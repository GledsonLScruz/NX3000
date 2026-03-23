import Foundation
import Network

actor NX3000CameraClient {
    private let transport = NX3000TCPTransport()
    private let parser = NX3000BrowseParser()
    private let fileStore = MediaFileStore()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = .shared
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    func resetSession() {
    }

    func handshake() async throws {
        let config = currentConfig()
        let request = NX3000RequestBuilder.makeHandshakeRequest(config: config)

        do {
            _ = try await transport.send(
                host: config.cameraIP,
                port: config.controlPort,
                requestData: request,
                timeout: config.socketTimeout
            )
        } catch let error as NX3000Error {
            throw NX3000Error.handshakeFailed(error.localizedDescription)
        } catch {
            throw NX3000Error.handshakeFailed(error.localizedDescription)
        }
    }

    func browse(startingIndex: Int, requestedCount: Int) async throws -> BrowsePage {
        let config = currentConfig()
        let request = NX3000RequestBuilder.makeBrowseRequest(
            config: config,
            startingIndex: startingIndex,
            requestedCount: requestedCount
        )

        do {
            let responseData = try await transport.send(
                host: config.cameraIP,
                port: config.browsePort,
                requestData: request,
                timeout: config.socketTimeout
            )
            return try parser.parseBrowseResponse(responseData)
        } catch let error as NX3000Error {
            throw NX3000Error.browseFailed(error.localizedDescription)
        } catch {
            throw NX3000Error.browseFailed(error.localizedDescription)
        }
    }

    func downloadOriginal(for asset: MediaAsset) async throws -> URL {
        do {
            return try await fileStore.cachedOriginal(for: asset, session: session)
        } catch let error as NX3000Error {
            throw error
        } catch {
            throw NX3000Error.downloadFailed(error.localizedDescription)
        }
    }

    private func currentConfig() -> NX3000CameraConfig {
        NX3000CameraConfig(
            hostMAC: HostIdentityStore.currentHostMAC(),
            hostAddress: LocalIPv4AddressProvider.currentAddress() ?? "192.168.107.11"
        )
    }
}

private enum HostIdentityStore {
    private static let defaultsKey = "NX3000HostMACAddress"

    static func currentHostMAC() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let uuid = UUID().uuid
        let bytes = withUnsafeBytes(of: uuid) { Array($0.prefix(6)) }
        var macBytes = bytes
        macBytes[0] = (macBytes[0] | 0x02) & 0xFE

        let macAddress = macBytes
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")

        defaults.set(macAddress, forKey: defaultsKey)
        return macAddress
    }
}

private enum LocalIPv4AddressProvider {
    static func currentAddress() -> String? {
        if let wifiAddress = ipv4Address(forPreferredInterface: "en0") {
            return wifiAddress
        }
        return firstNonLoopbackIPv4Address()
    }

    private static func ipv4Address(forPreferredInterface preferredInterface: String) -> String? {
        guard let interfaces = interfaces() else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: interfaces, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == preferredInterface else { continue }
            return numericHostString(from: address)
        }

        return nil
    }

    private static func firstNonLoopbackIPv4Address() -> String? {
        guard let interfaces = interfaces() else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: interfaces, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard !isLoopback else { continue }
            return numericHostString(from: address)
        }

        return nil
    }

    private static func interfaces() -> UnsafeMutablePointer<ifaddrs>? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        return pointer
    }

    private static func numericHostString(from sockaddrPointer: UnsafeMutablePointer<sockaddr>) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            sockaddrPointer,
            socklen_t(sockaddrPointer.pointee.sa_len),
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: hostBuffer)
    }
}

private actor MediaFileStore {
    private let fileManager = FileManager.default
    private lazy var cacheDirectoryURL: URL = {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseDirectory.appendingPathComponent("NX3000Originals", isDirectory: true)
    }()

    func cachedOriginal(for asset: MediaAsset, session: URLSession) async throws -> URL {
        try ensureCacheDirectory()

        let destinationURL = cacheDirectoryURL.appendingPathComponent(asset.suggestedFilename)
        if fileManager.fileExists(atPath: destinationURL.path()) {
            return destinationURL
        }

        let temporaryResult: URL
        let response: URLResponse

        do {
            (temporaryResult, response) = try await session.download(from: asset.fullContentURL)
        } catch {
            throw NX3000Error.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw NX3000Error.downloadFailed("HTTP status \(httpResponse.statusCode)")
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path()) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryResult, to: destinationURL)
        } catch {
            throw NX3000Error.downloadFailed(error.localizedDescription)
        }

        return destinationURL
    }

    private func ensureCacheDirectory() throws {
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path()) {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }
}

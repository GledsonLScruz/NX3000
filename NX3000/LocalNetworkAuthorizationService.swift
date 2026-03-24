import Foundation
import Network
import dnssd

enum LocalNetworkAuthorizationStatus: Sendable {
    case granted
    case denied
    case failed(String)
}

@MainActor
final class LocalNetworkAuthorizationService {
    private var activeRequests: [UUID: LocalNetworkAuthorizationRequest] = [:]

    func requestAuthorization() async -> LocalNetworkAuthorizationStatus {
        let requestID = UUID()

        return await withCheckedContinuation { continuation in
            let request = LocalNetworkAuthorizationRequest(
                id: requestID,
                continuation: continuation
            ) { [weak self] finishedRequestID in
                self?.activeRequests[finishedRequestID] = nil
            }

            activeRequests[requestID] = request
            request.start()
        }
    }
}

@MainActor
private final class LocalNetworkAuthorizationRequest: NSObject, NetServiceDelegate {
    private static let serviceType = "_nx3kperm._tcp"

    private let id: UUID
    private let continuation: CheckedContinuation<LocalNetworkAuthorizationStatus, Never>
    private let onFinish: (UUID) -> Void
    private let browser: NWBrowser
    private let browserQueue = DispatchQueue(label: "NX3000.LocalNetworkAuthorization")
    private let netService: NetService

    private var hasCompleted = false
    private var browserReady = false
    private var netServicePublished = false
    private var timeoutTask: Task<Void, Never>?

    init(
        id: UUID,
        continuation: CheckedContinuation<LocalNetworkAuthorizationStatus, Never>,
        onFinish: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.continuation = continuation
        self.onFinish = onFinish
        self.browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        self.netService = NetService(
            domain: "local.",
            type: Self.serviceType,
            name: UUID().uuidString,
            port: 9
        )

        super.init()
    }

    func start() {
        netService.delegate = self
        netService.schedule(in: .main, forMode: .default)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserState(state)
            }
        }
        browser.browseResultsChangedHandler = { _, _ in
        }

        browser.start(queue: browserQueue)
        netService.publish()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                self?.handleTimeout()
            }
        }
    }

    func netServiceDidPublish(_ sender: NetService) {
        netServicePublished = true
        resolveIfGranted()
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? 0
        finish(with: .failed("The local network permission request could not be published. NetService error \(code)."))
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            browserReady = true
            resolveIfGranted()
        case .waiting(let error):
            handleBrowserError(error)
        case .failed(let error):
            handleBrowserError(error)
        default:
            break
        }
    }

    private func handleBrowserError(_ error: NWError) {
        if Self.isPolicyDenied(error) {
            finish(with: .denied)
            return
        }

        finish(with: .failed("The local network permission request failed. \(error.localizedDescription)"))
    }

    private func resolveIfGranted() {
        guard browserReady, netServicePublished else { return }
        finish(with: .granted)
    }

    private func handleTimeout() {
        finish(with: .failed("Timed out while checking Local Network access."))
    }

    private func finish(with status: LocalNetworkAuthorizationStatus) {
        guard !hasCompleted else { return }
        hasCompleted = true

        timeoutTask?.cancel()
        browser.cancel()
        netService.stop()
        netService.remove(from: .main, forMode: .default)

        continuation.resume(returning: status)
        onFinish(id)
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        guard case let .dns(dnsError) = error else { return false }
        return dnsError == kDNSServiceErr_PolicyDenied
    }
}

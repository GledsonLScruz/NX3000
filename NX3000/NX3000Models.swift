import Foundation

struct NX3000CameraConfig: Sendable {
    static let defaultCameraIP = "192.168.107.1"
    static let defaultControlPort: UInt16 = 7788
    static let defaultBrowsePort: UInt16 = 7676

    let cameraIP: String
    let controlPort: UInt16
    let browsePort: UInt16
    let hostMAC: String
    let hostAddress: String
    let hostPort: UInt16
    let hostPNumber: String
    let socketTimeout: TimeInterval

    init(
        cameraIP: String = NX3000CameraConfig.defaultCameraIP,
        controlPort: UInt16 = NX3000CameraConfig.defaultControlPort,
        browsePort: UInt16 = NX3000CameraConfig.defaultBrowsePort,
        hostMAC: String,
        hostAddress: String,
        hostPort: UInt16 = 7788,
        hostPNumber: String = "none",
        socketTimeout: TimeInterval = 6.0
    ) {
        self.cameraIP = cameraIP
        self.controlPort = controlPort
        self.browsePort = browsePort
        self.hostMAC = hostMAC
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.hostPNumber = hostPNumber
        self.socketTimeout = socketTimeout
    }
}

enum MediaAssetType: String, Sendable {
    case image
    case video

    var badgeTitle: String {
        switch self {
        case .image:
            return "PHOTO"
        case .video:
            return "VIDEO"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .image:
            return "photo"
        case .video:
            return "video"
        }
    }
}

struct MediaAsset: Identifiable, Hashable, Sendable {
    let title: String
    let date: Date
    let type: MediaAssetType
    let fullContentURL: URL
    let thumbnailURL: URL?
    let screenImageURL: URL?
    let fileExtension: String
    let protocolInfo: String

    var id: String {
        fullContentURL.absoluteString
    }

    var previewURL: URL {
        thumbnailURL ?? screenImageURL ?? fullContentURL
    }

    var gridPreviewURL: URL {
        switch type {
        case .image:
            return screenImageURL ?? thumbnailURL ?? fullContentURL
        case .video:
            return thumbnailURL ?? screenImageURL ?? fullContentURL
        }
    }

    var displayURL: URL {
        screenImageURL ?? fullContentURL
    }

    var formattedDate: String {
        MediaAsset.dateFormatter.string(from: date)
    }

    var suggestedFilename: String {
        let lastPathComponent = fullContentURL.lastPathComponent
        if !lastPathComponent.isEmpty {
            return sanitizeFilename(lastPathComponent)
        }

        let sanitizedTitle = sanitizeFilename(title)
        let fallbackExtension = fileExtension.isEmpty ? "jpg" : fileExtension
        return "\(sanitizedTitle).\(fallbackExtension)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct BrowsePage: Sendable {
    let items: [MediaAsset]
    let numberReturned: Int
    let totalMatches: Int?
}

enum CameraConnectionState: Equatable {
    case checkingWiFi
    case needsWiFi
    case readyToConnect
    case connecting
    case connected
    case failed(String)
}

enum CameraSetupStep: Int, CaseIterable, Identifiable {
    case turnOnCamera = 1
    case openMobileLink
    case joinWiFi
    case returnToApp
    case checkConnection

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .turnOnCamera:
            return "Turn on the NX3000"
        case .openMobileLink:
            return "Open the camera Wi‑Fi / MobileLink mode"
        case .joinWiFi:
            return "Join the camera Wi‑Fi in iPhone or iPad Settings"
        case .returnToApp:
            return "Return to this app after the Wi‑Fi connection completes"
        case .checkConnection:
            return "Tap Check Connection to load the camera library"
        }
    }

    var subtitle: String {
        switch self {
        case .turnOnCamera:
            return "The camera must already be awake before the app can talk to it."
        case .openMobileLink:
            return "That mode exposes the local Wi‑Fi connection used for browsing photos."
        case .joinWiFi:
            return "The app cannot reach the camera until this device is on the camera’s network."
        case .returnToApp:
            return "You do not need to close the app; just switch back after connecting."
        case .checkConnection:
            return "The app will run the handshake, browse the library, and show the grid."
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

func sanitizeFilename(_ value: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let cleaned = value.components(separatedBy: invalidCharacters).joined(separator: "_")
    let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "NX3000" : trimmed
}

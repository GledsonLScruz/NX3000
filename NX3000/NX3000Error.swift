import Foundation

enum NX3000Error: LocalizedError {
    case noWiFiConnection
    case timeout(TimeInterval)
    case invalidHTTPResponse
    case missingHTTPBody
    case handshakeFailed(String)
    case browseFailed(String)
    case transportFailed(String)
    case parseFailed(String)
    case downloadFailed(String)
    case invalidURL(String)
    case photoLibraryAccessDenied
    case photoLibrarySaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWiFiConnection:
            return "Connect this device to the Samsung NX3000 Wi‑Fi network first."
        case .timeout(let seconds):
            return "The camera did not respond within \(Int(seconds)) seconds."
        case .invalidHTTPResponse:
            return "The camera returned an invalid HTTP response."
        case .missingHTTPBody:
            return "The camera response did not include the expected XML body."
        case .handshakeFailed(let details):
            return "Could not complete the camera handshake. \(details)"
        case .browseFailed(let details):
            return "Could not load photos from the camera. \(details)"
        case .transportFailed(let details):
            return "Could not reach the camera over the local network. \(details)"
        case .parseFailed(let details):
            return "The camera response could not be parsed. \(details)"
        case .downloadFailed(let details):
            return "The file could not be downloaded. \(details)"
        case .invalidURL(let value):
            return "The camera returned an invalid media URL: \(value)"
        case .photoLibraryAccessDenied:
            return "Photos access is required to save into the NX3000 album."
        case .photoLibrarySaveFailed(let details):
            return "The file could not be saved to Photos. \(details)"
        }
    }
}

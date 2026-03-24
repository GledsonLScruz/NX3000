import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var connectionState: CameraConnectionState = .checkingWiFi
    @Published private(set) var mediaItems: [MediaAsset] = []
    @Published private(set) var isCheckingConnection = false
    @Published private(set) var isLoadingInitialPage = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isProcessingAssetAction = false
    @Published private(set) var assetActionMessage = ""
    @Published var showsLocalNetworkSettingsAlert = false
    @Published var selectedAsset: MediaAsset?
    @Published var activeShareItem: ShareItem?
    @Published var activeAlert: AlertContext?

    let networkStatusService = NetworkStatusService()

    private let cameraClient = NX3000CameraClient()
    private let localNetworkAuthorizationService = LocalNetworkAuthorizationService()
    private let photoLibraryService = PhotoLibraryService()
    private var cancellables: Set<AnyCancellable> = []
    private let pageSize = 50
    private var nextStartIndex = 0
    private var totalMatches: Int?
    private var reachedEndOfBrowseResults = false
    private var localNetworkPermissionDenied = false
    private var hasCompletedHandshake = false
    private var hasHandledLaunch = false

    init() {
        networkStatusService.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleNetworkSnapshot(snapshot)
            }
            .store(in: &cancellables)
    }

    var showsBrowser: Bool {
        connectionState == .connected
    }

    var connectionBadgeTitle: String {
        switch connectionState {
        case .checkingWiFi:
            return "Preparing Connection"
        case .needsWiFi:
            return "Wi‑Fi Required"
        case .needsLocalNetworkPermission:
            return "Local Network Access"
        case .readyToConnect:
            return "Ready to Connect"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .handshakeFailed:
            return "Connection Failed"
        case .browseFailed:
            return "Browse Failed"
        }
    }

    var connectionBadgeSymbol: String {
        switch connectionState {
        case .connected:
            return "wifi"
        case .needsLocalNetworkPermission:
            return "lock.shield"
        case .handshakeFailed, .browseFailed:
            return "exclamationmark.triangle"
        case .needsWiFi:
            return "wifi.slash"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }

    var connectionBadgeColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .needsLocalNetworkPermission:
            return AppTheme.primaryPink
        case .handshakeFailed, .browseFailed:
            return .red
        case .needsWiFi:
            return AppTheme.primaryPink
        default:
            return .blue
        }
    }

    var connectionMessage: String {
        switch connectionState {
        case .checkingWiFi:
            return "Preparing the connection flow before trying the camera."
        case .needsWiFi:
            return "Join the Samsung NX3000 Wi‑Fi network, then come back and continue."
        case .needsLocalNetworkPermission:
            return "Allow Local Network access so the app can find and reach the camera on Wi‑Fi."
        case .readyToConnect:
            return "The app can now try the NX3000 handshake."
        case .connecting:
            return "Talking to the camera and loading the first page of media."
        case .connected:
            return "The camera is connected and ready."
        case .handshakeFailed:
            return "The camera did not respond. Confirm you joined the camera’s network and that MobileLink is still open."
        case .browseFailed:
            return "The camera responded, but loading the media list failed. Try the browse request again."
        }
    }

    var lastConnectionError: String? {
        switch connectionState {
        case .handshakeFailed(let message), .browseFailed(let message):
            return message
        default:
            return nil
        }
    }

    var mediaSubtitle: String {
        if isLoadingInitialPage && mediaItems.isEmpty {
            return "Loading photos from the camera..."
        }

        if let totalMatches {
            return "\(mediaItems.count) of \(totalMatches) loaded"
        }

        return "\(mediaItems.count) items loaded"
    }

    var transientStatusMessage: String? {
        if isLoadingInitialPage {
            return "Loading the first page"
        }
        if isLoadingNextPage {
            return "Loading more photos"
        }
        return nil
    }

    func handleAppLaunch() async {
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true
        _ = await ensureLocalNetworkPermission(promptForSettingsOnDenial: true)
        if networkStatusService.snapshot.isResolved {
            handleNetworkSnapshot(networkStatusService.snapshot)
        }
    }

    func checkConnectionAndLoad() async {
        guard await ensureLocalNetworkPermission(promptForSettingsOnDenial: true) else {
            return
        }

        isCheckingConnection = true
        connectionState = .connecting

        defer {
            isCheckingConnection = false
        }

        do {
            try await cameraClient.handshake()
            hasCompletedHandshake = true
            connectionState = .connected
            await reload()
        } catch {
            hasCompletedHandshake = false
            mediaItems = []
            connectionState = .handshakeFailed(error.localizedDescription)
        }
    }

    func reload() async {
        guard hasCompletedHandshake else {
            await checkConnectionAndLoad()
            return
        }

        isLoadingInitialPage = true
        nextStartIndex = 0
        totalMatches = nil
        reachedEndOfBrowseResults = false
        mediaItems = []

        defer {
            isLoadingInitialPage = false
        }

        await loadPage(startingIndex: 0, replaceExisting: true)
    }

    func loadNextPageIfNeeded(after asset: MediaAsset) async {
        guard connectionState == .connected else { return }
        guard !isLoadingInitialPage, !isLoadingNextPage else { return }
        guard hasMorePages else { return }

        let thresholdIndex = mediaItems.index(mediaItems.endIndex, offsetBy: -6, limitedBy: mediaItems.startIndex) ?? mediaItems.startIndex
        guard let currentIndex = mediaItems.firstIndex(of: asset), currentIndex >= thresholdIndex else {
            return
        }

        isLoadingNextPage = true
        defer {
            isLoadingNextPage = false
        }

        await loadPage(startingIndex: nextStartIndex, replaceExisting: false)
    }

    func prepareShare(for asset: MediaAsset) async {
        isProcessingAssetAction = true
        assetActionMessage = "Preparing share..."

        defer {
            isProcessingAssetAction = false
            assetActionMessage = ""
        }

        do {
            let localURL = try await cameraClient.downloadOriginal(for: asset)
            activeShareItem = ShareItem(url: localURL)
        } catch {
            activeAlert = AlertContext(
                title: "Share Failed",
                message: error.localizedDescription
            )
        }
    }

    func saveToPhotoLibrary(_ asset: MediaAsset) async {
        isProcessingAssetAction = true
        assetActionMessage = "Saving to Photos..."

        defer {
            isProcessingAssetAction = false
            assetActionMessage = ""
        }

        do {
            let localURL = try await cameraClient.downloadOriginal(for: asset)
            try await photoLibraryService.saveAsset(at: localURL, type: asset.type)
            activeAlert = AlertContext(
                title: "Saved",
                message: "\(asset.title) was added to the NX3000 album in Photos."
            )
        } catch {
            activeAlert = AlertContext(
                title: "Save Failed",
                message: error.localizedDescription
            )
        }
    }

    private var hasMorePages: Bool {
        if let totalMatches {
            return mediaItems.count < totalMatches
        }
        return !reachedEndOfBrowseResults
    }

    private func ensureLocalNetworkPermission(promptForSettingsOnDenial: Bool) async -> Bool {
        switch await localNetworkAuthorizationService.requestAuthorization() {
        case .granted:
            let shouldRefreshConnectionState = localNetworkPermissionDenied
            localNetworkPermissionDenied = false
            showsLocalNetworkSettingsAlert = false

            if shouldRefreshConnectionState, networkStatusService.snapshot.isResolved {
                handleNetworkSnapshot(networkStatusService.snapshot)
            }

            return true
        case .denied:
            localNetworkPermissionDenied = true
            connectionState = .needsLocalNetworkPermission

            if promptForSettingsOnDenial {
                showsLocalNetworkSettingsAlert = true
            }

            return false
        case .failed(let message):
            if promptForSettingsOnDenial {
                activeAlert = AlertContext(
                    title: "Local Network Check Failed",
                    message: message
                )
            }
            return true
        }
    }

    private func handleNetworkSnapshot(_ snapshot: NetworkSnapshot) {
        if localNetworkPermissionDenied {
            connectionState = .needsLocalNetworkPermission
            return
        }

        guard snapshot.isResolved else {
            connectionState = .checkingWiFi
            return
        }

        if connectionState != .connected && connectionState != .connecting {
            connectionState = .readyToConnect
        }
    }

    private func loadPage(startingIndex: Int, replaceExisting: Bool) async {
        do {
            let page = try await cameraClient.browse(
                startingIndex: startingIndex,
                requestedCount: pageSize
            )

            totalMatches = page.totalMatches
            nextStartIndex = startingIndex + page.numberReturned
            reachedEndOfBrowseResults = page.totalMatches == nil && page.numberReturned < pageSize

            if replaceExisting {
                mediaItems = page.items
            } else {
                let existingIDs = Set(mediaItems.map { $0.id })
                mediaItems.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            }
        } catch {
            if replaceExisting {
                connectionState = .browseFailed(error.localizedDescription)
            } else {
                activeAlert = AlertContext(
                    title: "Pagination Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}

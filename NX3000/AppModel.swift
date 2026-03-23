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
    @Published var selectedAsset: MediaAsset?
    @Published var activeShareItem: ShareItem?
    @Published var activeAlert: AlertContext?

    let networkStatusService = NetworkStatusService()

    private let cameraClient = NX3000CameraClient()
    private let photoLibraryService = PhotoLibraryService()
    private var cancellables: Set<AnyCancellable> = []
    private let pageSize = 50
    private var nextStartIndex = 0
    private var totalMatches: Int?
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
            return "Checking Wi‑Fi"
        case .needsWiFi:
            return "Wi‑Fi Required"
        case .readyToConnect:
            return "Ready to Connect"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .failed:
            return "Connection Failed"
        }
    }

    var connectionBadgeSymbol: String {
        switch connectionState {
        case .connected:
            return "wifi"
        case .failed:
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
        case .failed:
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
            return "Looking for a Wi‑Fi connection before trying the camera."
        case .needsWiFi:
            return "Join the Samsung NX3000 Wi‑Fi network, then come back and continue."
        case .readyToConnect:
            return "Wi‑Fi is available. The app can now try the NX3000 handshake."
        case .connecting:
            return "Talking to the camera and loading the first page of media."
        case .connected:
            return "The camera is connected and ready."
        case .failed:
            return "The camera did not respond. Confirm you joined the camera’s network and that MobileLink is still open."
        }
    }

    var lastConnectionError: String? {
        guard case let .failed(message) = connectionState else { return nil }
        return message
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
        if networkStatusService.snapshot.isResolved {
            handleNetworkSnapshot(networkStatusService.snapshot)
        }
    }

    func checkConnectionAndLoad() async {
        guard networkStatusService.snapshot.isWiFiConnected else {
            connectionState = .needsWiFi
            activeAlert = AlertContext(
                title: "Wi‑Fi Required",
                message: NX3000Error.noWiFiConnection.localizedDescription
            )
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
            connectionState = .failed(error.localizedDescription)
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
        return true
    }

    private func handleNetworkSnapshot(_ snapshot: NetworkSnapshot) {
        guard snapshot.isResolved else {
            connectionState = .checkingWiFi
            return
        }

        guard snapshot.isWiFiConnected else {
            mediaItems = []
            nextStartIndex = 0
            totalMatches = nil
            hasCompletedHandshake = false
            connectionState = .needsWiFi
            Task {
                await cameraClient.resetSession()
            }
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

            if replaceExisting {
                mediaItems = page.items
            } else {
                let existingIDs = Set(mediaItems.map { $0.id })
                mediaItems.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            }

            if page.numberReturned == 0 && page.totalMatches == nil {
                nextStartIndex = mediaItems.count
            }
        } catch {
            if replaceExisting {
                connectionState = .failed(error.localizedDescription)
            } else {
                activeAlert = AlertContext(
                    title: "Pagination Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}

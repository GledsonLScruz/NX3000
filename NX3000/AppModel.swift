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
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedAssetIDs: Set<String> = []
    @Published private(set) var isRunningBatchDownload = false
    @Published private(set) var batchProgress: BatchDownloadProgress?
    @Published var showsLocalNetworkSettingsAlert = false
    @Published var selectedAsset: MediaAsset?
    @Published var activeShareItem: ShareItem?
    @Published var activeAlert: AlertContext?
    @Published var activeBatchFailurePrompt: BatchFailurePromptContext?

    let networkStatusService = NetworkStatusService()

    private let cameraClient = NX3000CameraClient()
    private let localNetworkAuthorizationService = LocalNetworkAuthorizationService()
    private let photoLibraryService = PhotoLibraryService()
    private let batchLiveActivityController = BatchDownloadLiveActivityController()
    private var cancellables: Set<AnyCancellable> = []
    private let pageSize = 50
    private var nextStartIndex = 0
    private var totalMatches: Int?
    private var reachedEndOfBrowseResults = false
    private var localNetworkPermissionDenied = false
    private var hasCompletedHandshake = false
    private var hasHandledLaunch = false
    private var batchFailureContinuation: CheckedContinuation<BatchFailureChoice, Never>?

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

        if isSelectionMode {
            let noun = selectedImageCount == 1 ? "photo" : "photos"
            return "\(selectedImageCount) \(noun) selected"
        }

        if let totalMatches {
            return "\(mediaItems.count) of \(totalMatches) loaded"
        }

        return "\(mediaItems.count) items loaded"
    }

    var transientStatusMessage: String? {
        if let batchProgress {
            return batchProgress.statusMessage
        }
        if isLoadingInitialPage {
            return "Loading the first page"
        }
        if isLoadingNextPage {
            return "Loading more photos"
        }
        return nil
    }

    var canEnterSelectionMode: Bool {
        !isRunningBatchDownload && mediaItems.contains(where: canBatchSelect(_:))
    }

    var selectedImageCount: Int {
        selectedImageAssets.count
    }

    var allSelectableImagesSelected: Bool {
        let selectableIDs = Set(mediaItems.filter(canBatchSelect(_:)).map(\.id))
        guard !selectableIDs.isEmpty else { return false }
        return selectableIDs.isSubset(of: selectedAssetIDs)
    }

    var selectionToggleAllTitle: String {
        allSelectableImagesSelected ? "Clear All" : "Select All"
    }

    var batchActionTitle: String {
        if let batchProgress {
            return batchProgress.actionLabel
        }
        return selectedImageCount == 1 ? "Download 1 Photo" : "Download \(selectedImageCount) Photos"
    }

    var batchSelectionSummary: String {
        if let batchProgress {
            return batchProgress.summaryLabel
        }

        let noun = selectedImageCount == 1 ? "photo" : "photos"
        return "\(selectedImageCount) \(noun) ready for sequential save"
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

    func handleGridTap(on asset: MediaAsset) {
        guard !isRunningBatchDownload else { return }

        if isSelectionMode {
            toggleSelection(for: asset)
        } else {
            selectedAsset = asset
        }
    }

    func enterSelectionMode() {
        guard canEnterSelectionMode else { return }
        selectedAsset = nil
        isSelectionMode = true
    }

    func exitSelectionMode() {
        guard !isRunningBatchDownload else { return }
        clearSelection()
    }

    func toggleSelection(for asset: MediaAsset) {
        guard isSelectionMode else { return }
        guard canBatchSelect(asset) else { return }

        if selectedAssetIDs.contains(asset.id) {
            selectedAssetIDs.remove(asset.id)
        } else {
            selectedAssetIDs.insert(asset.id)
        }
    }

    func toggleSelectAll() {
        guard isSelectionMode else { return }

        let selectableIDs = Set(mediaItems.filter(canBatchSelect(_:)).map(\.id))
        guard !selectableIDs.isEmpty else { return }

        if allSelectableImagesSelected {
            selectedAssetIDs.subtract(selectableIDs)
        } else {
            selectedAssetIDs.formUnion(selectableIDs)
        }
    }

    func isAssetSelected(_ asset: MediaAsset) -> Bool {
        selectedAssetIDs.contains(asset.id)
    }

    func canBatchSelect(_ asset: MediaAsset) -> Bool {
        asset.type == .image
    }

    func startBatchDownload() async {
        guard !isRunningBatchDownload else { return }

        let assets = selectedImageAssets
        guard !assets.isEmpty else {
            activeAlert = AlertContext(
                title: "No Photos Selected",
                message: "Choose at least one photo before starting a batch download."
            )
            return
        }

        isRunningBatchDownload = true
        activeAlert = nil
        activeBatchFailurePrompt = nil
        selectedAsset = nil

        do {
            let batchSession = try await photoLibraryService.prepareBatchSession()
            let initialProgress = BatchDownloadProgress(
                totalCount: assets.count,
                processedCount: 0,
                savedCount: 0,
                failedCount: 0,
                currentAssetTitle: assets.first?.title,
                phase: .starting
            )
            batchProgress = initialProgress
            await batchLiveActivityController.start(with: initialProgress)

            var savedCount = 0
            var failedCount = 0
            var stoppedEarly = false

            for asset in assets {
                await updateBatchProgress(
                    totalCount: assets.count,
                    processedCount: savedCount + failedCount,
                    savedCount: savedCount,
                    failedCount: failedCount,
                    currentAssetTitle: asset.title,
                    phase: .downloading
                )

                do {
                    let localURL = try await cameraClient.downloadOriginal(for: asset)

                    await updateBatchProgress(
                        totalCount: assets.count,
                        processedCount: savedCount + failedCount,
                        savedCount: savedCount,
                        failedCount: failedCount,
                        currentAssetTitle: asset.title,
                        phase: .saving
                    )

                    try await batchSession.saveAsset(at: localURL, type: asset.type)
                    savedCount += 1
                } catch {
                    failedCount += 1

                    await updateBatchProgress(
                        totalCount: assets.count,
                        processedCount: savedCount + failedCount,
                        savedCount: savedCount,
                        failedCount: failedCount,
                        currentAssetTitle: asset.title,
                        phase: .awaitingDecision
                    )

                    let choice = await promptForBatchFailure(asset: asset, error: error)
                    if choice == .stop {
                        stoppedEarly = true
                        break
                    }
                }
            }

            let finalProgress = BatchDownloadProgress(
                totalCount: assets.count,
                processedCount: savedCount + failedCount,
                savedCount: savedCount,
                failedCount: failedCount,
                currentAssetTitle: nil,
                phase: stoppedEarly ? .stopped : .completed
            )

            batchProgress = finalProgress
            await batchLiveActivityController.end(with: finalProgress)
            finishBatchDownload(with: finalProgress)
        } catch {
            let failedProgress = BatchDownloadProgress(
                totalCount: assets.count,
                processedCount: 0,
                savedCount: 0,
                failedCount: 0,
                currentAssetTitle: nil,
                phase: .failedToStart
            )
            batchProgress = failedProgress
            await batchLiveActivityController.end(with: failedProgress)
            isRunningBatchDownload = false
            batchProgress = nil
            activeAlert = AlertContext(
                title: "Batch Download Failed",
                message: error.localizedDescription
            )
        }
    }

    func resolveBatchFailurePrompt(shouldContinue: Bool) {
        activeBatchFailurePrompt = nil

        guard let continuation = batchFailureContinuation else { return }
        batchFailureContinuation = nil
        continuation.resume(returning: shouldContinue ? .continueProcessing : .stop)
    }

    private var selectedImageAssets: [MediaAsset] {
        mediaItems.filter { selectedAssetIDs.contains($0.id) && canBatchSelect($0) }
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
                let existingIDs = Set(mediaItems.map(\.id))
                mediaItems.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            }

            reconcileSelectionState()
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

    private func reconcileSelectionState() {
        let availableIDs = Set(mediaItems.map(\.id))
        selectedAssetIDs = selectedAssetIDs.intersection(availableIDs)
        if isSelectionMode && selectedAssetIDs.isEmpty && !isRunningBatchDownload {
            isSelectionMode = false
        }
    }

    private func clearSelection() {
        isSelectionMode = false
        selectedAssetIDs.removeAll()
    }

    private func updateBatchProgress(
        totalCount: Int,
        processedCount: Int,
        savedCount: Int,
        failedCount: Int,
        currentAssetTitle: String?,
        phase: BatchDownloadProgress.Phase
    ) async {
        let progress = BatchDownloadProgress(
            totalCount: totalCount,
            processedCount: processedCount,
            savedCount: savedCount,
            failedCount: failedCount,
            currentAssetTitle: currentAssetTitle,
            phase: phase
        )
        batchProgress = progress
        await batchLiveActivityController.update(with: progress)
    }

    private func finishBatchDownload(with progress: BatchDownloadProgress) {
        isRunningBatchDownload = false
        activeBatchFailurePrompt = nil
        batchFailureContinuation = nil
        batchProgress = nil
        clearSelection()

        let savedLabel = progress.savedCount == 1 ? "1 photo was" : "\(progress.savedCount) photos were"
        let failureSuffix = progress.failedCount > 0 ? " \(progress.failedCount) failed." : ""
        let title = progress.phase == .stopped ? "Download Stopped" : "Download Complete"

        activeAlert = AlertContext(
            title: title,
            message: "\(savedLabel) saved to Photos.\(failureSuffix)"
        )
    }

    private func promptForBatchFailure(asset: MediaAsset, error: Error) async -> BatchFailureChoice {
        activeBatchFailurePrompt = BatchFailurePromptContext(
            assetTitle: asset.title,
            message: error.localizedDescription
        )

        return await withCheckedContinuation { continuation in
            batchFailureContinuation = continuation
        }
    }
}

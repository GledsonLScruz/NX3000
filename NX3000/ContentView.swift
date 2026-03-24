import SwiftUI
import AVKit
import UIKit

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if appModel.showsBrowser {
                    MediaGridView()
                } else {
                    ConnectionGuideView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await appModel.handleAppLaunch()
        }
        .alert(item: $appModel.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $appModel.activeShareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .fullScreenCover(item: $appModel.selectedAsset) { asset in
            MediaDetailView(items: appModel.mediaItems, initialAsset: asset)
                .environmentObject(appModel)
        }
    }
}

private struct ConnectionGuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("connectionGuideShowsSteps") private var showsSetupSteps = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.blush,
                    AppTheme.mist,
                    Color.white,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    statusCard
                    stepsCard
                    actionArea
                }
                .padding(20)
                .frame(maxWidth: 720)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NX3000")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text("Connect your iPhone or iPad to the camera first.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("This app talks directly to the Samsung NX3000 over the camera’s Wi‑Fi network, then loads your photos and videos.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryPink.opacity(0.18))
                    .frame(width: 92, height: 92)
                Image(systemName: "camera.macro.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.primaryPink, Color.black.opacity(0.1))
            }
            .padding(18)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appModel.connectionBadgeTitle, systemImage: appModel.connectionBadgeSymbol)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(appModel.connectionBadgeColor)

            Text(appModel.connectionMessage)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            if let error = appModel.lastConnectionError {
                Text(error)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Setup Steps")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsSetupSteps.toggle()
                    }
                } label: {
                    Label(showsSetupSteps ? "Hide" : "Show", systemImage: showsSetupSteps ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.softPink.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }

            Group {
                if showsSetupSteps {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(CameraSetupStep.allCases) { step in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(step.rawValue)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(AppTheme.primaryPink))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text(step.subtitle)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: showsSetupSteps)
    }

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task {
                    await appModel.checkConnectionAndLoad()
                }
            } label: {
                HStack {
                    if appModel.isCheckingConnection {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(appModel.isCheckingConnection ? "Checking Connection..." : "Check Connection")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryPink)
            .disabled(appModel.isCheckingConnection)

            Text("The app needs Wi‑Fi access, local network access, and Photos permission when you save images.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MediaGridView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        GeometryReader { proxy in
            let columns = gridColumns(for: proxy.size)

            ZStack {
                LinearGradient(
                    colors: [
                        AppTheme.blush,
                        AppTheme.mist,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    if appModel.mediaItems.isEmpty && !appModel.isLoadingInitialPage {
                        emptyState
                            .padding(.top, 40)
                            .padding(.horizontal, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(appModel.mediaItems) { asset in
                                MediaGridCell(asset: asset)
                                    .onTapGesture {
                                        appModel.selectedAsset = asset
                                    }
                                    .onAppear {
                                        Task {
                                            await appModel.loadNextPageIfNeeded(after: asset)
                                        }
                                    }
                            }

                            if appModel.isLoadingNextPage {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .gridCellColumns(columns.count)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera Roll")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(appModel.mediaSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await appModel.reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.95)))
                }
                .buttonStyle(.plain)
                .disabled(appModel.isLoadingInitialPage)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let message = appModel.transientStatusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.95)))
            }
        }
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(AppTheme.primaryPink)
            Text("No media was returned")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("The camera connected successfully, but this page came back empty. Pull to refresh or try reconnecting from the camera.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
    }

    private func gridColumns(for size: CGSize) -> [GridItem] {
        let horizontalPadding: CGFloat = 32
        let spacing: CGFloat = 14
        let minimumItemWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 200 : 156
        let availableWidth = max(size.width - horizontalPadding, minimumItemWidth)
        let columnCount = max(2, Int((availableWidth + spacing) / (minimumItemWidth + spacing)))

        return Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: columnCount
        )
    }
}

private struct MediaGridCell: View {
    let asset: MediaAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(AppTheme.softPink.opacity(0.2))
                    .overlay {
                        SerializedGridThumbnail(url: asset.gridPreviewURL, type: asset.type)
                    }
                    .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Image(systemName: asset.type.badgeSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .foregroundStyle(.white)
                    .padding(10)
            }

            Text(asset.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text(asset.formattedDate)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
    }
}

private struct MediaDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let items: [MediaAsset]
    @State private var selectedID: String

    init(items: [MediaAsset], initialAsset: MediaAsset) {
        self.items = items
        _selectedID = State(initialValue: initialAsset.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(items) { asset in
                    MediaDetailPage(asset: asset)
                        .tag(asset.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            VStack {
                HStack {
                    chromeButton(systemName: "xmark") {
                        dismiss()
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        chromeButton(systemName: "arrow.down.circle") {
                            Task {
                                await appModel.saveToPhotoLibrary(currentAsset)
                            }
                        }
                        .disabled(appModel.isProcessingAssetAction)

                        chromeButton(systemName: "square.and.arrow.up") {
                            Task {
                                await appModel.prepareShare(for: currentAsset)
                            }
                        }
                        .disabled(appModel.isProcessingAssetAction)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentAsset.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(currentAsset.formattedDate)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 52)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            if appModel.isProcessingAssetAction {
                ProgressView(appModel.assetActionMessage)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentAsset: MediaAsset {
        items.first(where: { $0.id == selectedID }) ?? items[0]
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.42)))
        }
        .buttonStyle(.plain)
    }
}

private struct MediaDetailPage: View {
    let asset: MediaAsset
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if asset.type == .video {
                VideoPlayer(player: player)
                    .onAppear {
                        let avPlayer = AVPlayer(url: asset.fullContentURL)
                        player = avPlayer
                        avPlayer.play()
                    }
                    .onDisappear {
                        player?.pause()
                    }
            } else {
                MediaPreviewImageView(url: asset.displayURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaPreviewImageView: View {
    let url: URL

    @State private var phase: Phase = .loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)

                    Text("Loading image...")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
            case .success(let image):
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            case .failure:
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Could not load this image")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .task(id: url) {
            await loadImage()
        }
        .animation(.easeInOut(duration: 0.2), value: phase.id)
    }

    @MainActor
    private func loadImage() async {
        phase = .loading

        do {
            let data = try await CameraPreviewLoader.shared.previewData(for: url)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                phase = .failure
                return
            }
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure
        }
    }

    private enum Phase {
        case loading
        case success(UIImage)
        case failure

        var id: Int {
            switch self {
            case .loading:
                return 0
            case .success:
                return 1
            case .failure:
                return 2
            }
        }
    }
}

private struct SerializedGridThumbnail: View {
    let url: URL
    let type: MediaAssetType

    @State private var phase: Phase = .loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(AppTheme.primaryPink)
            case .success(let image):
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            case .failure:
                Image(systemName: type == .image ? "photo" : "video")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        phase = .loading

        do {
            let data = try await CameraPreviewLoader.shared.previewData(for: url)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                phase = .failure
                return
            }
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure
        }
    }

    private enum Phase {
        case loading
        case success(UIImage)
        case failure
    }
}

private actor CameraPreviewLoader {
    static let shared = CameraPreviewLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data, Error>] = [:]
    private var tailTask: Task<Void, Never>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 180
    }

    func previewData(for url: URL) async throws -> Data {
        if let cachedData = memoryCache.object(forKey: url as NSURL) {
            return Data(referencing: cachedData)
        }

        if let existingTask = inFlight[url] {
            return try await existingTask.value
        }

        let previousTask = tailTask
        let task = Task<Data, Error> {
            await previousTask?.value
            return try await self.fetchPreviewDataWithRetry(from: url)
        }

        inFlight[url] = task
        tailTask = Task {
            _ = try? await task.value
        }

        do {
            let data = try await task.value
            memoryCache.setObject(data as NSData, forKey: url as NSURL)
            inFlight[url] = nil
            return data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private func fetchPreviewDataWithRetry(from url: URL) async throws -> Data {
        var lastError: Error = PreviewLoadError.invalidImageData

        for attempt in 0..<3 {
            try Task.checkCancellation()

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 20

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    throw PreviewLoadError.invalidResponse(httpResponse.statusCode)
                }

                guard !data.isEmpty, UIImage(data: data) != nil else {
                    throw PreviewLoadError.invalidImageData
                }

                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }

        throw lastError
    }

    private enum PreviewLoadError: Error {
        case invalidImageData
        case invalidResponse(Int)
    }
}

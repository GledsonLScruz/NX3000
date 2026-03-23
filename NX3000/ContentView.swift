import SwiftUI
import AVKit

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
            Text("Setup Steps")
                .font(.system(size: 20, weight: .bold, design: .rounded))

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
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
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
                            .padding(.top, 120)
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
            .overlay(alignment: .top) {
                header
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 88)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera Roll")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(appModel.mediaSubtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await appModel.reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .bold))
                        .padding(12)
                        .background(Circle().fill(Color.white.opacity(0.95)))
                }
                .buttonStyle(.plain)
                .disabled(appModel.isLoadingInitialPage)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let message = appModel.transientStatusMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.95)))
            }
        }
        .padding(.bottom, 10)
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
        let isPhonePortrait = UIDevice.current.userInterfaceIdiom == .phone && size.height > size.width
        if isPhonePortrait {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        }

        let minimumWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 180 : 150
        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 220), spacing: 12)]
    }
}

private struct MediaGridCell: View {
    let asset: MediaAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: asset.previewURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(AppTheme.softPink.opacity(0.35))
                            .overlay {
                                ProgressView()
                                    .tint(AppTheme.primaryPink)
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.12))
                            .overlay {
                                Image(systemName: asset.type == .image ? "photo" : "video")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                    @unknown default:
                        Color.gray.opacity(0.1)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Label(asset.type.badgeTitle, systemImage: asset.type.badgeSymbol)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
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
                .padding(20)
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
                AsyncImage(url: asset.displayURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    @unknown default:
                        Color.black
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

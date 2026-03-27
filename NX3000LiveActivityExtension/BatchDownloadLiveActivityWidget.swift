import ActivityKit
import SwiftUI
import WidgetKit

struct BatchDownloadLiveActivityWidget: Widget {
    private let activityBackground = Color(red: 0.96, green: 0.92, blue: 0.95)
    private let primaryText = Color.black.opacity(0.92)
    private let secondaryText = Color.black.opacity(0.64)
    private let accent = Color(red: 0.84, green: 0.18, blue: 0.41)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BatchDownloadActivityAttributes.self) { context in
            BatchDownloadActivityView(
                state: context.state,
                primaryText: primaryText,
                secondaryText: secondaryText,
                accent: accent
            )
                .activityBackgroundTint(activityBackground)
                .activitySystemActionForegroundColor(primaryText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.savedCount)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.processedCount)/\(context.state.totalCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusMessage)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(primaryText)
                        Text(context.state.currentAssetTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: Double(context.state.processedCount), total: Double(max(context.state.totalCount, 1)))
                        .tint(accent)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text("\(context.state.processedCount)/\(context.state.totalCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(accent)
            }
        }
    }
}

private struct BatchDownloadActivityView: View {
    let state: BatchDownloadActivityAttributes.ContentState
    let primaryText: Color
    let secondaryText: Color
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.statusMessage)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(primaryText)
                    Text(state.currentAssetTitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(state.processedCount)/\(state.totalCount)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(primaryText)
            }

            ProgressView(value: Double(state.processedCount), total: Double(max(state.totalCount, 1)))
                .tint(accent)

            HStack(spacing: 16) {
                statLabel(title: "Saved", value: state.savedCount)
                statLabel(title: "Failed", value: state.failedCount)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLabel(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryText)
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
        }
    }
}

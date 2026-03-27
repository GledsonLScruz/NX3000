import ActivityKit
import Foundation

actor BatchDownloadLiveActivityController {
    private var activity: Activity<BatchDownloadActivityAttributes>?

    func start(with progress: BatchDownloadProgress) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let activity {
            await end(activity: activity, with: progress)
        }

        let attributes = BatchDownloadActivityAttributes(id: UUID())
        let content = ActivityContent(state: state(for: progress), staleDate: nil)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(with progress: BatchDownloadProgress) async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: state(for: progress), staleDate: nil))
    }

    func end(with progress: BatchDownloadProgress) async {
        guard let activity else { return }
        await end(activity: activity, with: progress)
        self.activity = nil
    }

    private func end(activity: Activity<BatchDownloadActivityAttributes>, with progress: BatchDownloadProgress) async {
        await activity.end(
            ActivityContent(state: state(for: progress), staleDate: nil),
            dismissalPolicy: .default
        )
    }

    private func state(for progress: BatchDownloadProgress) -> BatchDownloadActivityAttributes.ContentState {
        BatchDownloadActivityAttributes.ContentState(
            totalCount: progress.totalCount,
            processedCount: progress.processedCount,
            savedCount: progress.savedCount,
            failedCount: progress.failedCount,
            currentAssetTitle: progress.currentAssetTitle ?? "NX3000",
            statusMessage: progress.liveActivityStatus
        )
    }
}

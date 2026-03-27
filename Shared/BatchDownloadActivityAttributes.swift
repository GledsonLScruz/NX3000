import ActivityKit
import Foundation

struct BatchDownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let totalCount: Int
        let processedCount: Int
        let savedCount: Int
        let failedCount: Int
        let currentAssetTitle: String
        let statusMessage: String
    }

    let id: UUID
}

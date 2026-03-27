import Foundation

struct BatchFailurePromptContext: Identifiable {
    let id = UUID()
    let assetTitle: String
    let message: String
}

enum BatchFailureChoice {
    case continueProcessing
    case stop
}

struct BatchDownloadProgress: Equatable {
    enum Phase: Equatable {
        case starting
        case downloading
        case saving
        case awaitingDecision
        case completed
        case stopped
        case failedToStart
    }

    let totalCount: Int
    let processedCount: Int
    let savedCount: Int
    let failedCount: Int
    let currentAssetTitle: String?
    let phase: Phase

    var statusMessage: String {
        switch phase {
        case .starting:
            return "Preparing batch download"
        case .downloading:
            return progressPrefix + currentItemSuffix("Downloading")
        case .saving:
            return progressPrefix + currentItemSuffix("Saving")
        case .awaitingDecision:
            return progressPrefix + "Waiting for your decision"
        case .completed:
            return summaryLabel
        case .stopped:
            return "Stopped after saving \(savedCount) of \(totalCount)"
        case .failedToStart:
            return "Could not start batch download"
        }
    }

    var summaryLabel: String {
        if failedCount == 0 {
            return "Saved \(savedCount) of \(totalCount) photos"
        }
        return "Saved \(savedCount) of \(totalCount), \(failedCount) failed"
    }

    var actionLabel: String {
        switch phase {
        case .starting, .downloading, .saving:
            return "Downloading..."
        case .awaitingDecision:
            return "Awaiting Decision"
        case .completed:
            return "Completed"
        case .stopped:
            return "Stopped"
        case .failedToStart:
            return "Retry Download"
        }
    }

    var liveActivityStatus: String {
        switch phase {
        case .starting:
            return "Preparing download queue"
        case .downloading:
            return "Downloading from camera"
        case .saving:
            return "Saving to Photos"
        case .awaitingDecision:
            return "Paused after an error"
        case .completed:
            return "Download complete"
        case .stopped:
            return "Download stopped"
        case .failedToStart:
            return "Could not start download"
        }
    }

    private var progressPrefix: String {
        "Processed \(processedCount) of \(totalCount). "
    }

    private func currentItemSuffix(_ verb: String) -> String {
        guard let currentAssetTitle, !currentAssetTitle.isEmpty else {
            return "\(verb) current photo"
        }
        return "\(verb) \(currentAssetTitle)"
    }
}

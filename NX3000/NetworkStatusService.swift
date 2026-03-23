import Foundation
import Network
import Combine

struct NetworkSnapshot: Sendable {
    let isResolved: Bool
    let isWiFiConnected: Bool
    let isExpensive: Bool
    let isConstrained: Bool
}

@MainActor
final class NetworkStatusService: ObservableObject {
    @Published private(set) var snapshot = NetworkSnapshot(
        isResolved: false,
        isWiFiConnected: false,
        isExpensive: false,
        isConstrained: false
    )

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NX3000.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = NetworkSnapshot(
                isResolved: true,
                isWiFiConnected: path.status == .satisfied && path.usesInterfaceType(.wifi),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )

            Task { @MainActor [weak self] in
                self?.snapshot = NetworkSnapshot(
                    isResolved: snapshot.isResolved,
                    isWiFiConnected: snapshot.isWiFiConnected,
                    isExpensive: snapshot.isExpensive,
                    isConstrained: snapshot.isConstrained
                )
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

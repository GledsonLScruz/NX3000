import Foundation
import Network

actor NX3000TCPTransport {
    func send(
        host: String,
        port: UInt16,
        requestData: Data,
        timeout: TimeInterval
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.sendWithoutTimeout(
                    host: host,
                    port: port,
                    requestData: requestData
                )
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw NX3000Error.timeout(timeout)
            }

            guard let firstResult = try await group.next() else {
                throw NX3000Error.transportFailed("No response task completed.")
            }

            group.cancelAll()
            return firstResult
        }
    }

    private nonisolated func sendWithoutTimeout(
        host: String,
        port: UInt16,
        requestData: Data
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: NX3000Error.transportFailed("Invalid TCP port \(port)."))
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let queue = DispatchQueue(label: "NX3000.TCPTransport.\(UUID().uuidString)")
            var responseData = Data()
            var didFinish = false
            var receiveNext: (() -> Void)?

            func finish(_ result: Result<Data, Error>) {
                guard !didFinish else { return }
                didFinish = true
                connection.cancel()
                continuation.resume(with: result)
            }

            receiveNext = {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        responseData.append(data)
                    }

                    if let error {
                        finish(.failure(NX3000Error.transportFailed(error.localizedDescription)))
                        return
                    }

                    if isComplete {
                        finish(.success(responseData))
                        return
                    }

                    receiveNext?()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(NX3000Error.transportFailed(error.localizedDescription)))
                            return
                        }
                        receiveNext?()
                    })
                case .waiting(let error):
                    finish(.failure(NX3000Error.transportFailed(error.localizedDescription)))
                case .failed(let error):
                    finish(.failure(NX3000Error.transportFailed(error.localizedDescription)))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}

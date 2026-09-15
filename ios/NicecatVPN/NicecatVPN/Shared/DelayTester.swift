import Foundation
import Network

enum DelayTester {
    static func test(nodes: [NodeProfile], timeout: TimeInterval = 2.5) async -> [String: Int?] {
        await withTaskGroup(of: (String, Int?).self) { group in
            for node in nodes {
                group.addTask {
                    let delay = await measure(host: node.server, port: node.port, timeout: timeout)
                    return (node.tag, delay)
                }
            }
            var results: [String: Int?] = [:]
            for await result in group {
                results[result.0] = result.1
            }
            return results
        }
    }

    private static func measure(host: String, port: Int, timeout: TimeInterval) async -> Int? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "nicecat.delay.\(UUID().uuidString)")
            let start = DispatchTime.now()
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
            let lock = NSLock()
            var finished = false

            func finish(_ value: Int?) {
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    return
                }
                finished = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(max(1, Int(elapsed / 1_000_000)))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
            connection.start(queue: queue)
        }
    }
}

#if canImport(Libbox)
import Foundation
import Libbox

func runBlocking<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        box.value = await block()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value
}

func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ThrowingResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do {
            box.result = .success(try await block())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T!
}

private final class ThrowingResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>!
}

extension LibboxStringIteratorProtocol {
    func toArray() -> [String] {
        var result: [String] = []
        while hasNext() {
            result.append(next())
        }
        return result
    }
}
#endif

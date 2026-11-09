import Foundation

/// Waits for an asynchronous service without hanging the caller when that
/// service never answers. Late responses are ignored.
enum TimedCallback {
    @MainActor
    static func run<Value>(
        timeout: TimeInterval,
        fallback: Value,
        start: (@escaping @Sendable (Value) -> Void) -> Void
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let result = ResultOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                result.resume(fallback)
            }
            start { result.resume($0) }
        }
    }

    private final class ResultOnce<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Never>?

        init(_ continuation: CheckedContinuation<Value, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: Value) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}

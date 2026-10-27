import Foundation

/// A native call already running cannot be interrupted safely. Serialize native
/// work and check cancellation when a queued call reaches the gate, so obsolete
/// requests do not accumulate into concurrent library executions.
private actor NativeWorkGate {
    func run<T: Sendable>(_ work: @Sendable () throws -> T) throws -> T {
        try Task.checkCancellation()
        return try work()
    }
}

private let nativeWorkGate = NativeWorkGate()

func runNativeWork<T: Sendable>(
    priority: TaskPriority = .userInitiated,
    _ work: @escaping @Sendable () throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached(priority: priority) {
        try await nativeWorkGate.run(work)
    }
    return try await withTaskCancellationHandler {
        let result = try await task.value
        try Task.checkCancellation()
        return result
    } onCancel: {
        task.cancel()
    }
}

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

/// Runs native work without the serialization gate. Only for calls that are
/// known to be independent of one another, such as the per-point classification
/// of a Phase Map. Cancellation is honoured before the call starts; a call
/// already running cannot be interrupted.
func runConcurrentNativeWork<T: Sendable>(
    priority: TaskPriority = .userInitiated,
    _ work: @escaping @Sendable () throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached(priority: priority) {
        try Task.checkCancellation()
        return try work()
    }
    return try await withTaskCancellationHandler {
        let result = try await task.value
        try Task.checkCancellation()
        return result
    } onCancel: {
        task.cancel()
    }
}

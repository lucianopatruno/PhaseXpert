import Foundation

/// Runs blocking native-engine work off the caller's executor.
///
/// Cancellation is checked before the work starts and again after it returns,
/// so a cancelled request never yields a result to the caller.
func runNativeWork<T: Sendable>(
    priority: TaskPriority = .userInitiated,
    _ work: @escaping @Sendable () throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let result = try await Task.detached(priority: priority, operation: work).value
    try Task.checkCancellation()
    return result
}

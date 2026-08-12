import Foundation

#if os(iOS) && canImport(PhaseXpertTeqpBridge)
import PhaseXpertTeqpBridge
#endif

public struct NativeTeqpEngine: TeqpEngine {
    public var isAvailable: Bool {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        true
        #else
        false
        #endif
    }

    public var libraryVersion: String {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        var buffer = [CChar](repeating: 0, count: 160)
        let status = px_teqp_copy_version(&buffer, buffer.count)
        guard status == 0 else { return "teqp linked" }
        return String(cString: buffer)
        #else
        return "Not linked"
        #endif
    }

    public init() {}

    public func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> TeqpEngineResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_pure_co2(
                pressurePa,
                temperatureK,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native calculation failed." : message
                )
            }
            return TeqpEngineResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                densityRootCount: Int(nativeResult.density_root_count),
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
        #else
        throw ProviderError.modelUnavailable(
            "The teqp native XCFramework has not been linked."
        )
        #endif
    }
}

#if os(iOS) && canImport(PhaseXpertTeqpBridge)
private func phaseIdentifier(for phase: PXTeqpPhase) -> String {
    switch phase {
    case PXTeqpPhaseSupercritical:
        "supercritical"
    default:
        "unknown"
    }
}
#endif

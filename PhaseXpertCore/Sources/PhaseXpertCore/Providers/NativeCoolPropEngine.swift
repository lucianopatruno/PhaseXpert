import Foundation

#if os(iOS) && canImport(PhaseXpertCoolPropBridge)
import PhaseXpertCoolPropBridge

/// Bridge-backed CoolProp engine for the validation-pending pure-CO2 spike.
public struct NativeCoolPropEngine: CoolPropEngine {
    public var isAvailable: Bool { true }

    public var libraryVersion: String {
        var buffer = [CChar](repeating: 0, count: 128)
        let status = px_coolprop_copy_version(&buffer, buffer.count)
        guard status == 0 else {
            return "CoolProp linked"
        }
        return String(cString: buffer)
    }

    public init() {}

    public func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        try Task.checkCancellation()

        var nativeResult = PXCoolPropResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_coolprop_calculate_pure_co2(
            pressurePa,
            temperatureK,
            &nativeResult,
            &errorBuffer,
            errorBuffer.count
        )

        try Task.checkCancellation()

        guard status == 0 else {
            let message = String(cString: errorBuffer)
            throw ProviderError.malformedResponse(
                message.isEmpty ? "CoolProp native calculation failed." : message
            )
        }

        return CoolPropEngineResult(
            densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
            dynamicViscosityPascalSeconds: nativeResult.dynamic_viscosity_pa_s,
            phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
        )
    }

    private func phaseIdentifier(for phase: PXCoolPropPhase) -> String {
        switch phase {
        case PXCoolPropPhaseGas:
            "gas"
        case PXCoolPropPhaseLiquid:
            "liquid"
        case PXCoolPropPhaseDense:
            "supercritical_liquid"
        case PXCoolPropPhaseSupercritical:
            "supercritical"
        case PXCoolPropPhaseTwoPhase:
            "twophase"
        case PXCoolPropPhaseSolid:
            "solid"
        default:
            "unknown"
        }
    }
}
#endif

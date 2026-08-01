import Foundation

#if os(iOS) && canImport(PhaseXpertCoolPropBridge)
import PhaseXpertCoolPropBridge

/// Bridge-backed CoolProp engine for the validation-pending pure-CO₂ provider.
public struct NativeCoolPropEngine: CoolPropEngine {
    public var isAvailable: Bool { true }

    public var libraryVersion: String {
        var buffer = [CChar](repeating: 0, count: 128)
        let status = px_coolprop_copy_version(&buffer, buffer.count)
        guard status == 0 else { return "CoolProp linked" }
        return String(cString: buffer)
    }

    public init() {}

    public func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXCoolPropResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_calculate_pure_co2(
                pressurePa,
                temperatureK,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp native calculation failed." : message
                )
            }
            return CoolPropEngineResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                dynamicViscosityPascalSeconds: nativeResult.dynamic_viscosity_pa_s,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase),
                expandedProperties: CoolPropPureFluidProperties(
                    enthalpyJoulesPerKilogram: nativeResult.enthalpy_j_kg,
                    entropyJoulesPerKilogramKelvin: nativeResult.entropy_j_kg_k,
                    internalEnergyJoulesPerKilogram: nativeResult.internal_energy_j_kg,
                    isobaricHeatCapacityJoulesPerKilogramKelvin:
                        nativeResult.isobaric_heat_capacity_j_kg_k,
                    isochoricHeatCapacityJoulesPerKilogramKelvin:
                        nativeResult.isochoric_heat_capacity_j_kg_k,
                    speedOfSoundMetresPerSecond: nativeResult.speed_of_sound_m_s,
                    thermalConductivityWattsPerMetreKelvin:
                        nativeResult.thermal_conductivity_w_m_k,
                    jouleThomsonKelvinPerPascal: nativeResult.joule_thomson_k_pa
                )
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func calculateCarbonDioxideNitrogen(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> CoolPropBinaryEngineResult {
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXCoolPropBinaryResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_calculate_co2_n2(
                pressurePa,
                temperatureK,
                carbonDioxideMoleFraction,
                nitrogenMoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp CO₂-N₂ calculation failed." : message
                )
            }
            return CoolPropBinaryEngineResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        try Task.checkCancellation()
        let limits = try await Task.detached(priority: .userInitiated) {
            var nativeLimits = PXCoolPropSaturationLimits()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_pure_co2_saturation_limits(
                &nativeLimits,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp saturation limits failed." : message
                )
            }
            return CoolPropSaturationLimits(
                triplePointTemperatureK: nativeLimits.triple_temperature_k,
                criticalPointTemperatureK: nativeLimits.critical_temperature_k,
                criticalPointPressurePa: nativeLimits.critical_pressure_pa
            )
        }.value
        try Task.checkCancellation()
        return limits
    }

    public func pureCarbonDioxideSaturationPressure(
        temperatureK: Double
    ) async throws -> Double {
        try Task.checkCancellation()
        let pressure = try await Task.detached(priority: .userInitiated) {
            var pressurePa = 0.0
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_pure_co2_saturation_pressure(
                temperatureK,
                &pressurePa,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp saturation calculation failed." : message
                )
            }
            return pressurePa
        }.value
        try Task.checkCancellation()
        return pressure
    }
}

private func phaseIdentifier(for phase: PXCoolPropPhase) -> String {
    switch phase {
    case PXCoolPropPhaseGas: "gas"
    case PXCoolPropPhaseLiquid: "liquid"
    case PXCoolPropPhaseDense: "supercritical_liquid"
    case PXCoolPropPhaseSupercritical: "supercritical"
    case PXCoolPropPhaseTwoPhase: "twophase"
    case PXCoolPropPhaseSolid: "solid"
    default: "unknown"
    }
}
#endif

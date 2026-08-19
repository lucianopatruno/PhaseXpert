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
                densityMolesPerCubicMetre: nativeResult.density_mol_m3,
                reducingDensityMolesPerCubicMetre: nativeResult.reducing_density_mol_m3,
                gibbsMolarJoulesPerMole: nativeResult.gibbs_molar_j_mol,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropBinaryEngineResult {
        try Task.checkCancellation()
        let fractions = composition.reduce(into: [ComponentID: Double]()) {
            $0[$1.component, default: 0] += $1.moleFraction
        }
        let carbonDioxide = fractions[.carbonDioxide] ?? 0
        let nitrogen = fractions[.nitrogen] ?? 0
        let oxygen = fractions[.oxygen] ?? 0
        let argon = fractions[.argon] ?? 0
        let methane = fractions[.methane] ?? 0
        let hydrogen = fractions[.hydrogen] ?? 0
        let carbonMonoxide = fractions[.carbonMonoxide] ?? 0
        let hydrogenSulfide = fractions[.hydrogenSulfide] ?? 0

        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXCoolPropBinaryResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_calculate_dry_co2_mixture(
                pressurePa,
                temperatureK,
                carbonDioxide,
                nitrogen,
                oxygen,
                argon,
                methane,
                hydrogen,
                carbonMonoxide,
                hydrogenSulfide,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp dry-mixture calculation failed." : message
                )
            }
            return CoolPropBinaryEngineResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                densityMolesPerCubicMetre: nativeResult.density_mol_m3,
                reducingDensityMolesPerCubicMetre: nativeResult.reducing_density_mol_m3,
                gibbsMolarJoulesPerMole: nativeResult.gibbs_molar_j_mol,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func identifyDryCarbonDioxideMixturePhase(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropPhaseEngineResult {
        try Task.checkCancellation()
        let fractions = composition.reduce(into: [ComponentID: Double]()) {
            $0[$1.component, default: 0] += $1.moleFraction
        }

        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXCoolPropPhaseResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_classify_dry_co2_mixture_phase_legacy_stability(
                pressurePa,
                temperatureK,
                fractions[.carbonDioxide] ?? 0,
                fractions[.nitrogen] ?? 0,
                fractions[.oxygen] ?? 0,
                fractions[.argon] ?? 0,
                fractions[.methane] ?? 0,
                fractions[.hydrogen] ?? 0,
                fractions[.carbonMonoxide] ?? 0,
                fractions[.hydrogenSulfide] ?? 0,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp dry-mixture legacy-stability phase classification failed." : message
                )
            }
            return CoolPropPhaseEngineResult(
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        imposedPhase: CoolPropSinglePhaseHint
    ) async throws -> CoolPropBinaryEngineResult {
        try Task.checkCancellation()
        let fractions = composition.reduce(into: [ComponentID: Double]()) {
            $0[$1.component, default: 0] += $1.moleFraction
        }
        let phaseHint: PXCoolPropPhaseHint = switch imposedPhase {
        case .gas:
            PXCoolPropPhaseHintGas
        case .liquid:
            PXCoolPropPhaseHintLiquid
        }

        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXCoolPropBinaryResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_calculate_dry_co2_mixture_with_phase_hint(
                pressurePa,
                temperatureK,
                fractions[.carbonDioxide] ?? 0,
                fractions[.nitrogen] ?? 0,
                fractions[.oxygen] ?? 0,
                fractions[.argon] ?? 0,
                fractions[.methane] ?? 0,
                fractions[.hydrogen] ?? 0,
                fractions[.carbonMonoxide] ?? 0,
                fractions[.hydrogenSulfide] ?? 0,
                phaseHint,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp phase-imposed dry-mixture calculation failed." : message
                )
            }
            return CoolPropBinaryEngineResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                densityMolesPerCubicMetre: nativeResult.density_mol_m3,
                reducingDensityMolesPerCubicMetre: nativeResult.reducing_density_mol_m3,
                gibbsMolarJoulesPerMole: nativeResult.gibbs_molar_j_mol,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase)
            )
        }.value
        try Task.checkCancellation()
        return result
    }

    public func dryCarbonDioxideMixtureSaturationPressures(
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureSaturationPressures {
        try Task.checkCancellation()
        let fractions = composition.reduce(into: [ComponentID: Double]()) {
            $0[$1.component, default: 0] += $1.moleFraction
        }

        let pressures = try await Task.detached(priority: .utility) {
            var nativePressures = PXCoolPropMixtureSaturationPressures()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_dry_co2_mixture_saturation_pressures(
                temperatureK,
                fractions[.carbonDioxide] ?? 0,
                fractions[.nitrogen] ?? 0,
                fractions[.oxygen] ?? 0,
                fractions[.argon] ?? 0,
                fractions[.methane] ?? 0,
                fractions[.hydrogen] ?? 0,
                fractions[.carbonMonoxide] ?? 0,
                fractions[.hydrogenSulfide] ?? 0,
                &nativePressures,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp dry-mixture saturation-pressure calculation failed." : message
                )
            }
            return CoolPropMixtureSaturationPressures(
                bubblePressurePa: nativePressures.bubble_pressure_pa,
                dewPressurePa: nativePressures.dew_pressure_pa
            )
        }.value
        try Task.checkCancellation()
        return pressures
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

    public func dryCarbonDioxideMixturePhaseEnvelope(
        composition: [MixtureComponent]
    ) async throws -> CoolPropMixtureEnvelopeResult {
        try Task.checkCancellation()
        let fractions = composition.reduce(into: [ComponentID: Double]()) {
            $0[$1.component, default: 0] += $1.moleFraction
        }
        let nativeResult = try await Task.detached(priority: .utility) {
            var points = [PXCoolPropEnvelopePoint](repeating: .init(), count: 512)
            var pointCount = 0
            var isComplete: Int32 = 0
            var isClosed: Int32 = 0
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_coolprop_dry_co2_mixture_phase_envelope(
                fractions[.carbonDioxide] ?? 0,
                fractions[.nitrogen] ?? 0,
                fractions[.oxygen] ?? 0,
                fractions[.argon] ?? 0,
                fractions[.methane] ?? 0,
                fractions[.hydrogen] ?? 0,
                fractions[.carbonMonoxide] ?? 0,
                fractions[.hydrogenSulfide] ?? 0,
                &points,
                points.count,
                &pointCount,
                &isComplete,
                &isClosed,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "CoolProp mixture phase-envelope calculation failed." : message
                )
            }
            let mappedPoints = points.prefix(pointCount).map { point in
                let branch: PhaseEnvelopePoint.Branch = switch point.branch {
                case PXCoolPropEnvelopeDew: .dew
                case PXCoolPropEnvelopeCritical: .critical
                default: .bubble
                }
                return PhaseEnvelopePoint(
                    temperatureK: point.temperature_k,
                    pressurePa: point.pressure_pa,
                    branch: branch
                )
            }
            return (
                points: mappedPoints,
                isComplete: isComplete != 0,
                isClosed: isClosed != 0
            )
        }.value
        try Task.checkCancellation()
        return CoolPropMixtureEnvelopeResult(
            points: nativeResult.points,
            solverMethod: "CoolProp AbstractState.build_phase_envelope(level: none), HEOS dry CO₂-rich mixture, start 80000 Pa, maximum 256 provider continuation steps",
            isComplete: nativeResult.isComplete,
            isClosed: nativeResult.isClosed
        )
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

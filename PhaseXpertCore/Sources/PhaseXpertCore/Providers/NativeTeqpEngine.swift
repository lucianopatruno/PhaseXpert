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
                isochoricHeatCapacityJoulesPerKilogramKelvin:
                    nativeResult.isochoric_heat_capacity_j_kg_k,
                isobaricHeatCapacityJoulesPerKilogramKelvin:
                    nativeResult.isobaric_heat_capacity_j_kg_k,
                heatCapacityRatio: nativeResult.heat_capacity_ratio,
                speedOfSoundMetresPerSecond: nativeResult.speed_of_sound_m_s,
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

    public func pureCarbonDioxideSaturation(
        temperatureK: Double
    ) async throws -> TeqpSaturationPoint {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpSaturationResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_saturation_pure_co2(
                temperatureK,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native saturation calculation failed." : message
                )
            }
            return TeqpSaturationPoint(
                temperatureK: temperatureK,
                pressurePa: nativeResult.pressure_pa,
                liquidDensityKilogramsPerCubicMetre: nativeResult.liquid_density_kg_m3,
                vaporDensityKilogramsPerCubicMetre: nativeResult.vapor_density_kg_m3
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

    public func calculateCarbonDioxideHydrogenGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        hydrogenMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpMixtureDensityResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_eoscg_co2_h2_gas_density(
                pressurePa,
                temperatureK,
                hydrogenMoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native CO₂+H₂ gas-density calculation failed." : message
                )
            }
            return TeqpMixtureDensityResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                molarDensityMolesPerCubicMetre: nativeResult.molar_density_mol_m3,
                densityRootCount: Int(nativeResult.density_root_count),
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase),
                formulationID: TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id
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

    public func calculateCarbonDioxideMethaneGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        methaneMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpMixtureDensityResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_eoscg_co2_ch4_gas_density(
                pressurePa,
                temperatureK,
                methaneMoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native CO₂+CH₄ gas-density calculation failed." : message
                )
            }
            return TeqpMixtureDensityResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                molarDensityMolesPerCubicMetre: nativeResult.molar_density_mol_m3,
                densityRootCount: Int(nativeResult.density_root_count),
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase),
                formulationID: TeqpFormulationCatalog.co2MethaneEOSCGGasDensity.id
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

    public func calculateBinaryVLE(
        formulation: TeqpBinaryFormulationID,
        temperatureK: Double,
        liquidComponent2MoleFraction: Double,
        initialGuess: TeqpBinaryVLEInitialGuess? = nil
    ) async throws -> TeqpBinaryVLEResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpGenericBinaryVLEResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let nativeFormulation = nativeFormulation(for: formulation)
            let status: Int32
            if let initialGuess {
                let nativeInitialGuess = PXTeqpBinaryVLEInitialGuess(
                    liquid_molar_density_mol_m3:
                        initialGuess.liquidMolarDensityMolesPerCubicMetre,
                    vapor_molar_density_mol_m3:
                        initialGuess.vaporMolarDensityMolesPerCubicMetre,
                    vapor_component2_mole_fraction:
                        initialGuess.vaporComponent2MoleFraction
                )
                status = px_teqp_calculate_binary_vle_tx_with_initial_guess(
                    nativeFormulation,
                    temperatureK,
                    liquidComponent2MoleFraction,
                    nativeInitialGuess,
                    &nativeResult,
                    &errorBuffer,
                    errorBuffer.count
                )
            } else {
                status = px_teqp_calculate_binary_vle_tx(
                    nativeFormulation,
                    temperatureK,
                    liquidComponent2MoleFraction,
                    &nativeResult,
                    &errorBuffer,
                    errorBuffer.count
                )
            }
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native binary VLE calculation failed." : message
                )
            }
            return TeqpBinaryVLEResult(
                converged: nativeResult.converged == 1,
                iterationCount: Int(nativeResult.iteration_count),
                returnCode: Int(nativeResult.return_code),
                pressurePa: nativeResult.pressure_pa,
                liquidMolarDensityMolesPerCubicMetre:
                    nativeResult.liquid_molar_density_mol_m3,
                vaporMolarDensityMolesPerCubicMetre:
                    nativeResult.vapor_molar_density_mol_m3,
                liquidComponent2MoleFraction:
                    nativeResult.liquid_component2_mole_fraction,
                vaporComponent2MoleFraction:
                    nativeResult.vapor_component2_mole_fraction,
                pressureResidualPa: nativeResult.pressure_residual_pa,
                component1ChemicalPotentialResidual:
                    nativeResult.component1_chemical_potential_residual,
                component2ChemicalPotentialResidual:
                    nativeResult.component2_chemical_potential_residual
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
private func nativeFormulation(
    for formulation: TeqpBinaryFormulationID
) -> PXTeqpBinaryFormulation {
    switch formulation {
    case .carbonDioxideNitrogen:
        PXTeqpBinaryFormulationCO2N2
    case .eoscgCarbonDioxideHydrogen:
        PXTeqpBinaryFormulationEOSCGCO2H2
    case .eoscgCarbonDioxideMethane:
        PXTeqpBinaryFormulationEOSCGCO2CH4
    }
}

private func phaseIdentifier(for phase: PXTeqpPhase) -> String {
    switch phase {
    case PXTeqpPhaseSupercritical:
        "supercritical"
    case PXTeqpPhaseGas:
        "gas"
    case PXTeqpPhaseLiquid:
        "liquid"
    case PXTeqpPhaseTwoPhase:
        "twoPhase"
    default:
        "unknown"
    }
}
#endif

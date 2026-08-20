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

    public func calculateBinaryThermodynamicState(
        formulation: TeqpBinaryFormulationID,
        pressurePa: Double,
        temperatureK: Double,
        component2MoleFraction: Double
    ) async throws -> TeqpMixtureThermodynamicResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXNativeTeqpMixtureThermodynamicResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_native_teqp_calculate_binary_thermodynamic_state(
                nativeFormulationRawValue(for: formulation),
                pressurePa,
                temperatureK,
                component2MoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty
                        ? "teqp native binary thermodynamic-state calculation failed."
                        : message
                )
            }
            return TeqpMixtureThermodynamicResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                molarDensityMolesPerCubicMetre: nativeResult.molar_density_mol_m3,
                pressurePa: nativeResult.pressure_pa,
                pressureDerivativeWithRespectToMolarDensityJoulesPerMole:
                    nativeResult.dp_drho_molar_j_mol,
                pressureDerivativeWithRespectToTemperaturePascalsPerKelvin:
                    nativeResult.dp_dt_pa_k,
                isochoricHeatCapacityJoulesPerKilogramKelvin:
                    nativeResult.isochoric_heat_capacity_j_kg_k,
                isobaricHeatCapacityJoulesPerKilogramKelvin:
                    nativeResult.isobaric_heat_capacity_j_kg_k,
                heatCapacityRatio: nativeResult.heat_capacity_ratio,
                speedOfSoundMetresPerSecond: nativeResult.speed_of_sound_m_s,
                speedOfSoundSquaredMetresSquaredPerSecondSquared:
                    nativeResult.speed_of_sound_squared_m2_s2,
                minimumStabilityEigenvalue:
                    nativeResult.minimum_stability_eigenvalue,
                densityRootCount: Int(nativeResult.density_root_count),
                converged: nativeResult.converged == 1,
                phaseIdentifier: phaseIdentifier(forRawPhase: nativeResult.phase),
                formulationID: formulation.diagnosticFormulationID
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

    public func calculateBinaryCriticalPoint(
        formulation: TeqpBinaryFormulationID,
        component2MoleFraction: Double
    ) async throws -> TeqpBinaryCriticalResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXNativeTeqpBinaryCriticalResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_native_teqp_calculate_binary_critical_point(
                nativeFormulationRawValue(for: formulation),
                component2MoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty
                        ? "teqp native binary critical-point calculation failed."
                        : message
                )
            }
            return TeqpBinaryCriticalResult(
                converged: nativeResult.converged == 1,
                iterationCount: Int(nativeResult.iteration_count),
                temperatureK: nativeResult.temperature_k,
                pressurePa: nativeResult.pressure_pa,
                molarDensityMolesPerCubicMetre:
                    nativeResult.molar_density_mol_m3,
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                component2MoleFraction:
                    nativeResult.component2_mole_fraction,
                minimumStabilityEigenvalue:
                    nativeResult.minimum_stability_eigenvalue,
                thirdOrderResidual: nativeResult.third_order_residual,
                formulationID: formulation.diagnosticFormulationID
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

    public func calculateNComponentDensity(
        pressurePa: Double,
        temperatureK: Double,
        composition: CanonicalComposition
    ) async throws -> TeqpNComponentDensityResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let canonicalComponents = composition.components
        let ids = try canonicalComponents.map { entry in
            try nativeComponentID(for: entry.component)
        }
        let fractions = canonicalComponents.map(\.moleFraction)
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpNComponentDensityResult()
            var errorBuffer = [CChar](repeating: 0, count: 768)
            let status = ids.withUnsafeBufferPointer { idBuffer in
                fractions.withUnsafeBufferPointer { fractionBuffer in
                    px_teqp_calculate_ncomponent_density(
                        idBuffer.baseAddress,
                        fractionBuffer.baseAddress,
                        idBuffer.count,
                        pressurePa,
                        temperatureK,
                        &nativeResult,
                        &errorBuffer,
                        errorBuffer.count
                    )
                }
            }
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty
                        ? "teqp native N-component density calculation failed."
                        : message
                )
            }
            return TeqpNComponentDensityResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                molarDensityMolesPerCubicMetre: nativeResult.molar_density_mol_m3,
                densityRootCount: Int(nativeResult.density_root_count),
                converged: nativeResult.converged == 1,
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase),
                formulationID: TeqpNComponentDiagnostic.formulationID,
                composition: canonicalComponents
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

    public func calculateNComponentVLE(
        temperatureK: Double,
        specifiedComposition: CanonicalComposition,
        specification: TeqpPhaseEquilibriumSpecification
    ) async throws -> TeqpNComponentVLEResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let components = specifiedComposition.components
        let ids = try components.map { try nativeComponentID(for: $0.component) }
        let fractions = components.map(\.moleFraction)
        let nativeSpecification = specification == .bubble
            ? PXTeqpEquilibriumBubble : PXTeqpEquilibriumDew
        let result = try await Task.detached(priority: .userInitiated) {
            var mutableIDs = ids
            var mutableFractions = fractions
            var liquid = [Double](repeating: 0, count: components.count)
            var vapor = [Double](repeating: 0, count: components.count)
            var nativeResult = PXTeqpNComponentVLEResult()
            var errorBuffer = [CChar](repeating: 0, count: 768)
            let status = px_teqp_calculate_ncomponent_vle(
                &mutableIDs, &mutableFractions, mutableIDs.count,
                temperatureK, nativeSpecification,
                &liquid, liquid.count, &vapor, vapor.count,
                &nativeResult, &errorBuffer, errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp N-component VLE solve failed." : message
                )
            }
            let liquidComposition = zip(components, liquid).map {
                MixtureComponent(component: $0.0.component, moleFraction: $0.1)
            }
            let vaporComposition = zip(components, vapor).map {
                MixtureComponent(component: $0.0.component, moleFraction: $0.1)
            }
            return TeqpNComponentVLEResult(
                converged: nativeResult.converged == 1,
                iterationCount: Int(nativeResult.iteration_count),
                status: TeqpPhaseEquilibriumStatus(rawValue: Int(nativeResult.status.rawValue)) ?? .unknown,
                pressurePa: nativeResult.pressure_pa,
                liquidMolarDensityMolesPerCubicMetre: nativeResult.liquid_molar_density_mol_m3,
                vaporMolarDensityMolesPerCubicMetre: nativeResult.vapor_molar_density_mol_m3,
                liquidComposition: liquidComposition,
                vaporComposition: vaporComposition,
                maximumLogFugacityResidual: nativeResult.maximum_log_fugacity_residual,
                relativePressureResidual: nativeResult.relative_pressure_residual,
                liquidMinimumStabilityEigenvalue: nativeResult.liquid_minimum_stability_eigenvalue,
                vaporMinimumStabilityEigenvalue: nativeResult.vapor_minimum_stability_eigenvalue
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

    public func calculateCarbonDioxideOxygenGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        oxygenMoleFraction: Double
    ) async throws -> TeqpMixtureDensityResult {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            var nativeResult = PXTeqpMixtureDensityResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_eoscg_co2_o2_gas_density(
                pressurePa,
                temperatureK,
                oxygenMoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
            guard status == 0 else {
                let message = String(cString: errorBuffer)
                throw ProviderError.malformedResponse(
                    message.isEmpty ? "teqp native CO₂+O₂ gas-density calculation failed." : message
                )
            }
            return TeqpMixtureDensityResult(
                densityKilogramsPerCubicMetre: nativeResult.density_kg_m3,
                molarDensityMolesPerCubicMetre: nativeResult.molar_density_mol_m3,
                densityRootCount: Int(nativeResult.density_root_count),
                phaseIdentifier: phaseIdentifier(for: nativeResult.phase),
                formulationID: TeqpFormulationCatalog.co2OxygenEOSCGGasDensity.id
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
private struct PXNativeTeqpMixtureThermodynamicResult {
    var density_kg_m3: Double = 0
    var molar_density_mol_m3: Double = 0
    var pressure_pa: Double = 0
    var dp_drho_molar_j_mol: Double = 0
    var dp_dt_pa_k: Double = 0
    var isochoric_heat_capacity_j_kg_k: Double = 0
    var isobaric_heat_capacity_j_kg_k: Double = 0
    var heat_capacity_ratio: Double = 0
    var speed_of_sound_m_s: Double = 0
    var speed_of_sound_squared_m2_s2: Double = 0
    var minimum_stability_eigenvalue: Double = 0
    var density_root_count: Int32 = 0
    var converged: Int32 = 0
    var phase: Int32 = 0
}

private struct PXNativeTeqpBinaryCriticalResult {
    var converged: Int32 = 0
    var iteration_count: Int32 = 0
    var temperature_k: Double = 0
    var pressure_pa: Double = 0
    var molar_density_mol_m3: Double = 0
    var density_kg_m3: Double = 0
    var component2_mole_fraction: Double = 0
    var minimum_stability_eigenvalue: Double = 0
    var third_order_residual: Double = 0
}

@_silgen_name("px_teqp_calculate_binary_thermodynamic_state")
private func px_native_teqp_calculate_binary_thermodynamic_state(
    _ formulation: Int32,
    _ pressurePa: Double,
    _ temperatureK: Double,
    _ component2MoleFraction: Double,
    _ result: UnsafeMutablePointer<PXNativeTeqpMixtureThermodynamicResult>,
    _ errorBuffer: UnsafeMutablePointer<CChar>,
    _ errorBufferSize: Int
) -> Int32

@_silgen_name("px_teqp_calculate_binary_critical_point")
private func px_native_teqp_calculate_binary_critical_point(
    _ formulation: Int32,
    _ component2MoleFraction: Double,
    _ result: UnsafeMutablePointer<PXNativeTeqpBinaryCriticalResult>,
    _ errorBuffer: UnsafeMutablePointer<CChar>,
    _ errorBufferSize: Int
) -> Int32

private func nativeFormulationRawValue(
    for formulation: TeqpBinaryFormulationID
) -> Int32 {
    switch formulation {
    case .carbonDioxideNitrogen:
        1
    case .eoscgCarbonDioxideHydrogen:
        2
    case .eoscgCarbonDioxideMethane:
        3
    }
}

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

private func phaseIdentifier(forRawPhase phase: Int32) -> String {
    switch phase {
    case 1:
        "supercritical"
    case 2:
        "gas"
    case 3:
        "liquid"
    case 4:
        "twoPhase"
    default:
        "unknown"
    }
}

private func nativeComponentID(for component: ComponentID) throws -> Int32 {
    switch component {
    case .carbonDioxide:
        1
    case .nitrogen:
        2
    case .methane:
        3
    case .hydrogen:
        4
    case .oxygen:
        5
    case .argon:
        6
    case .carbonMonoxide:
        7
    case .hydrogenSulfide:
        8
    case .water:
        9
    case .helium, .ethane, .propane:
        throw ProviderError.invalidRequest(
            "\(component.symbol) is not part of the audited teqp EOS-CG-2021 N-component subset."
        )
    }
}
#endif

private extension TeqpBinaryFormulationID {
    var diagnosticFormulationID: String {
        switch self {
        case .carbonDioxideNitrogen:
            TeqpFormulationCatalog.co2NitrogenGernertGergDiagnostic.id
        case .eoscgCarbonDioxideHydrogen:
            TeqpFormulationCatalog.co2HydrogenEOSCGDiagnostic.id
        case .eoscgCarbonDioxideMethane:
            TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.id
        }
    }
}

#if os(iOS) && canImport(PhaseXpertThermoPackBridge)
import Foundation
import PhaseXpertThermoPackBridge

public actor NativeThermoPackEngine: ThermoPackEngine {
    public nonisolated let isAvailable = true
    public nonisolated let libraryVersion: String
    public nonisolated let bridgeVersion: String
    public nonisolated let configurationIdentifier: String

    public init() {
        libraryVersion = String(cString: px_thermopack_library_version())
        bridgeVersion = String(cString: px_thermopack_bridge_version())
        configurationIdentifier = String(cString: px_thermopack_configuration())
    }

    public func calculate(
        pressurePa: Double,
        temperatureK: Double,
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double
    ) async throws -> ThermoPackStateResult {
        try Task.checkCancellation()
        var native = PXThermoPackState()
        var error = [CChar](repeating: 0, count: Int(PX_THERMOPACK_ERROR_CAPACITY))
        let status = error.withUnsafeMutableBufferPointer { buffer in
            px_thermopack_state(
                pressurePa,
                temperatureK,
                carbonDioxideMoleFraction,
                nitrogenMoleFraction,
                &native,
                buffer.baseAddress,
                buffer.count
            )
        }
        try Task.checkCancellation()
        guard status == 0 else {
            throw ProviderError.malformedResponse(errorMessage(error, status: status))
        }

        let phase: ThermoPackStateResult.Phase
        switch native.phase {
        case 1: phase = .liquid
        case 2: phase = .vapor
        case 3: phase = .twoPhase
        default: phase = .unknown
        }
        if native.is_two_phase != 0 {
            guard native.vapor_fraction.isFinite,
                  (0...1).contains(native.vapor_fraction)
            else {
                throw ProviderError.malformedResponse(
                    "ThermoPack returned an invalid two-phase vapor fraction."
                )
            }
            return ThermoPackStateResult(
                phase: .twoPhase,
                vaporFraction: native.vapor_fraction
            )
        }

        return ThermoPackStateResult(
            phase: phase,
            densityKilogramsPerCubicMetre: native.density_kg_m3,
            molarMassKilogramsPerMole: native.molar_mass_kg_mol,
            specificVolumeCubicMetresPerKilogram: native.specific_volume_m3_kg,
            compressibilityFactor: native.compressibility_factor,
            enthalpyJoulesPerKilogram: native.enthalpy_j_kg,
            entropyJoulesPerKilogramKelvin: native.entropy_j_kg_k,
            isobaricHeatCapacityJoulesPerKilogramKelvin: native.cp_j_kg_k
        )
    }

    public func phaseEnvelope(
        carbonDioxideMoleFraction: Double,
        nitrogenMoleFraction: Double,
        bounds: ScientificDomain,
        maximumPointsPerBranch: Int,
        maximumElapsedMilliseconds: Double
    ) async throws -> ThermoPackEnvelopeResult {
        try Task.checkCancellation()
        var native = PXThermoPackEnvelope()
        var error = [CChar](repeating: 0, count: Int(PX_THERMOPACK_ERROR_CAPACITY))
        let status = error.withUnsafeMutableBufferPointer { buffer in
            px_thermopack_envelope(
                carbonDioxideMoleFraction,
                nitrogenMoleFraction,
                bounds.minimumTemperatureK,
                bounds.maximumTemperatureK,
                bounds.minimumPressurePa,
                bounds.maximumPressurePa,
                Int32(maximumPointsPerBranch),
                maximumElapsedMilliseconds,
                &native,
                buffer.baseAddress,
                buffer.count
            )
        }
        try Task.checkCancellation()
        guard status == 0 else {
            throw ProviderError.malformedResponse(errorMessage(error, status: status))
        }
        guard native.point_count >= 0,
              native.point_count <= PX_THERMOPACK_MAX_POINTS
        else {
            throw ProviderError.malformedResponse(
                "ThermoPack returned an invalid envelope point count."
            )
        }

        var points: [PhaseEnvelopePoint] = []
        points.reserveCapacity(Int(native.point_count))
        for index in 0..<native.point_count {
            try Task.checkCancellation()
            var point = PXThermoPackEnvelopePoint()
            guard px_thermopack_envelope_point(&native, index, &point) == 0 else {
                throw ProviderError.malformedResponse(
                    "ThermoPack envelope point access failed at index \(index)."
                )
            }
            let branch: PhaseEnvelopePoint.Branch
            switch point.branch {
            case 0: branch = .bubble
            case 1: branch = .dew
            default:
                throw ProviderError.malformedResponse(
                    "ThermoPack returned an unknown envelope branch."
                )
            }
            points.append(
                PhaseEnvelopePoint(
                    temperatureK: point.temperature_k,
                    pressurePa: point.pressure_pa,
                    branch: branch
                )
            )
        }
        return ThermoPackEnvelopeResult(
            points: points,
            attemptedCalls: Int(native.attempted_calls),
            failedCalls: Int(native.failed_calls),
            complete: native.complete != 0,
            timedOut: native.timed_out != 0,
            durationMilliseconds: native.elapsed_ms
        )
    }

    private func errorMessage(_ buffer: [CChar], status: Int32) -> String {
        let message = buffer.withUnsafeBufferPointer {
            guard let base = $0.baseAddress, base.pointee != 0 else { return "" }
            return String(cString: base)
        }
        return message.isEmpty
            ? "ThermoPack native bridge failed with status \(status)."
            : message
    }
}
#endif

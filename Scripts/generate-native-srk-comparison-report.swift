import Foundation
#if canImport(PhaseXpertCore)
import PhaseXpertCore
#endif

struct ReferenceDataset: Decodable {
    let phaseEnvelopeCases: [ReferenceCase]

    enum CodingKeys: String, CodingKey {
        case phaseEnvelopeCases = "phase_envelope_cases"
    }
}

struct ReferenceCase: Decodable {
    let id: String
    let points: [ReferencePoint]
    let request: ReferenceRequest
}

struct ReferenceRequest: Decodable {
    let composition: [ReferenceComposition]
}

struct ReferenceComposition: Decodable {
    let component: ComponentID
    let moleFraction: Double

    enum CodingKeys: String, CodingKey {
        case component
        case moleFraction = "mole_fraction"
    }
}

struct ReferencePoint: Decodable {
    let branch: String
    let temperatureK: Double
    let pressurePa: Double

    enum CodingKeys: String, CodingKey {
        case branch
        case temperatureK = "temperature_k"
        case pressurePa = "pressure_pa"
    }
}

struct ComparisonOutput: Encodable {
    let schemaVersion: String
    let referenceDataset: String
    let referenceModel: String
    let localModel: String
    let comparisonMethod: String
    let acceptanceTolerances: AcceptanceTolerances
    let acceptanceGatePassed: Bool
    let cases: [CaseMetric]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case referenceDataset = "reference_dataset"
        case referenceModel = "reference_model"
        case localModel = "local_model"
        case comparisonMethod = "comparison_method"
        case acceptanceTolerances = "acceptance_tolerances"
        case acceptanceGatePassed = "acceptance_gate_passed"
        case cases
    }
}

struct AcceptanceTolerances: Encodable {
    let meanRelativePressureError: Double
    let percentile95RelativePressureError: Double
    let maximumRelativePressureError: Double
    let minimumBranchCoverage: Double

    enum CodingKeys: String, CodingKey {
        case meanRelativePressureError = "mean_relative_pressure_error"
        case percentile95RelativePressureError = "percentile95_relative_pressure_error"
        case maximumRelativePressureError = "maximum_relative_pressure_error"
        case minimumBranchCoverage = "minimum_branch_coverage"
    }
}

struct CaseMetric: Encodable {
    let caseID: String
    let totalAttempted: Int
    let totalConverged: Int
    let gapCount: Int
    let bubble: Metric
    let dew: Metric
    let coldBranchExperiment: ColdBranchExperimentMetric?

    enum CodingKeys: String, CodingKey {
        case caseID = "case_id"
        case totalAttempted = "total_attempted"
        case totalConverged = "total_converged"
        case gapCount = "gap_count"
        case bubble
        case dew
        case coldBranchExperiment = "cold_branch_experiment"
    }
}

struct Metric: Encodable {
    let referenceTemperatureRangeK: [Double]
    let localTemperatureRangeK: [Double]
    let referencePointCount: Int
    let attemptedLocalPointCount: Int
    let convergedLocalPointCount: Int
    let convergenceCoverage: Double
    let meanAbsolutePressureErrorPa: Double?
    let medianAbsolutePressureErrorPa: Double?
    let percentile95AbsolutePressureErrorPa: Double?
    let maximumAbsolutePressureErrorPa: Double?
    let meanRelativePressureError: Double?
    let maximumRelativePressureError: Double?

    enum CodingKeys: String, CodingKey {
        case referenceTemperatureRangeK = "reference_temperature_range_k"
        case localTemperatureRangeK = "local_temperature_range_k"
        case referencePointCount = "reference_point_count"
        case attemptedLocalPointCount = "attempted_local_point_count"
        case convergedLocalPointCount = "converged_local_point_count"
        case convergenceCoverage = "convergence_coverage"
        case meanAbsolutePressureErrorPa = "mean_absolute_pressure_error_pa"
        case medianAbsolutePressureErrorPa = "median_absolute_pressure_error_pa"
        case percentile95AbsolutePressureErrorPa = "percentile95_absolute_pressure_error_pa"
        case maximumAbsolutePressureErrorPa = "maximum_absolute_pressure_error_pa"
        case meanRelativePressureError = "mean_relative_pressure_error"
        case maximumRelativePressureError = "maximum_relative_pressure_error"
    }
}

struct ColdBranchExperimentMetric: Encodable {
    let startingTemperatureK: Double
    let startingPressurePa: Double
    let productionAttemptReason: String
    let pressureParameterizedAttemptReason: String
    let multiStartTPDMinimumCount: Int
    let negativeTPDMinimumCount: Int
    let detachedMinimumCount: Int
    let flashAttemptCount: Int
    let convergedFlashCount: Int
    let continuousFlashCount: Int
    let lowestContinuousFlashTemperatureK: Double?
    let flashFailureReason: String
    let betaLimitDiagnostic: BetaLimitDiagnosticMetric
    let bestContinuousTPD: TPDMinimumMetric?
    let rootClassification: String
    let rootSeparation: Double
    let densitySeparationMolesPerCubicMeter: Double
    let phaseCompositionDistance: Double
    let failureClassification: String

    enum CodingKeys: String, CodingKey {
        case startingTemperatureK = "starting_temperature_k"
        case startingPressurePa = "starting_pressure_pa"
        case productionAttemptReason = "production_attempt_reason"
        case pressureParameterizedAttemptReason = "pressure_parameterized_attempt_reason"
        case multiStartTPDMinimumCount = "multi_start_tpd_minimum_count"
        case negativeTPDMinimumCount = "negative_tpd_minimum_count"
        case detachedMinimumCount = "detached_minimum_count"
        case flashAttemptCount = "flash_attempt_count"
        case convergedFlashCount = "converged_flash_count"
        case continuousFlashCount = "continuous_flash_count"
        case lowestContinuousFlashTemperatureK = "lowest_continuous_flash_temperature_k"
        case flashFailureReason = "flash_failure_reason"
        case betaLimitDiagnostic = "beta_limit_diagnostic"
        case bestContinuousTPD = "best_continuous_tpd"
        case rootClassification = "root_classification"
        case rootSeparation = "root_separation"
        case densitySeparationMolesPerCubicMeter = "density_separation_moles_per_cubic_meter"
        case phaseCompositionDistance = "phase_composition_distance"
        case failureClassification = "failure_classification"
    }
}

struct BetaLimitDiagnosticMetric: Encodable {
    let startingTemperatureK: Double?
    let startingPressurePa: Double?
    let startingVaporFraction: Double?
    let betaSchedule: [Double]
    let attemptedStateCount: Int
    let acceptedStateCount: Int
    let lowestAcceptedBeta: Double?
    let lowestAcceptedTemperatureK: Double?
    let verifiedBubbleLimit: Bool
    let bubbleResidualNorm: Double?
    let sumZKMinusOne: Double?
    let terminationReason: String

    enum CodingKeys: String, CodingKey {
        case startingTemperatureK = "starting_temperature_k"
        case startingPressurePa = "starting_pressure_pa"
        case startingVaporFraction = "starting_vapor_fraction"
        case betaSchedule = "beta_schedule"
        case attemptedStateCount = "attempted_state_count"
        case acceptedStateCount = "accepted_state_count"
        case lowestAcceptedBeta = "lowest_accepted_beta"
        case lowestAcceptedTemperatureK = "lowest_accepted_temperature_k"
        case verifiedBubbleLimit = "verified_bubble_limit"
        case bubbleResidualNorm = "bubble_residual_norm"
        case sumZKMinusOne = "sum_zk_minus_one"
        case terminationReason = "termination_reason"
    }
}

struct TPDMinimumMetric: Encodable {
    let minimumTangentPlaneDistance: Double
    let residualNorm: Double
    let finalTrialComposition: [Double]
    let terminationReason: String
    let isTrivialFeedStationaryPoint: Bool
    let isBoundaryPinned: Bool

    enum CodingKeys: String, CodingKey {
        case minimumTangentPlaneDistance = "minimum_tangent_plane_distance"
        case residualNorm = "residual_norm"
        case finalTrialComposition = "final_trial_composition"
        case terminationReason = "termination_reason"
        case isTrivialFeedStationaryPoint = "is_trivial_feed_stationary_point"
        case isBoundaryPinned = "is_boundary_pinned"
    }
}

@main
enum NativeSRKComparisonReport {
    static func main() throws {
        let datasetPath = "Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json"
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appendingPathComponent(datasetPath))
        let reference = try JSONDecoder().decode(ReferenceDataset.self, from: data)
        let tracer = NativeSRKPhaseEnvelopeTracer()
        let temperatureRange = reference.phaseEnvelopeCases
            .flatMap { $0.points.map(\.temperatureK) }
        let minimumTemperature = max(1, (temperatureRange.min() ?? 186.0).rounded(.down))
        let maximumTemperature = (temperatureRange.max() ?? 305.0).rounded(.up)
        let options = NativeSRKEnvelopeOptions(
            minimumTemperatureK: minimumTemperature,
            maximumTemperatureK: maximumTemperature,
            initialTemperatureStepK: 5.0,
            minimumTemperatureStepK: 0.5,
            maximumTemperatureStepK: 8.0,
            maximumIterationsPerSolve: 80,
            maximumConsecutiveFailures: 6
        )
        let tolerances = AcceptanceTolerances(
            meanRelativePressureError: 0.10,
            percentile95RelativePressureError: 0.20,
            maximumRelativePressureError: 0.35,
            minimumBranchCoverage: 0.80
        )
        let cases = try reference.phaseEnvelopeCases.map { referenceCase -> CaseMetric in
            let local = try tracer.phaseEnvelope(
                composition: referenceCase.request.composition.map {
                    NativeSRKMixtureFraction(component: $0.component, moleFraction: $0.moleFraction)
                },
                options: options
            )
            return CaseMetric(
                caseID: referenceCase.id,
                totalAttempted: local.attemptedPointCount,
                totalConverged: local.convergedPointCount,
                gapCount: local.gaps.count,
                bubble: metric(branch: "bubble", referenceCase: referenceCase, local: local),
                dew: metric(branch: "dew", referenceCase: referenceCase, local: local),
                coldBranchExperiment: coldBranchExperiment(
                    referenceCase: referenceCase,
                    local: local,
                    tracer: tracer,
                    options: options
                )
            )
        }
        let gatePassed = cases.allSatisfy { caseMetric in
            metricPasses(caseMetric.bubble, tolerances: tolerances)
                && metricPasses(caseMetric.dew, tolerances: tolerances)
        }
        let output = ComparisonOutput(
            schemaVersion: "phasexpert-native-srk-comparison.v1",
            referenceDataset: datasetPath,
            referenceModel: "NeqSim 3.16.0 SystemSrkEos classic",
            localModel: "phasexpert-native-srk-prototype",
            comparisonMethod: "Linear interpolation in pressure by temperature inside continuous same-branch local intervals; no interpolation across recorded gaps and no extrapolation.",
            acceptanceTolerances: tolerances,
            acceptanceGatePassed: gatePassed,
            cases: cases
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(output), encoding: .utf8)!)
    }

    private static func metric(branch: String, referenceCase: ReferenceCase, local: NativeSRKEnvelopeResult) -> Metric {
        let referencePoints = referenceCase.points.filter { $0.branch == branch }.sorted { $0.temperatureK < $1.temperatureK }
        let localPoints = local.points.filter { $0.branch.rawValue == branch }.sorted { $0.temperatureK < $1.temperatureK }
        let localGaps = local.gaps.filter { $0.branch.rawValue == branch }
        let errors = referencePoints.compactMap { point -> (absolute: Double, relative: Double)? in
            guard let localPressure = interpolatedPressure(
                at: point.temperatureK,
                points: localPoints,
                gaps: localGaps
            ) else {
                return nil
            }
            let absolute = abs(localPressure - point.pressurePa)
            return (absolute, absolute / point.pressurePa)
        }
        let absoluteErrors = errors.map(\.absolute)
        let relativeErrors = errors.map(\.relative)
        return Metric(
            referenceTemperatureRangeK: range(referencePoints.map(\.temperatureK)),
            localTemperatureRangeK: range(localPoints.map(\.temperatureK)),
            referencePointCount: referencePoints.count,
            attemptedLocalPointCount: localPoints.count + localGaps.count,
            convergedLocalPointCount: localPoints.count,
            convergenceCoverage: referencePoints.isEmpty ? 0 : Double(errors.count) / Double(referencePoints.count),
            meanAbsolutePressureErrorPa: mean(absoluteErrors),
            medianAbsolutePressureErrorPa: percentile(absoluteErrors, 0.50),
            percentile95AbsolutePressureErrorPa: percentile(absoluteErrors, 0.95),
            maximumAbsolutePressureErrorPa: absoluteErrors.max(),
            meanRelativePressureError: mean(relativeErrors),
            maximumRelativePressureError: relativeErrors.max()
        )
    }

    private static func metricPasses(_ metric: Metric, tolerances: AcceptanceTolerances) -> Bool {
        guard let meanRelative = metric.meanRelativePressureError,
              let maximumRelative = metric.maximumRelativePressureError
        else {
            return false
        }
        return metric.convergenceCoverage >= tolerances.minimumBranchCoverage
            && meanRelative <= tolerances.meanRelativePressureError
            && maximumRelative <= tolerances.maximumRelativePressureError
    }

    private static func coldBranchExperiment(
        referenceCase: ReferenceCase,
        local: NativeSRKEnvelopeResult,
        tracer: NativeSRKPhaseEnvelopeTracer,
        options: NativeSRKEnvelopeOptions
    ) -> ColdBranchExperimentMetric? {
        guard referenceCase.id == "co2-90-n2-10",
              let startingPoint = local.points
                .filter({ $0.branch == .bubble })
                .min(by: { $0.temperatureK < $1.temperatureK }),
              let vaporCO2 = startingPoint.vaporMoleFractions[.carbonDioxide]
        else {
            return nil
        }
        let composition = referenceCase.request.composition.map {
            NativeSRKMixtureFraction(component: $0.component, moleFraction: $0.moleFraction)
        }
        guard let experiment = try? tracer.coldBubbleInitializationExperiment(
            startingTemperatureK: startingPoint.temperatureK,
            startingPressurePa: startingPoint.pressurePa,
            startingVaporCarbonDioxideMoleFraction: vaporCO2,
            feedComposition: composition,
            options: options
        ) else {
            return nil
        }
        return ColdBranchExperimentMetric(
            startingTemperatureK: experiment.startingTemperatureK,
            startingPressurePa: experiment.startingPressurePa,
            productionAttemptReason: experiment.productionAttemptReason,
            pressureParameterizedAttemptReason: experiment.pressureParameterizedAttemptReason,
            multiStartTPDMinimumCount: experiment.multiStartTPDMinimumCount,
            negativeTPDMinimumCount: experiment.negativeTPDMinimumCount,
            detachedMinimumCount: experiment.detachedMinimumCount,
            flashAttemptCount: experiment.flashAttemptCount,
            convergedFlashCount: experiment.convergedFlashCount,
            continuousFlashCount: experiment.continuousFlashCount,
            lowestContinuousFlashTemperatureK: experiment.lowestContinuousFlashTemperatureK,
            flashFailureReason: experiment.flashFailureReason,
            betaLimitDiagnostic: BetaLimitDiagnosticMetric(
                startingTemperatureK: experiment.betaLimitDiagnostic.startingTemperatureK,
                startingPressurePa: experiment.betaLimitDiagnostic.startingPressurePa,
                startingVaporFraction: experiment.betaLimitDiagnostic.startingVaporFraction,
                betaSchedule: experiment.betaLimitDiagnostic.betaSchedule,
                attemptedStateCount: experiment.betaLimitDiagnostic.attemptedStateCount,
                acceptedStateCount: experiment.betaLimitDiagnostic.acceptedStateCount,
                lowestAcceptedBeta: experiment.betaLimitDiagnostic.lowestAcceptedBeta,
                lowestAcceptedTemperatureK: experiment.betaLimitDiagnostic.lowestAcceptedTemperatureK,
                verifiedBubbleLimit: experiment.betaLimitDiagnostic.verifiedBubbleLimit,
                bubbleResidualNorm: experiment.betaLimitDiagnostic.bubbleResidualNorm,
                sumZKMinusOne: experiment.betaLimitDiagnostic.sumZKMinusOne,
                terminationReason: experiment.betaLimitDiagnostic.terminationReason
            ),
            bestContinuousTPD: experiment.bestContinuousMinimum.map {
                TPDMinimumMetric(
                    minimumTangentPlaneDistance: $0.minimumTangentPlaneDistance,
                    residualNorm: $0.residualNorm,
                    finalTrialComposition: $0.finalTrialComposition,
                    terminationReason: $0.terminationReason,
                    isTrivialFeedStationaryPoint: $0.isTrivialFeedStationaryPoint,
                    isBoundaryPinned: $0.isBoundaryPinned
                )
            },
            rootClassification: experiment.rootDiagnostic.classification,
            rootSeparation: experiment.rootDiagnostic.rootSeparation,
            densitySeparationMolesPerCubicMeter: experiment.rootDiagnostic.densitySeparationMolesPerCubicMeter,
            phaseCompositionDistance: experiment.rootDiagnostic.phaseCompositionDistance,
            failureClassification: experiment.failureClassification
        )
    }

    private static func interpolatedPressure(
        at temperatureK: Double,
        points: [NativeSRKEnvelopePoint],
        gaps: [NativeSRKEnvelopeGap]
    ) -> Double? {
        guard let first = points.first, let last = points.last,
              temperatureK >= first.temperatureK,
              temperatureK <= last.temperatureK
        else {
            return nil
        }
        if let exact = points.first(where: { abs($0.temperatureK - temperatureK) <= 1e-9 }) {
            return exact.pressurePa
        }
        guard let lower = points.last(where: { $0.temperatureK < temperatureK }),
              let upper = points.first(where: { $0.temperatureK > temperatureK }),
              upper.temperatureK > lower.temperatureK
        else {
            return nil
        }
        let crossesGap = gaps.contains {
            $0.temperatureK > lower.temperatureK && $0.temperatureK < upper.temperatureK
        }
        guard !crossesGap else {
            return nil
        }
        let fraction = (temperatureK - lower.temperatureK) / (upper.temperatureK - lower.temperatureK)
        return lower.pressurePa + fraction * (upper.pressurePa - lower.pressurePa)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }

    private static func range(_ values: [Double]) -> [Double] {
        guard let minimum = values.min(), let maximum = values.max() else { return [] }
        return [minimum, maximum]
    }
}

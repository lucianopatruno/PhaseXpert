import Foundation

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
    let elapsedSeconds: Double
    let totalAttempted: Int
    let totalConverged: Int
    let gapCount: Int
    let bubble: Metric
    let dew: Metric

    enum CodingKeys: String, CodingKey {
        case caseID = "case_id"
        case elapsedSeconds = "elapsed_seconds"
        case totalAttempted = "total_attempted"
        case totalConverged = "total_converged"
        case gapCount = "gap_count"
        case bubble
        case dew
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

@main
enum NativeSRKComparisonReport {
    static func main() throws {
        let datasetPath = "Documentation/Feasibility/LocalPhaseDiagramNeqSimReferenceDataset.json"
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appendingPathComponent(datasetPath))
        let reference = try JSONDecoder().decode(ReferenceDataset.self, from: data)
        let tracer = NativeSRKPhaseEnvelopeTracer()
        let options = NativeSRKEnvelopeOptions(
            minimumTemperatureK: 186.0,
            maximumTemperatureK: 305.0,
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
                elapsedSeconds: local.elapsedSeconds,
                totalAttempted: local.attemptedPointCount,
                totalConverged: local.convergedPointCount,
                gapCount: local.gaps.count,
                bubble: metric(branch: "bubble", referenceCase: referenceCase, local: local),
                dew: metric(branch: "dew", referenceCase: referenceCase, local: local)
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
            comparisonMethod: "Nearest local point on same branch within 1.0 K; no interpolation across gaps and no extrapolation.",
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
        let errors = referencePoints.compactMap { point -> (absolute: Double, relative: Double)? in
            guard let best = localPoints.min(by: {
                abs($0.temperatureK - point.temperatureK) < abs($1.temperatureK - point.temperatureK)
            }),
            abs(best.temperatureK - point.temperatureK) <= 1.0
            else {
                return nil
            }
            let absolute = abs(best.pressurePa - point.pressurePa)
            return (absolute, absolute / point.pressurePa)
        }
        let absoluteErrors = errors.map(\.absolute)
        let relativeErrors = errors.map(\.relative)
        return Metric(
            referenceTemperatureRangeK: range(referencePoints.map(\.temperatureK)),
            localTemperatureRangeK: range(localPoints.map(\.temperatureK)),
            referencePointCount: referencePoints.count,
            attemptedLocalPointCount: local.attemptedPointCount,
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

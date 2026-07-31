import Foundation

/// Review state of a literature-derived experimental reference dataset.
///
/// Only ``approved`` datasets may be evaluated. Approval means that the
/// machine-readable values and units were checked against the cited source; it
/// does not mean that the thermodynamic provider passed validation.
public enum DensityReferenceReviewStatus: String, Codable, Equatable, Sendable {
    case candidate
    case transcribed
    case independentlyVerified
    case approved
}

/// Meaning assigned by the cited source to a reported density uncertainty.
public enum DensityUncertaintyBasis: String, Codable, Equatable, Sendable {
    case standard
    case expanded
    case maximumError
    case reportedAccuracy
}

/// Traceable uncertainty attached to one experimental density value.
public struct DensityUncertainty: Codable, Equatable, Sendable {
    /// Absolute uncertainty in kg/m³, when stated by the source.
    public let absoluteKilogramsPerCubicMetre: Double?
    /// Relative uncertainty as a fraction, where 0.001 means 0.1 %.
    public let relativeFraction: Double?
    public let basis: DensityUncertaintyBasis
    public let coverageFactor: Double?
    public let confidenceLevel: Double?
    /// Table, section, note, or other location in the cited source.
    public let sourceLocation: String

    public init(
        absoluteKilogramsPerCubicMetre: Double? = nil,
        relativeFraction: Double? = nil,
        basis: DensityUncertaintyBasis,
        coverageFactor: Double? = nil,
        confidenceLevel: Double? = nil,
        sourceLocation: String
    ) {
        self.absoluteKilogramsPerCubicMetre = absoluteKilogramsPerCubicMetre
        self.relativeFraction = relativeFraction
        self.basis = basis
        self.coverageFactor = coverageFactor
        self.confidenceLevel = confidenceLevel
        self.sourceLocation = sourceLocation
    }
}

/// One independently published CO₂-N₂ density measurement in SI units.
public struct ExperimentalDensityPoint: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let pressurePa: Double
    public let temperatureK: Double
    public let composition: [MixtureComponent]
    public let densityKilogramsPerCubicMetre: Double
    public let uncertainty: DensityUncertainty
    /// Exact table/row locator without copying copyrighted narrative text.
    public let sourceLocation: String

    public init(
        id: String,
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        densityKilogramsPerCubicMetre: Double,
        uncertainty: DensityUncertainty,
        sourceLocation: String
    ) {
        self.id = id
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.composition = composition
        self.densityKilogramsPerCubicMetre = densityKilogramsPerCubicMetre
        self.uncertainty = uncertainty
        self.sourceLocation = sourceLocation
    }
}

/// Acceptance rule approved before provider deviations are inspected.
public struct DensityAcceptancePolicy: Codable, Equatable, Sendable {
    public let version: String
    /// Maximum absolute relative deviation as a fraction.
    public let maximumAbsoluteRelativeDeviation: Double
    public let rationale: String
    public let approvedBy: String
    public let approvedAt: Date

    public init(
        version: String,
        maximumAbsoluteRelativeDeviation: Double,
        rationale: String,
        approvedBy: String,
        approvedAt: Date
    ) {
        self.version = version
        self.maximumAbsoluteRelativeDeviation = maximumAbsoluteRelativeDeviation
        self.rationale = rationale
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
    }
}

/// Versioned, provenance-preserving collection of experimental density points.
public struct ExperimentalDensityDataset: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let version: String
    public let citation: SourceReference
    public let dataArchiveURL: URL?
    public let dataArchiveVersion: String?
    public let reviewStatus: DensityReferenceReviewStatus
    public let reviewedBy: String?
    public let reviewedAt: Date?
    public let acceptancePolicy: DensityAcceptancePolicy?
    public let points: [ExperimentalDensityPoint]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        version: String,
        citation: SourceReference,
        dataArchiveURL: URL? = nil,
        dataArchiveVersion: String? = nil,
        reviewStatus: DensityReferenceReviewStatus,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil,
        acceptancePolicy: DensityAcceptancePolicy? = nil,
        points: [ExperimentalDensityPoint]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.citation = citation
        self.dataArchiveURL = dataArchiveURL
        self.dataArchiveVersion = dataArchiveVersion
        self.reviewStatus = reviewStatus
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.acceptancePolicy = acceptancePolicy
        self.points = points
    }
}

public enum DensityValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case datasetNotApproved
    case missingReviewProvenance
    case missingAcceptancePolicy
    case invalidAcceptancePolicy
    case emptyDataset
    case duplicatePointID(String)
    case invalidPoint(String)
    case unsupportedComposition(String)
    case missingPrediction(String)
    case invalidPrediction(String)
}

/// Comparison of one provider prediction with one experimental measurement.
public struct DensityValidationCase: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let experimentalDensityKilogramsPerCubicMetre: Double
    public let predictedDensityKilogramsPerCubicMetre: Double
    /// Signed value: (prediction - experiment) / experiment.
    public let relativeDeviation: Double
    public let passed: Bool
}

/// Immutable result of one dataset evaluation.
public struct DensityValidationSummary: Codable, Equatable, Sendable {
    public let datasetID: String
    public let datasetVersion: String
    public let policyVersion: String
    public let cases: [DensityValidationCase]
    public let maximumAbsoluteRelativeDeviation: Double
    public let meanAbsoluteRelativeDeviation: Double
    public let passed: Bool
}

/// Evaluates precomputed density predictions against an approved dataset.
///
/// This type deliberately does not call a thermodynamic provider. Predictions
/// must be generated and recorded separately so dataset approval and tolerance
/// selection can be completed before model deviations are inspected.
public struct DensityValidationEvaluator: Sendable {
    public static let maximumNitrogenMoleFraction = 0.10
    private static let compositionTolerance = 1e-10

    public init() {}

    public func evaluate(
        dataset: ExperimentalDensityDataset,
        predictionsKilogramsPerCubicMetre: [String: Double]
    ) throws -> DensityValidationSummary {
        let policy = try validate(dataset: dataset)
        var cases: [DensityValidationCase] = []
        cases.reserveCapacity(dataset.points.count)

        for point in dataset.points {
            guard let prediction = predictionsKilogramsPerCubicMetre[point.id] else {
                throw DensityValidationError.missingPrediction(point.id)
            }
            guard prediction.isFinite, prediction > 0 else {
                throw DensityValidationError.invalidPrediction(point.id)
            }

            let deviation = (
                prediction - point.densityKilogramsPerCubicMetre
            ) / point.densityKilogramsPerCubicMetre
            cases.append(
                DensityValidationCase(
                    id: point.id,
                    experimentalDensityKilogramsPerCubicMetre:
                        point.densityKilogramsPerCubicMetre,
                    predictedDensityKilogramsPerCubicMetre: prediction,
                    relativeDeviation: deviation,
                    passed: abs(deviation)
                        <= policy.maximumAbsoluteRelativeDeviation
                )
            )
        }

        let absoluteDeviations = cases.map { abs($0.relativeDeviation) }
        let maximum = absoluteDeviations.max() ?? 0
        let mean = absoluteDeviations.reduce(0, +)
            / Double(absoluteDeviations.count)

        return DensityValidationSummary(
            datasetID: dataset.id,
            datasetVersion: dataset.version,
            policyVersion: policy.version,
            cases: cases,
            maximumAbsoluteRelativeDeviation: maximum,
            meanAbsoluteRelativeDeviation: mean,
            passed: cases.allSatisfy(\.passed)
        )
    }

    private func validate(
        dataset: ExperimentalDensityDataset
    ) throws -> DensityAcceptancePolicy {
        guard dataset.schemaVersion == ExperimentalDensityDataset.currentSchemaVersion else {
            throw DensityValidationError.unsupportedSchemaVersion(
                dataset.schemaVersion
            )
        }
        guard dataset.reviewStatus == .approved else {
            throw DensityValidationError.datasetNotApproved
        }
        guard
            let reviewedBy = dataset.reviewedBy,
            !reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            dataset.reviewedAt != nil
        else {
            throw DensityValidationError.missingReviewProvenance
        }
        guard let policy = dataset.acceptancePolicy else {
            throw DensityValidationError.missingAcceptancePolicy
        }
        guard
            policy.maximumAbsoluteRelativeDeviation.isFinite,
            policy.maximumAbsoluteRelativeDeviation > 0,
            !policy.version.isEmpty,
            !policy.rationale.isEmpty,
            !policy.approvedBy.isEmpty
        else {
            throw DensityValidationError.invalidAcceptancePolicy
        }
        guard !dataset.points.isEmpty else {
            throw DensityValidationError.emptyDataset
        }

        var identifiers = Set<String>()
        for point in dataset.points {
            guard identifiers.insert(point.id).inserted else {
                throw DensityValidationError.duplicatePointID(point.id)
            }
            try validate(point: point)
        }
        return policy
    }

    private func validate(point: ExperimentalDensityPoint) throws {
        guard
            !point.id.isEmpty,
            point.pressurePa.isFinite,
            point.pressurePa > 0,
            point.temperatureK.isFinite,
            point.temperatureK > 0,
            point.densityKilogramsPerCubicMetre.isFinite,
            point.densityKilogramsPerCubicMetre > 0,
            !point.sourceLocation.isEmpty,
            uncertaintyIsValid(point.uncertainty)
        else {
            throw DensityValidationError.invalidPoint(point.id)
        }

        let active = point.composition.filter {
            $0.moleFraction > Self.compositionTolerance
        }
        guard
            active.count == 2,
            let carbonDioxide = active.first(where: {
                $0.component == .carbonDioxide
            }),
            let nitrogen = active.first(where: {
                $0.component == .nitrogen
            }),
            active.allSatisfy({
                $0.moleFraction.isFinite && $0.moleFraction >= 0
            }),
            abs(
                carbonDioxide.moleFraction + nitrogen.moleFraction - 1
            ) <= Self.compositionTolerance,
            carbonDioxide.moleFraction > nitrogen.moleFraction,
            nitrogen.moleFraction <= Self.maximumNitrogenMoleFraction
        else {
            throw DensityValidationError.unsupportedComposition(point.id)
        }
    }

    private func uncertaintyIsValid(_ uncertainty: DensityUncertainty) -> Bool {
        let absoluteIsValid = uncertainty.absoluteKilogramsPerCubicMetre.map {
            $0.isFinite && $0 >= 0
        } ?? false
        let relativeIsValid = uncertainty.relativeFraction.map {
            $0.isFinite && $0 >= 0
        } ?? false
        let coverageIsValid = uncertainty.coverageFactor.map {
            $0.isFinite && $0 > 0
        } ?? true
        let confidenceIsValid = uncertainty.confidenceLevel.map {
            $0.isFinite && $0 > 0 && $0 <= 1
        } ?? true

        return (absoluteIsValid || relativeIsValid)
            && coverageIsValid
            && confidenceIsValid
            && !uncertainty.sourceLocation.isEmpty
    }
}

import Foundation
import XCTest
@testable import PhaseXpertCore

final class ExperimentalDensityValidationTests: XCTestCase {
    func testApprovedDatasetEvaluatesSignedRelativeDeviation() throws {
        let dataset = makeDataset(points: [
            makePoint(id: "synthetic-pass", density: 800),
            makePoint(id: "synthetic-fail", density: 800)
        ])

        let summary = try DensityValidationEvaluator().evaluate(
            dataset: dataset,
            predictionsKilogramsPerCubicMetre: [
                "synthetic-pass": 801.2,
                "synthetic-fail": 802.4
            ]
        )

        XCTAssertEqual(summary.cases.count, 2)
        XCTAssertEqual(
            summary.cases[0].relativeDeviation,
            0.0015,
            accuracy: 1e-12
        )
        XCTAssertTrue(summary.cases[0].passed)
        XCTAssertEqual(
            summary.cases[1].relativeDeviation,
            0.003,
            accuracy: 1e-12
        )
        XCTAssertFalse(summary.cases[1].passed)
        XCTAssertEqual(
            summary.maximumAbsoluteRelativeDeviation,
            0.003,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            summary.meanAbsoluteRelativeDeviation,
            0.00225,
            accuracy: 1e-12
        )
        XCTAssertFalse(summary.passed)
    }

    func testDatasetMustBeApprovedBeforePredictionIsInspected() {
        let dataset = makeDataset(reviewStatus: .transcribed)

        XCTAssertThrowsError(
            try DensityValidationEvaluator().evaluate(
                dataset: dataset,
                predictionsKilogramsPerCubicMetre: [
                    "synthetic-point": .nan
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? DensityValidationError,
                .datasetNotApproved
            )
        }
    }

    func testAcceptancePolicyIsMandatory() {
        let dataset = makeDataset(acceptancePolicy: nil)

        XCTAssertThrowsError(
            try DensityValidationEvaluator().evaluate(
                dataset: dataset,
                predictionsKilogramsPerCubicMetre: [
                    "synthetic-point": 800
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? DensityValidationError,
                .missingAcceptancePolicy
            )
        }
    }

    func testPointOutsideCurrentNitrogenScopeIsRejected() {
        let point = ExperimentalDensityPoint(
            id: "outside-scope",
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.89),
                .init(component: .nitrogen, moleFraction: 0.11)
            ],
            densityKilogramsPerCubicMetre: 800,
            uncertainty: makeUncertainty(),
            sourceLocation: "Synthetic schema test"
        )
        let dataset = makeDataset(points: [point])

        XCTAssertThrowsError(
            try DensityValidationEvaluator().evaluate(
                dataset: dataset,
                predictionsKilogramsPerCubicMetre: [
                    "outside-scope": 800
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? DensityValidationError,
                .unsupportedComposition("outside-scope")
            )
        }
    }

    func testHiddenThirdOrNonFiniteComponentIsRejected() {
        let point = ExperimentalDensityPoint(
            id: "malformed-composition",
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05),
                .init(component: .oxygen, moleFraction: .nan)
            ],
            densityKilogramsPerCubicMetre: 800,
            uncertainty: makeUncertainty(),
            sourceLocation: "Synthetic schema test"
        )
        let dataset = makeDataset(points: [point])

        XCTAssertThrowsError(
            try DensityValidationEvaluator().evaluate(
                dataset: dataset,
                predictionsKilogramsPerCubicMetre: [
                    "malformed-composition": 800
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? DensityValidationError,
                .unsupportedComposition("malformed-composition")
            )
        }
    }

    func testNonFinitePredictionIsRejected() {
        let dataset = makeDataset()

        XCTAssertThrowsError(
            try DensityValidationEvaluator().evaluate(
                dataset: dataset,
                predictionsKilogramsPerCubicMetre: [
                    "synthetic-point": .infinity
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? DensityValidationError,
                .invalidPrediction("synthetic-point")
            )
        }
    }

    func testDatasetAndSummaryRoundTripWithoutLosingProvenance() throws {
        let dataset = makeDataset()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let datasetData = try encoder.encode(dataset)
        let decodedDataset = try decoder.decode(
            ExperimentalDensityDataset.self,
            from: datasetData
        )
        XCTAssertEqual(decodedDataset, dataset)

        let summary = try DensityValidationEvaluator().evaluate(
            dataset: dataset,
            predictionsKilogramsPerCubicMetre: [
                "synthetic-point": 800.8
            ]
        )
        let summaryData = try encoder.encode(summary)
        XCTAssertEqual(
            try decoder.decode(
                DensityValidationSummary.self,
                from: summaryData
            ),
            summary
        )
    }

    private func makeDataset(
        reviewStatus: DensityReferenceReviewStatus = .approved,
        acceptancePolicy: DensityAcceptancePolicy? = DensityAcceptancePolicy(
            version: "synthetic-policy-1",
            maximumAbsoluteRelativeDeviation: 0.002,
            rationale: "Synthetic evaluator contract test only.",
            approvedBy: "Test fixture",
            approvedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ),
        points: [ExperimentalDensityPoint]? = nil
    ) -> ExperimentalDensityDataset {
        ExperimentalDensityDataset(
            id: "synthetic-density-schema-test",
            version: "1",
            citation: SourceReference(
                authors: "Test fixture",
                title: "Synthetic values; not experimental data",
                year: 2026,
                doiOrURL: nil
            ),
            reviewStatus: reviewStatus,
            reviewedBy: reviewStatus == .approved ? "Test fixture" : nil,
            reviewedAt: reviewStatus == .approved
                ? Date(timeIntervalSince1970: 1_800_000_000)
                : nil,
            acceptancePolicy: acceptancePolicy,
            points: points ?? [makePoint()]
        )
    }

    private func makePoint(
        id: String = "synthetic-point",
        density: Double = 800
    ) -> ExperimentalDensityPoint {
        ExperimentalDensityPoint(
            id: id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            densityKilogramsPerCubicMetre: density,
            uncertainty: makeUncertainty(),
            sourceLocation: "Synthetic schema test"
        )
    }

    private func makeUncertainty() -> DensityUncertainty {
        DensityUncertainty(
            relativeFraction: 0.001,
            basis: .reportedAccuracy,
            sourceLocation: "Synthetic schema test"
        )
    }
}

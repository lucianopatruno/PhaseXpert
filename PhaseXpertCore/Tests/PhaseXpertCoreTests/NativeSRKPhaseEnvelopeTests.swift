import XCTest
@testable import PhaseXpertCore

final class NativeSRKPhaseEnvelopeTests: XCTestCase {
    private let tracer = NativeSRKPhaseEnvelopeTracer()

    func testPureCO2SaturationProducesFiniteBubbleAndDewPoints() throws {
        let result = try tracer.phaseEnvelope(
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            options: testOptions(maximumTemperatureK: 302.0)
        )

        XCTAssertFalse(result.wasCancelled)
        XCTAssertGreaterThan(result.convergedPointCount, 10)
        XCTAssertEqual(
            result.points.filter { $0.branch == .bubble }.count,
            result.points.filter { $0.branch == .dew }.count
        )
        XCTAssertTrue(result.points.allSatisfy { point in
            point.temperatureK.isFinite
                && point.pressurePa.isFinite
                && point.temperatureK > 0
                && point.pressurePa > 0
        })
    }

    func testCO2NitrogenMixtureProducesSeparateFiniteBranchesOrExplicitGaps() throws {
        let result = try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            options: testOptions(maximumTemperatureK: 280.0)
        )

        let bubblePoints = result.points.filter { $0.branch == .bubble }
        let dewPoints = result.points.filter { $0.branch == .dew }

        XCTAssertGreaterThan(bubblePoints.count, 2)
        XCTAssertGreaterThan(dewPoints.count + result.gaps.filter { $0.branch == .dew }.count, 0)
        XCTAssertTrue(result.points.allSatisfy { $0.status == .converged })
        XCTAssertTrue(result.points.allSatisfy { $0.pressurePa.isFinite && $0.pressurePa > 0 })
        XCTAssertLessThanOrEqual(result.convergedPointCount, result.attemptedPointCount)
    }

    func testStabilityAssessmentReturnsFiniteTangentPlaneDistances() throws {
        let assessment = try tracer.stabilityAssessment(
            temperatureK: 293.15,
            pressurePa: 10_000_000,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ]
        )

        XCTAssertTrue(assessment.liquidLikeTangentPlaneDistance.isFinite)
        XCTAssertTrue(assessment.vaporLikeTangentPlaneDistance.isFinite)
    }

    func testStabilityAssessmentCarriesMinimizedTPDDiagnostics() throws {
        let assessment = try tracer.stabilityAssessment(
            temperatureK: 220.0,
            pressurePa: 2_500_000,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ]
        )

        XCTAssertEqual(assessment.liquidLikeMinimum.trialType, .liquidLike)
        XCTAssertEqual(assessment.vaporLikeMinimum.trialType, .vaporLike)
        XCTAssertTrue(assessment.liquidLikeMinimum.minimumTangentPlaneDistance.isFinite)
        XCTAssertTrue(assessment.vaporLikeMinimum.minimumTangentPlaneDistance.isFinite)
        XCTAssertGreaterThan(assessment.liquidLikeMinimum.iterations, 0)
        XCTAssertGreaterThan(assessment.vaporLikeMinimum.iterations, 0)
        XCTAssertEqual(assessment.liquidLikeMinimum.finalTrialComposition.count, 2)
        XCTAssertEqual(assessment.vaporLikeMinimum.finalTrialComposition.count, 2)
        XCTAssertTrue(assessment.liquidLikeMinimum.residualNorm.isFinite)
        XCTAssertTrue(assessment.vaporLikeMinimum.residualNorm.isFinite)
        XCTAssertFalse(assessment.liquidLikeMinimum.terminationReason.isEmpty)
        XCTAssertFalse(assessment.vaporLikeMinimum.terminationReason.isEmpty)
    }

    func testMultiStartTPDStationaryPointsAreRankedAndDeduplicated() throws {
        let points = try tracer.tangentPlaneDistanceStationaryPoints(
            type: .vaporLike,
            temperatureK: 139.986665,
            pressurePa: 1_000_000,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            additionalTrialCompositions: [
                [0.90, 0.10],
                [0.90, 0.10],
                [0.02, 0.98],
                [1e-6, 1 - 1e-6]
            ]
        )

        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(
            points.map(\.finalTrialComposition).count,
            Set(points.map { $0.finalTrialComposition.map { String(format: "%.8f", $0) }.joined(separator: ",") }).count
        )
        XCTAssertEqual(
            points.map(\.minimumTangentPlaneDistance),
            points.map(\.minimumTangentPlaneDistance).sorted()
        )
        XCTAssertTrue(points.allSatisfy { $0.minimumTangentPlaneDistance.isFinite })
        XCTAssertTrue(points.allSatisfy { $0.residualNorm.isFinite })
    }

    func testRootSelectionDiagnosticReportsPhaseIdentityContinuity() throws {
        let point = try tracer.solveBubblePressure(
            temperatureK: 139.986665,
            liquidComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: testOptions(minimumTemperatureK: 54)
        )
        let diagnostic = try tracer.rootSelectionDiagnostic(
            branch: .bubble,
            temperatureK: point.temperatureK,
            pressurePa: point.pressurePa,
            feedComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            incipientCarbonDioxideMoleFraction: try XCTUnwrap(point.vaporMoleFractions[.carbonDioxide])
        )

        XCTAssertFalse(diagnostic.liquidCompressibilityRoots.isEmpty)
        XCTAssertFalse(diagnostic.vaporCompressibilityRoots.isEmpty)
        XCTAssertTrue(diagnostic.selectedLiquidRoot.isFinite)
        XCTAssertTrue(diagnostic.selectedVaporRoot.isFinite)
        XCTAssertGreaterThan(diagnostic.rootSeparation, 0)
        XCTAssertGreaterThan(diagnostic.densitySeparationMolesPerCubicMeter, 0)
        XCTAssertGreaterThan(diagnostic.phaseCompositionDistance, 0)
        XCTAssertFalse(diagnostic.classification.isEmpty)
    }

    func testColdBubbleInitializationExperimentClassifiesBoundedFailure() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.90),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.10)
        ]
        let point = try tracer.solveBubblePressure(
            temperatureK: 139.986665,
            liquidComposition: composition,
            options: testOptions(minimumTemperatureK: 54)
        )
        let experiment = try tracer.coldBubbleInitializationExperiment(
            startingTemperatureK: point.temperatureK,
            startingPressurePa: point.pressurePa,
            startingVaporCarbonDioxideMoleFraction: try XCTUnwrap(point.vaporMoleFractions[.carbonDioxide]),
            feedComposition: composition,
            options: testOptions(minimumTemperatureK: 54)
        )

        XCTAssertGreaterThan(experiment.multiStartTPDMinimumCount, 0)
        XCTAssertGreaterThanOrEqual(experiment.negativeTPDMinimumCount, 0)
        XCTAssertTrue(experiment.pressureParameterizedAttemptReason.contains("pressure-parameterized"))
        XCTAssertGreaterThan(experiment.flashAttemptCount, 0)
        XCTAssertGreaterThan(experiment.convergedFlashCount, 0)
        XCTAssertGreaterThan(experiment.continuousFlashCount, 0)
        XCTAssertLessThan(try XCTUnwrap(experiment.lowestContinuousFlashTemperatureK), point.temperatureK)
        XCTAssertFalse(experiment.betaLimitDiagnostic.betaSchedule.isEmpty)
        XCTAssertGreaterThan(experiment.betaLimitDiagnostic.attemptedStateCount, 0)
        XCTAssertGreaterThanOrEqual(experiment.betaLimitDiagnostic.acceptedStateCount, 0)
        XCTAssertFalse(experiment.betaLimitDiagnostic.verifiedBubbleLimit)
        XCTAssertFalse(experiment.betaLimitDiagnostic.terminationReason.isEmpty)
        XCTAssertTrue(experiment.rootDiagnostic.selectedLiquidRoot.isFinite)
        XCTAssertTrue(experiment.rootDiagnostic.selectedVaporRoot.isFinite)
        XCTAssertFalse(experiment.productionAttemptReason.isEmpty)
        XCTAssertFalse(experiment.failureClassification.isEmpty)
    }

    func testTwoPhaseFlashDiagnosticSolvesMaterialBalanceAndFugacityEquality() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.90),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.10)
        ]
        let options = testOptions(minimumTemperatureK: 54)
        let point = try tracer.solveBubblePressure(
            temperatureK: 139.986665,
            liquidComposition: composition,
            options: options
        )
        let vaporCO2 = try XCTUnwrap(point.vaporMoleFractions[.carbonDioxide])
        let vaporN2 = try XCTUnwrap(point.vaporMoleFractions[.nitrogen])
        let diagnostic = try tracer.twoPhaseFlashDiagnostic(
            temperatureK: point.temperatureK,
            pressurePa: point.pressurePa,
            composition: composition,
            initialKValues: [vaporCO2 / 0.90, vaporN2 / 0.10],
            initialVaporFraction: 1e-4,
            options: options
        )

        XCTAssertGreaterThan(diagnostic.vaporFraction, 0)
        XCTAssertLessThan(diagnostic.vaporFraction, 1)
        XCTAssertLessThan(diagnostic.fugacityResidualNorm, 1e-3)
        XCTAssertLessThan(diagnostic.materialBalanceResidual, 1e-3)
        XCTAssertEqual(diagnostic.liquidFractions.count, 2)
        XCTAssertEqual(diagnostic.vaporFractions.count, 2)
        XCTAssertGreaterThan(diagnostic.rootDiagnostic.phaseCompositionDistance, 0)
        XCTAssertTrue(diagnostic.terminationReason.contains("two-phase flash converged"))
    }

    func testFiniteBetaStatesRemainExcludedFromBubbleStatistics() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.90),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.10)
        ]
        let result = try tracer.phaseEnvelope(
            composition: composition,
            options: testOptions(minimumTemperatureK: 54)
        )
        let point = try tracer.solveBubblePressure(
            temperatureK: 139.986665,
            liquidComposition: composition,
            options: testOptions(minimumTemperatureK: 54)
        )
        let experiment = try tracer.coldBubbleInitializationExperiment(
            startingTemperatureK: point.temperatureK,
            startingPressurePa: point.pressurePa,
            startingVaporCarbonDioxideMoleFraction: try XCTUnwrap(point.vaporMoleFractions[.carbonDioxide]),
            feedComposition: composition,
            options: testOptions(minimumTemperatureK: 54)
        )

        XCTAssertGreaterThan(experiment.continuousFlashCount, 0)
        XCTAssertNil(result.points.filter { $0.branch == .bubble }.map(\.temperatureK).min { $0 < $1 }.flatMap {
            $0 < 139.0 ? $0 : nil
        })
        XCTAssertFalse(experiment.betaLimitDiagnostic.verifiedBubbleLimit)
    }

    func testConvergedCoupledBubbleCarriesDiagnostics() throws {
        let point = try tracer.solveBubblePressure(
            temperatureK: 220,
            liquidComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            options: testOptions()
        )

        XCTAssertLessThan(point.finalResidualNorm, 1e-6)
        XCTAssertTrue(point.finalStepNorm.isFinite)
        XCTAssertGreaterThan(point.liquidRootCount, 0)
        XCTAssertGreaterThan(point.vaporRootCount, 0)
        XCTAssertTrue(point.selectedLiquidRoot.isFinite)
        XCTAssertTrue(point.selectedVaporRoot.isFinite)
        XCTAssertNotNil(point.stabilityAssessment)
        XCTAssertEqual(point.terminationReason, "coupled fugacity system converged")
    }

    func testPureCO2CriticalRegionDoesNotReturnCollapsedRootPoint() {
        XCTAssertThrowsError(try tracer.solveBubblePressure(
            temperatureK: 296,
            liquidComposition: [.init(component: .carbonDioxide, moleFraction: 1)],
            options: testOptions()
        ))
    }

    func testColdBubbleNearBoundaryRequiresTPDBackedPhaseSeparation() throws {
        let point = try tracer.solveBubblePressure(
            temperatureK: 61.875,
            liquidComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: testOptions(minimumTemperatureK: 54)
        )

        XCTAssertTrue(point.pressurePa.isFinite)
        XCTAssertGreaterThan(point.pressurePa, 0)
        let vaporCO2 = try XCTUnwrap(point.vaporMoleFractions[.carbonDioxide])
        XCTAssertLessThan(vaporCO2, 1e-8)
        let minimumTPD = min(
            point.stabilityAssessment?.liquidLikeTangentPlaneDistance ?? .infinity,
            point.stabilityAssessment?.vaporLikeTangentPlaneDistance ?? .infinity
        )
        XCTAssertLessThan(minimumTPD, -1e-6)
        XCTAssertGreaterThan(point.finalResidualNorm, 0)
        XCTAssertLessThan(point.finalResidualNorm, 1e-6)
    }

    func testPseudoArcLengthCorrectorContinuesBoundedBubbleState() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.97),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.03)
        ]
        let options = testOptions(minimumTemperatureK: 54)
        let previous = try tracer.solveBubblePressure(
            temperatureK: 220,
            liquidComposition: composition,
            options: options
        )
        let current = try tracer.solveBubblePressure(
            temperatureK: 228,
            liquidComposition: composition,
            options: options,
            initialPressurePa: previous.pressurePa
        )

        let diagnostic = try tracer.pseudoArcLengthDiagnosticStep(
            branch: .bubble,
            previousTemperatureK: previous.temperatureK,
            previousPressurePa: previous.pressurePa,
            previousIncipientCarbonDioxideMoleFraction: try XCTUnwrap(previous.vaporMoleFractions[.carbonDioxide]),
            currentTemperatureK: current.temperatureK,
            currentPressurePa: current.pressurePa,
            currentIncipientCarbonDioxideMoleFraction: try XCTUnwrap(current.vaporMoleFractions[.carbonDioxide]),
            feedComposition: composition,
            options: options
        )

        let corrected = try XCTUnwrap(diagnostic.correctedPoint)
        XCTAssertEqual(corrected.branch, .bubble)
        XCTAssertTrue(diagnostic.isContinuousWithSeed)
        XCTAssertLessThan(diagnostic.finalResidualNorm, 1e-8)
        XCTAssertGreaterThan(corrected.temperatureK, current.temperatureK)
        XCTAssertLessThan(corrected.temperatureK - current.temperatureK, 12)
        XCTAssertTrue(diagnostic.tangent.allSatisfy(\.isFinite))
    }

    func testPseudoArcLengthRejectsDetachedColdBubbleJump() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.90),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.10)
        ]
        let options = testOptions(minimumTemperatureK: 54)
        let main = try tracer.solveBubblePressure(
            temperatureK: 139.986665,
            liquidComposition: composition,
            options: options
        )
        let detached = try tracer.solveBubblePressure(
            temperatureK: 61.875,
            liquidComposition: composition,
            options: options
        )

        let diagnostic = try tracer.pseudoArcLengthDiagnosticStep(
            branch: .bubble,
            previousTemperatureK: main.temperatureK,
            previousPressurePa: main.pressurePa,
            previousIncipientCarbonDioxideMoleFraction: try XCTUnwrap(main.vaporMoleFractions[.carbonDioxide]),
            currentTemperatureK: detached.temperatureK,
            currentPressurePa: detached.pressurePa,
            currentIncipientCarbonDioxideMoleFraction: try XCTUnwrap(detached.vaporMoleFractions[.carbonDioxide]),
            feedComposition: composition,
            options: options
        )

        XCTAssertNil(diagnostic.correctedPoint)
        XCTAssertFalse(diagnostic.isContinuousWithSeed)
        XCTAssertTrue(diagnostic.terminationReason.contains("incipient composition boundary"))
    }

    func testProductionTraceExcludesDetachedColdBubbleSegment() throws {
        let result = try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: testOptions(minimumTemperatureK: 54)
        )
        let bubblePoints = result.points.filter { $0.branch == .bubble }
        let bubbleGaps = result.gaps.filter { $0.branch == .bubble }

        XCTAssertFalse(bubblePoints.contains { $0.temperatureK < 139.0 })
        XCTAssertTrue(bubbleGaps.contains {
            $0.temperatureK < 140.0
                && $0.reason.contains("detached")
        })
        XCTAssertGreaterThanOrEqual(bubblePoints.map(\.temperatureK).min() ?? 0, 139.0)
    }

    func testBidirectionalProductionTraceExtendsContinuousBranchBackward() throws {
        let result = try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            options: testOptions(minimumTemperatureK: 54)
        )
        let bubblePoints = result.points.filter { $0.branch == .bubble }

        XCTAssertLessThan(bubblePoints.map(\.temperatureK).min() ?? .infinity, 61.875)
        XCTAssertTrue(bubblePoints.allSatisfy { $0.terminationReason.contains("converged") })
    }

    func testIterationLimitBoundsTraceWork() throws {
        let result = try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: NativeSRKEnvelopeOptions(maximumIterationsPerSolve: 1)
        )

        XCTAssertEqual(result.attemptedPointCount, result.convergedPointCount + result.gaps.count)
        XCTAssertTrue(result.points.allSatisfy { $0.iterations <= 1 })
    }

    func testSingularPressureBoundsAreRejectedAsNonConvergence() {
        XCTAssertThrowsError(try tracer.solveDewPressure(
            temperatureK: 260,
            vaporComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: NativeSRKEnvelopeOptions(
                minimumPressurePa: 1_000_000,
                maximumPressurePa: 1_000_000,
                maximumIterationsPerSolve: 3
            )
        ))
    }

    func testRejectsUnsupportedDuplicateAndNonNormalizedCompositions() {
        XCTAssertThrowsError(try tracer.phaseEnvelope(
            composition: [.init(component: .water, moleFraction: 1)],
            options: testOptions()
        ))

        XCTAssertThrowsError(try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.5),
                .init(component: .carbonDioxide, moleFraction: 0.5)
            ],
            options: testOptions()
        ))

        XCTAssertThrowsError(try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9),
                .init(component: .nitrogen, moleFraction: 0.09)
            ],
            options: testOptions()
        ))
    }

    func testCancellationReturnsPromptlyWithoutCalculatedPoints() throws {
        let result = try tracer.phaseEnvelope(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ],
            options: testOptions(),
            shouldCancel: { true }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.convergedPointCount, 0)
        XCTAssertLessThan(result.elapsedSeconds, 0.1)
    }

    func testRepeatedMixtureTraceIsDeterministic() throws {
        let composition = [
            NativeSRKMixtureFraction(component: .carbonDioxide, moleFraction: 0.90),
            NativeSRKMixtureFraction(component: .nitrogen, moleFraction: 0.10)
        ]
        let first = try tracer.phaseEnvelope(composition: composition, options: testOptions(maximumTemperatureK: 260))
        let second = try tracer.phaseEnvelope(composition: composition, options: testOptions(maximumTemperatureK: 260))

        XCTAssertEqual(first.points.count, second.points.count)
        XCTAssertEqual(first.gaps.count, second.gaps.count)
        for (left, right) in zip(first.points, second.points) {
            XCTAssertEqual(left.branch, right.branch)
            XCTAssertEqual(left.temperatureK, right.temperatureK, accuracy: 1e-12)
            XCTAssertEqual(left.pressurePa, right.pressurePa, accuracy: max(1e-6, abs(left.pressurePa) * 1e-12))
        }
    }

    func testNeqSimReferenceComparisonReportIsFiniteAndNotAcceptedYet() throws {
        let reference = try loadReferenceDataset()
        let tolerances = ReferenceTolerances(
            meanRelativePressureError: 0.10,
            percentile95RelativePressureError: 0.20,
            maximumRelativePressureError: 0.35,
            minimumCoverage: 0.80
        )
        let comparisons = try reference.phaseEnvelopeCases.map { referenceCase in
            try compare(
                referenceCase: referenceCase,
                local: tracer.phaseEnvelope(
                    composition: referenceCase.composition.map {
                        NativeSRKMixtureFraction(component: $0.component, moleFraction: $0.moleFraction)
                    },
                    options: testOptions(minimumTemperatureK: 54.0)
                ),
                tolerances: tolerances
            )
        }

        XCTAssertEqual(comparisons.count, 3)
        XCTAssertTrue(comparisons.contains { $0.bubble.meanRelativePressureError.isFinite })
        XCTAssertTrue(comparisons.contains { $0.bubble.coverage > 0 })
        XCTAssertTrue(comparisons.contains { !$0.passesAcceptanceGate })
    }

    private func testOptions(
        minimumTemperatureK: Double = 220.0,
        maximumTemperatureK: Double = 305.0
    ) -> NativeSRKEnvelopeOptions {
        NativeSRKEnvelopeOptions(
            minimumTemperatureK: minimumTemperatureK,
            maximumTemperatureK: maximumTemperatureK,
            initialTemperatureStepK: 10.0,
            minimumTemperatureStepK: 1.0,
            maximumTemperatureStepK: 12.0,
            maximumIterationsPerSolve: 80,
            maximumConsecutiveFailures: 5
        )
    }

    private func loadReferenceDataset() throws -> ReferenceDataset {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.lastPathComponent != "PhaseXpert" && directory.path != "/" {
            directory.deleteLastPathComponent()
        }
        let url = directory
            .appendingPathComponent("Documentation")
            .appendingPathComponent("Feasibility")
            .appendingPathComponent("LocalPhaseDiagramNeqSimReferenceDataset.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReferenceDataset.self, from: data)
    }

    private func compare(
        referenceCase: ReferenceEnvelopeCase,
        local: NativeSRKEnvelopeResult,
        tolerances: ReferenceTolerances
    ) throws -> ReferenceComparison {
        let bubble = branchComparison(
            branch: "bubble",
            referenceCase: referenceCase,
            local: local
        )
        let dew = branchComparison(
            branch: "dew",
            referenceCase: referenceCase,
            local: local
        )
        return ReferenceComparison(
            caseID: referenceCase.id,
            bubble: bubble,
            dew: dew,
            passesAcceptanceGate: bubble.passes(tolerances) && dew.passes(tolerances)
        )
    }

    private func branchComparison(
        branch: String,
        referenceCase: ReferenceEnvelopeCase,
        local: NativeSRKEnvelopeResult
    ) -> BranchComparison {
        let referencePoints = referenceCase.points.filter { $0.branch == branch }
        let localPoints = local.points.filter { $0.branch.rawValue == branch }.sorted { $0.temperatureK < $1.temperatureK }
        let localGaps = local.gaps.filter { $0.branch.rawValue == branch }
        let errors = referencePoints.compactMap { referencePoint -> Double? in
            guard let localPressure = interpolatedPressure(
                at: referencePoint.temperatureK,
                points: localPoints,
                gaps: localGaps
            ) else {
                return nil
            }
            return abs(localPressure - referencePoint.pressurePa) / referencePoint.pressurePa
        }.sorted()

        return BranchComparison(
            coverage: referencePoints.isEmpty ? 0 : Double(errors.count) / Double(referencePoints.count),
            meanRelativePressureError: errors.isEmpty ? .infinity : errors.reduce(0, +) / Double(errors.count),
            medianRelativePressureError: percentile(errors, 0.50),
            percentile95RelativePressureError: percentile(errors, 0.95),
            maximumRelativePressureError: errors.max() ?? .infinity
        )
    }

    private func percentile(_ sortedValues: [Double], _ fraction: Double) -> Double {
        guard !sortedValues.isEmpty else { return .infinity }
        let index = min(sortedValues.count - 1, max(0, Int((Double(sortedValues.count - 1) * fraction).rounded())))
        return sortedValues[index]
    }

    private func interpolatedPressure(
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
}

private struct ReferenceDataset: Decodable {
    let phaseEnvelopeCases: [ReferenceEnvelopeCase]

    enum CodingKeys: String, CodingKey {
        case phaseEnvelopeCases = "phase_envelope_cases"
    }
}

private struct ReferenceEnvelopeCase: Decodable {
    let id: String
    let points: [ReferencePoint]
    private let request: ReferenceRequest

    var composition: [ReferenceComposition] {
        request.composition
    }
}

private struct ReferenceRequest: Decodable {
    let composition: [ReferenceComposition]
}

private struct ReferenceComposition: Decodable {
    let component: ComponentID
    let moleFraction: Double

    enum CodingKeys: String, CodingKey {
        case component
        case moleFraction = "mole_fraction"
    }
}

private struct ReferencePoint: Decodable {
    let branch: String
    let temperatureK: Double
    let pressurePa: Double

    enum CodingKeys: String, CodingKey {
        case branch
        case temperatureK = "temperature_k"
        case pressurePa = "pressure_pa"
    }
}

private struct ReferenceTolerances {
    let meanRelativePressureError: Double
    let percentile95RelativePressureError: Double
    let maximumRelativePressureError: Double
    let minimumCoverage: Double
}

private struct ReferenceComparison {
    let caseID: String
    let bubble: BranchComparison
    let dew: BranchComparison
    let passesAcceptanceGate: Bool
}

private struct BranchComparison {
    let coverage: Double
    let meanRelativePressureError: Double
    let medianRelativePressureError: Double
    let percentile95RelativePressureError: Double
    let maximumRelativePressureError: Double

    func passes(_ tolerances: ReferenceTolerances) -> Bool {
        coverage >= tolerances.minimumCoverage
            && meanRelativePressureError <= tolerances.meanRelativePressureError
            && percentile95RelativePressureError <= tolerances.percentile95RelativePressureError
            && maximumRelativePressureError <= tolerances.maximumRelativePressureError
    }
}

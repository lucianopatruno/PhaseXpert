import Foundation

public struct NativeSRKMixtureFraction: Sendable, Equatable {
    public let component: ComponentID
    public let moleFraction: Double

    public init(component: ComponentID, moleFraction: Double) {
        self.component = component
        self.moleFraction = moleFraction
    }
}

public enum NativeSRKEnvelopeBranch: String, Sendable, Codable, Equatable {
    case bubble
    case dew
}

public enum NativeSRKSolveStatus: String, Sendable, Codable, Equatable {
    case converged
    case failed
    case cancelled
}

public struct NativeSRKEnvelopePoint: Sendable, Equatable {
    public let branch: NativeSRKEnvelopeBranch
    public let temperatureK: Double
    public let pressurePa: Double
    public let iterations: Int
    public let status: NativeSRKSolveStatus
    public let finalResidualNorm: Double
    public let finalStepNorm: Double
    public let liquidRootCount: Int
    public let vaporRootCount: Int
    public let selectedLiquidRoot: Double
    public let selectedVaporRoot: Double
    public let stabilityAssessment: NativeSRKStabilityAssessment?
    public let terminationReason: String
    public let liquidMoleFractions: [ComponentID: Double]
    public let vaporMoleFractions: [ComponentID: Double]
}

public struct NativeSRKEnvelopeGap: Sendable, Equatable {
    public let branch: NativeSRKEnvelopeBranch
    public let temperatureK: Double
    public let reason: String
}

public struct NativeSRKEnvelopeResult: Sendable, Equatable {
    public let provenance: NativeSRKProvenance
    public let points: [NativeSRKEnvelopePoint]
    public let gaps: [NativeSRKEnvelopeGap]
    public let attemptedPointCount: Int
    public let convergedPointCount: Int
    public let elapsedSeconds: Double
    public let wasCancelled: Bool
}

public struct NativeSRKStabilityAssessment: Sendable, Equatable {
    public let isStable: Bool
    public let liquidLikeTangentPlaneDistance: Double
    public let vaporLikeTangentPlaneDistance: Double
    public let liquidLikeMinimum: NativeSRKTPDMinimum
    public let vaporLikeMinimum: NativeSRKTPDMinimum
}

public enum NativeSRKTPDTrialType: String, Sendable, Codable, Equatable {
    case liquidLike
    case vaporLike
}

public struct NativeSRKTPDMinimum: Sendable, Equatable {
    public let trialType: NativeSRKTPDTrialType
    public let minimumTangentPlaneDistance: Double
    public let iterations: Int
    public let finalTrialComposition: [Double]
    public let residualNorm: Double
    public let terminationReason: String
}

public struct NativeSRKTPDStationaryPoint: Sendable, Equatable {
    public let trialType: NativeSRKTPDTrialType
    public let minimumTangentPlaneDistance: Double
    public let iterations: Int
    public let finalTrialComposition: [Double]
    public let residualNorm: Double
    public let terminationReason: String
    public let isTrivialFeedStationaryPoint: Bool
    public let isBoundaryPinned: Bool
}

public struct NativeSRKRootSelectionDiagnostic: Sendable, Equatable {
    public let temperatureK: Double
    public let pressurePa: Double
    public let liquidCompressibilityRoots: [Double]
    public let vaporCompressibilityRoots: [Double]
    public let selectedLiquidRoot: Double
    public let selectedVaporRoot: Double
    public let rootSeparation: Double
    public let densitySeparationMolesPerCubicMeter: Double
    public let phaseCompositionDistance: Double
    public let classification: String
}

public struct NativeSRKColdBranchExperiment: Sendable, Equatable {
    public let startingTemperatureK: Double
    public let startingPressurePa: Double
    public let productionAttemptReason: String
    public let pressureParameterizedAttemptReason: String
    public let multiStartTPDMinimumCount: Int
    public let negativeTPDMinimumCount: Int
    public let detachedMinimumCount: Int
    public let flashAttemptCount: Int
    public let convergedFlashCount: Int
    public let continuousFlashCount: Int
    public let lowestContinuousFlashTemperatureK: Double?
    public let flashFailureReason: String
    public let betaLimitDiagnostic: NativeSRKBetaLimitDiagnostic
    public let bestContinuousMinimum: NativeSRKTPDStationaryPoint?
    public let rootDiagnostic: NativeSRKRootSelectionDiagnostic
    public let failureClassification: String
}

public struct NativeSRKBetaLimitDiagnostic: Sendable, Equatable {
    public let startingTemperatureK: Double?
    public let startingPressurePa: Double?
    public let startingVaporFraction: Double?
    public let betaSchedule: [Double]
    public let attemptedStateCount: Int
    public let acceptedStateCount: Int
    public let lowestAcceptedBeta: Double?
    public let lowestAcceptedTemperatureK: Double?
    public let verifiedBubbleLimit: Bool
    public let bubbleResidualNorm: Double?
    public let sumZKMinusOne: Double?
    public let terminationReason: String
}

public struct NativeSRKFlashDiagnostic: Sendable, Equatable {
    public let temperatureK: Double
    public let pressurePa: Double
    public let vaporFraction: Double
    public let liquidFractions: [Double]
    public let vaporFractions: [Double]
    public let fugacityResidualNorm: Double
    public let materialBalanceResidual: Double
    public let rootDiagnostic: NativeSRKRootSelectionDiagnostic
    public let terminationReason: String
}

public struct NativeSRKProvenance: Sendable, Equatable {
    public let modelIdentifier = "phasexpert-native-srk-prototype"
    public let eos = "Soave-Redlich-Kwong"
    public let alphaFunction = "Standard Soave alpha"
    public let mixingRule = "Classical van der Waals one-fluid quadratic mixing"
    public let stabilityTest =
        "Bounded multi-start Michelsen tangent-plane-distance minimization using SRK fugacity coefficients"
    public let pressureUpdate =
        "Safeguarded finite-difference Newton on ln pressure with bounded successive-substitution fallback"
    public let componentData =
        "NeqSim 3.16.0 COMP.csv rows CO2 and nitrogen; source commit 3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
    public let interactionData =
        "NeqSim 3.16.0 INTER.csv row 7452 CO2-nitrogen Classic KIJSRK=-0.0171; source commit 3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
    public let gasConstant =
        "CODATA molar gas constant R=8.31446261815324 J mol^-1 K^-1"
    public let license =
        "Prototype constants derived from NeqSim Apache-2.0 source data; retain NeqSim notices before production redistribution."
}

public struct NativeSRKEnvelopeOptions: Sendable, Equatable {
    public let minimumTemperatureK: Double
    public let maximumTemperatureK: Double
    public let initialTemperatureStepK: Double
    public let minimumTemperatureStepK: Double
    public let maximumTemperatureStepK: Double
    public let minimumPressurePa: Double
    public let maximumPressurePa: Double
    public let maximumIterationsPerSolve: Int
    public let relativeTolerance: Double
    public let maximumConsecutiveFailures: Int

    public init(
        minimumTemperatureK: Double = 218.15,
        maximumTemperatureK: Double = 423.15,
        initialTemperatureStepK: Double = 5,
        minimumTemperatureStepK: Double = 0.5,
        maximumTemperatureStepK: Double = 10,
        minimumPressurePa: Double = 50_000,
        maximumPressurePa: Double = 30_000_000,
        maximumIterationsPerSolve: Int = 80,
        relativeTolerance: Double = 1e-8,
        maximumConsecutiveFailures: Int = 6
    ) {
        self.minimumTemperatureK = minimumTemperatureK
        self.maximumTemperatureK = maximumTemperatureK
        self.initialTemperatureStepK = initialTemperatureStepK
        self.minimumTemperatureStepK = minimumTemperatureStepK
        self.maximumTemperatureStepK = maximumTemperatureStepK
        self.minimumPressurePa = minimumPressurePa
        self.maximumPressurePa = maximumPressurePa
        self.maximumIterationsPerSolve = maximumIterationsPerSolve
        self.relativeTolerance = relativeTolerance
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
    }
}

public final class NativeSRKPhaseEnvelopeTracer: @unchecked Sendable {
    public enum NativeSRKError: Error, Equatable {
        case unsupportedComponent(ComponentID)
        case duplicateComponent(ComponentID)
        case invalidComposition(String)
        case invalidTemperature(Double)
    }

    private struct Parameter {
        let criticalTemperatureK: Double
        let criticalPressurePa: Double
        let acentricFactor: Double
    }

    private struct ComponentIDTerm {
        let component: ComponentID
        let fraction: Double
        let a: Double
        let b: Double
    }

    private struct MixtureTerm {
        let a: Double
        let b: Double
        let aij: [[Double]]
        let components: [ComponentIDTerm]
    }

    private struct SolveOutcome {
        let pressurePa: Double
        let iterations: Int
        let liquidFractions: [Double]
        let vaporFractions: [Double]
        let finalResidualNorm: Double
        let finalStepNorm: Double
        let liquidRootCount: Int
        let vaporRootCount: Int
        let selectedLiquidRoot: Double
        let selectedVaporRoot: Double
        let stabilityAssessment: NativeSRKStabilityAssessment?
        let terminationReason: String
    }

    private struct BranchCandidate {
        let temperatureK: Double
        let outcome: SolveOutcome
    }

    private struct FugacityResult {
        let coefficients: [Double]
        let rootCount: Int
        let selectedRoot: Double
    }

    private struct TPDTrial {
        let type: NativeSRKTPDTrialType
        let composition: [Double]
    }

    public struct PseudoArcLengthDiagnostic: Sendable, Equatable {
        public let predictedTemperatureK: Double
        public let predictedPressurePa: Double
        public let correctedPoint: NativeSRKEnvelopePoint?
        public let tangent: [Double]
        public let finalResidualNorm: Double
        public let terminationReason: String
        public let isContinuousWithSeed: Bool
    }

    fileprivate struct ArcState {
        let temperatureK: Double
        let logPressure: Double
        let compositionLogit: Double
    }

    public static let gasConstant = 8.314_462_618_153_24

    private let parameters: [ComponentID: Parameter] = [
        .carbonDioxide: Parameter(
            criticalTemperatureK: 31.04 + 273.15,
            criticalPressurePa: 73.815 * 100_000,
            acentricFactor: 0.2276
        ),
        .nitrogen: Parameter(
            criticalTemperatureK: -147.05 + 273.15,
            criticalPressurePa: 33.944 * 100_000,
            acentricFactor: 0.0403
        )
    ]

    private let binaryInteraction: [Set<ComponentID>: Double] = [
        Set([.carbonDioxide, .nitrogen]): -0.0171
    ]

    public init() {}

    public func phaseEnvelope(
        composition inputComposition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> NativeSRKEnvelopeResult {
        let start = Date()
        let composition = try validatedComposition(inputComposition)
        var points: [NativeSRKEnvelopePoint] = []
        var gaps: [NativeSRKEnvelopeGap] = []
        var attempted = 0
        var cancelled = false

        if composition.count == 1, composition[0].component == .carbonDioxide {
            tracePureCarbonDioxide(
                options: options,
                shouldCancel: shouldCancel,
                points: &points,
                gaps: &gaps,
                attempted: &attempted,
                cancelled: &cancelled
            )
        } else {
            traceMixtureBranch(
                .bubble,
                composition: composition,
                options: options,
                shouldCancel: shouldCancel,
                points: &points,
                gaps: &gaps,
                attempted: &attempted,
                cancelled: &cancelled
            )
            if !cancelled {
                traceMixtureBranch(
                    .dew,
                    composition: composition,
                    options: options,
                    shouldCancel: shouldCancel,
                    points: &points,
                    gaps: &gaps,
                    attempted: &attempted,
                    cancelled: &cancelled
                )
            }
        }

        return NativeSRKEnvelopeResult(
            provenance: NativeSRKProvenance(),
            points: points.sorted { lhs, rhs in
                if lhs.branch != rhs.branch {
                    return lhs.branch.rawValue < rhs.branch.rawValue
                }
                if lhs.temperatureK != rhs.temperatureK {
                    return lhs.temperatureK < rhs.temperatureK
                }
                return lhs.pressurePa < rhs.pressurePa
            },
            gaps: gaps,
            attemptedPointCount: attempted,
            convergedPointCount: points.count,
            elapsedSeconds: Date().timeIntervalSince(start),
            wasCancelled: cancelled
        )
    }

    public func solveBubblePressure(
        temperatureK: Double,
        liquidComposition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        initialPressurePa: Double? = nil,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> NativeSRKEnvelopePoint {
        let composition = try validatedComposition(liquidComposition)
        guard temperatureK.isFinite, temperatureK > 0 else {
            throw NativeSRKError.invalidTemperature(temperatureK)
        }
        let fractions = composition.map(\.moleFraction)
        let outcome = try solveBubble(
            temperatureK: temperatureK,
            liquidFractions: fractions,
            components: composition.map(\.component),
            options: options,
            initialPressurePa: initialPressurePa,
            shouldCancel: shouldCancel
        )
        return point(
            branch: .bubble,
            temperatureK: temperatureK,
            outcome: outcome,
            components: composition.map(\.component)
        )
    }

    public func stabilityAssessment(
        temperatureK: Double,
        pressurePa: Double,
        composition inputComposition: [NativeSRKMixtureFraction]
    ) throws -> NativeSRKStabilityAssessment {
        let composition = try validatedComposition(inputComposition)
        let components = composition.map(\.component)
        let fractions = composition.map(\.moleFraction)
        let liquidMinimum = try minimizedTangentPlaneDistance(
            type: .liquidLike,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: fractions,
            components: components
        )
        let vaporMinimum = try minimizedTangentPlaneDistance(
            type: .vaporLike,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: fractions,
            components: components
        )
        return NativeSRKStabilityAssessment(
            isStable: min(
                vaporMinimum.minimumTangentPlaneDistance,
                liquidMinimum.minimumTangentPlaneDistance
            ) >= -1e-8,
            liquidLikeTangentPlaneDistance: liquidMinimum.minimumTangentPlaneDistance,
            vaporLikeTangentPlaneDistance: vaporMinimum.minimumTangentPlaneDistance,
            liquidLikeMinimum: liquidMinimum,
            vaporLikeMinimum: vaporMinimum
        )
    }

    public func tangentPlaneDistanceStationaryPoints(
        type: NativeSRKTPDTrialType,
        temperatureK: Double,
        pressurePa: Double,
        composition inputComposition: [NativeSRKMixtureFraction],
        additionalTrialCompositions: [[Double]] = []
    ) throws -> [NativeSRKTPDStationaryPoint] {
        let composition = try validatedComposition(inputComposition)
        let components = composition.map(\.component)
        let fractions = composition.map(\.moleFraction)
        return try rankedTPDStationaryPoints(
            type: type,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: fractions,
            components: components,
            additionalTrialCompositions: additionalTrialCompositions
        )
    }

    public func rootSelectionDiagnostic(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        pressurePa: Double,
        feedComposition inputComposition: [NativeSRKMixtureFraction],
        incipientCarbonDioxideMoleFraction: Double
    ) throws -> NativeSRKRootSelectionDiagnostic {
        let composition = try validatedComposition(inputComposition)
        let components = composition.map(\.component)
        let feedFractions = composition.map(\.moleFraction)
        let incipient = binaryFractions(fromLogit: logit(incipientCarbonDioxideMoleFraction))
        let liquidFractions = branch == .bubble ? feedFractions : incipient
        let vaporFractions = branch == .bubble ? incipient : feedFractions
        return try rootSelectionDiagnostic(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            liquidFractions: liquidFractions,
            vaporFractions: vaporFractions,
            components: components
        )
    }

    public func coldBubbleInitializationExperiment(
        startingTemperatureK: Double,
        startingPressurePa: Double,
        startingVaporCarbonDioxideMoleFraction: Double,
        feedComposition inputComposition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> NativeSRKColdBranchExperiment {
        let composition = try validatedComposition(inputComposition)
        guard composition.count == 2 else {
            throw NativeSRKError.invalidComposition("Cold-branch experiment currently supports binary mixtures only.")
        }
        if shouldCancel() { throw CancellationError() }
        let components = composition.map(\.component)
        let feedFractions = composition.map(\.moleFraction)
        let incipient = binaryFractions(fromLogit: logit(startingVaporCarbonDioxideMoleFraction))
        let tpdPoints = try rankedTPDStationaryPoints(
            type: .vaporLike,
            temperatureK: startingTemperatureK,
            pressurePa: startingPressurePa,
            feedFractions: feedFractions,
            components: components,
            additionalTrialCompositions: branchNeighborhoodSeeds(feedFractions: feedFractions, incipient: incipient)
        )
        let rootDiagnostic = try rootSelectionDiagnostic(
            temperatureK: startingTemperatureK,
            pressurePa: startingPressurePa,
            liquidFractions: feedFractions,
            vaporFractions: incipient,
            components: components
        )
        let pressureParameterizedReason = pressureParameterizedBubbleReason(
            startingTemperatureK: startingTemperatureK,
            startingPressurePa: startingPressurePa,
            feedFractions: feedFractions,
            components: components,
            options: options,
            shouldCancel: shouldCancel
        )
        let flashDiagnostics = boundedColdFlashSearch(
            startingTemperatureK: startingTemperatureK,
            startingPressurePa: startingPressurePa,
            startingIncipient: incipient,
            feedFractions: feedFractions,
            components: components,
            options: options,
            shouldCancel: shouldCancel
        )
        let continuousFlash = flashDiagnostics.converged.filter {
            $0.vaporFraction > 1e-6
                && $0.vaporFraction < 0.25
                && maxRelativeDelta($0.vaporFractions, incipient) <= 0.5
                && $0.rootDiagnostic.phaseCompositionDistance > 1e-5
        }
        let betaLimit = betaLimitDiagnostic(
            flashStates: continuousFlash,
            feedFractions: feedFractions,
            components: components,
            options: options,
            shouldCancel: shouldCancel
        )
        let continuousTPD = tpdPoints.filter {
            !$0.isTrivialFeedStationaryPoint
                && !$0.isBoundaryPinned
                && maxRelativeDelta($0.finalTrialComposition, incipient) <= 0.5
        }
        let negativeTPD = tpdPoints.filter { $0.minimumTangentPlaneDistance < -1e-8 }
        let detached = negativeTPD.filter {
            maxRelativeDelta($0.finalTrialComposition, incipient) > 0.5 || $0.isBoundaryPinned
        }
        let productionReason: String
        do {
            _ = try solveBinaryEquilibrium(
                branch: .bubble,
                temperatureK: max(options.minimumTemperatureK, startingTemperatureK - options.minimumTemperatureStepK),
                feedFractions: feedFractions,
                components: components,
                options: options,
                initialPressurePa: startingPressurePa,
                shouldCancel: shouldCancel
            )
            productionReason = "bounded production initialization advances from the accepted branch"
        } catch {
            productionReason = "\(error)"
        }
        let classification: String
        if rootDiagnostic.rootSeparation <= 1e-8 || rootDiagnostic.densitySeparationMolesPerCubicMeter <= 1e-6 {
            classification = "loss or coalescence of admissible EOS roots"
        } else if betaLimit.verifiedBubbleLimit {
            classification = "finite-beta flash path successfully connected to the genuine bubble boundary"
        } else if !continuousFlash.isEmpty {
            classification = "finite-beta path terminates before the bubble limit"
        } else if continuousTPD.contains(where: { $0.minimumTangentPlaneDistance < -1e-8 }) {
            classification = "bordered-corrector/continuation failure"
        } else if !negativeTPD.isEmpty {
            classification = "genuine native-SRK branch termination or model-parity limitation"
        } else if tpdPoints.allSatisfy(\.isTrivialFeedStationaryPoint) {
            classification = "stability minimization failure"
        } else {
            classification = "still indeterminate: pressure-parameterized and flash diagnostics found no continuous accepted path within deterministic bounds"
        }
        return NativeSRKColdBranchExperiment(
            startingTemperatureK: startingTemperatureK,
            startingPressurePa: startingPressurePa,
            productionAttemptReason: productionReason,
            pressureParameterizedAttemptReason: pressureParameterizedReason,
            multiStartTPDMinimumCount: tpdPoints.count,
            negativeTPDMinimumCount: negativeTPD.count,
            detachedMinimumCount: detached.count,
            flashAttemptCount: flashDiagnostics.attempts,
            convergedFlashCount: flashDiagnostics.converged.count,
            continuousFlashCount: continuousFlash.count,
            lowestContinuousFlashTemperatureK: continuousFlash.map(\.temperatureK).min(),
            flashFailureReason: flashDiagnostics.failureReason,
            betaLimitDiagnostic: betaLimit,
            bestContinuousMinimum: continuousTPD.first,
            rootDiagnostic: rootDiagnostic,
            failureClassification: classification
        )
    }

    public func twoPhaseFlashDiagnostic(
        temperatureK: Double,
        pressurePa: Double,
        composition inputComposition: [NativeSRKMixtureFraction],
        initialKValues: [Double],
        initialVaporFraction: Double,
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> NativeSRKFlashDiagnostic {
        let composition = try validatedComposition(inputComposition)
        guard composition.count == 2, initialKValues.count == 2 else {
            throw NativeSRKError.invalidComposition("Binary flash diagnostic requires two components and two K-values.")
        }
        let state = [
            log(clamp(initialKValues[0], 1e-8, 1e8)),
            log(clamp(initialKValues[1], 1e-8, 1e8)),
            logit(initialVaporFraction)
        ]
        return try solveTwoPhaseFlash(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: composition.map(\.moleFraction),
            components: composition.map(\.component),
            initialState: state,
            options: options,
            shouldCancel: shouldCancel
        )
    }

    public func solveDewPressure(
        temperatureK: Double,
        vaporComposition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        initialPressurePa: Double? = nil,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> NativeSRKEnvelopePoint {
        let composition = try validatedComposition(vaporComposition)
        guard temperatureK.isFinite, temperatureK > 0 else {
            throw NativeSRKError.invalidTemperature(temperatureK)
        }
        let fractions = composition.map(\.moleFraction)
        let outcome = try solveDew(
            temperatureK: temperatureK,
            vaporFractions: fractions,
            components: composition.map(\.component),
            options: options,
            initialPressurePa: initialPressurePa,
            shouldCancel: shouldCancel
        )
        return point(
            branch: .dew,
            temperatureK: temperatureK,
            outcome: outcome,
            components: composition.map(\.component)
        )
    }

    public func pseudoArcLengthDiagnosticStep(
        branch: NativeSRKEnvelopeBranch,
        previousTemperatureK: Double,
        previousPressurePa: Double,
        previousIncipientCarbonDioxideMoleFraction: Double,
        currentTemperatureK: Double,
        currentPressurePa: Double,
        currentIncipientCarbonDioxideMoleFraction: Double,
        feedComposition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions = NativeSRKEnvelopeOptions(),
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> PseudoArcLengthDiagnostic {
        let composition = try validatedComposition(feedComposition)
        guard composition.count == 2 else {
            throw NativeSRKError.invalidComposition("Pseudo-arc diagnostic currently supports binary mixtures only.")
        }
        let components = composition.map(\.component)
        let feedFractions = composition.map(\.moleFraction)
        let previous = ArcState(
            temperatureK: previousTemperatureK,
            logPressure: log(previousPressurePa),
            compositionLogit: logit(previousIncipientCarbonDioxideMoleFraction)
        )
        let current = ArcState(
            temperatureK: currentTemperatureK,
            logPressure: log(currentPressurePa),
            compositionLogit: logit(currentIncipientCarbonDioxideMoleFraction)
        )
        let tangent = try arcTangent(
            branch: branch,
            state: current,
            preferredDirection: arcDelta(from: previous, to: current),
            feedFractions: feedFractions,
            components: components,
            options: options
        )
        let arcStep = min(
            0.4,
            max(0.05, scaledArcDistance(from: previous, to: current) * 0.5)
        )
        let predictor = boundedArcState(
            ArcState(
                temperatureK: current.temperatureK + tangent[0] * arcStep,
                logPressure: current.logPressure + tangent[1] * arcStep,
                compositionLogit: current.compositionLogit + tangent[2] * arcStep
            ),
            options: options
        )
        do {
            let corrected = try correctPseudoArcLength(
                branch: branch,
                predictor: predictor,
                tangent: tangent,
                current: current,
                feedFractions: feedFractions,
                components: components,
                options: options,
                shouldCancel: shouldCancel
            )
            let residual = try arcEquilibriumResidual(
                branch: branch,
                state: corrected,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let outcome = try coupledOutcome(
                branch: branch,
                temperatureK: corrected.temperatureK,
                feedFractions: feedFractions,
                state: [corrected.logPressure, corrected.compositionLogit],
                components: components,
                iterations: options.maximumIterationsPerSolve,
                residualNorm: vectorNorm(residual),
                stepNorm: scaledArcDistance(from: current, to: corrected),
                terminationReason: "pseudo-arc-length bordered corrector converged"
            )
            let point = point(
                branch: branch,
                temperatureK: corrected.temperatureK,
                outcome: outcome,
                components: components
            )
            let pressureJump = abs(corrected.logPressure - current.logPressure)
            let temperatureJump = abs(corrected.temperatureK - current.temperatureK)
            return PseudoArcLengthDiagnostic(
                predictedTemperatureK: predictor.temperatureK,
                predictedPressurePa: exp(predictor.logPressure),
                correctedPoint: point,
                tangent: tangent,
                finalResidualNorm: vectorNorm(residual),
                terminationReason: "pseudo-arc-length bordered corrector converged",
                isContinuousWithSeed: pressureJump <= log(3.0)
                    && temperatureJump <= max(12.0, options.maximumTemperatureStepK * 2)
            )
        } catch {
            return PseudoArcLengthDiagnostic(
                predictedTemperatureK: predictor.temperatureK,
                predictedPressurePa: exp(predictor.logPressure),
                correctedPoint: nil,
                tangent: tangent,
                finalResidualNorm: .infinity,
                terminationReason: "\(error)",
                isContinuousWithSeed: false
            )
        }
    }

    private func tracePureCarbonDioxide(
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool,
        points: inout [NativeSRKEnvelopePoint],
        gaps: inout [NativeSRKEnvelopeGap],
        attempted: inout Int,
        cancelled: inout Bool
    ) {
        var temperature = options.minimumTemperatureK
        var step = options.initialTemperatureStepK
        var failures = 0
        let criticalTemperature = parameters[.carbonDioxide]!.criticalTemperatureK

        while temperature <= min(options.maximumTemperatureK, criticalTemperature * 0.999_999) {
            if shouldCancel() {
                cancelled = true
                return
            }
            attempted += 2
            do {
                let outcome = try solvePureSaturation(
                    temperatureK: temperature,
                    options: options,
                    shouldCancel: shouldCancel
                )
                let bubble = point(
                    branch: .bubble,
                    temperatureK: temperature,
                    outcome: outcome,
                    components: [.carbonDioxide]
                )
                let dew = point(
                    branch: .dew,
                    temperatureK: temperature,
                    outcome: outcome,
                    components: [.carbonDioxide]
                )
                points.append(bubble)
                points.append(dew)
                failures = 0
                step = min(options.maximumTemperatureStepK, step * 1.2)
                temperature += step
            } catch {
                gaps.append(.init(branch: .bubble, temperatureK: temperature, reason: "\(error)"))
                gaps.append(.init(branch: .dew, temperatureK: temperature, reason: "\(error)"))
                failures += 1
                if !points.isEmpty, failures >= options.maximumConsecutiveFailures {
                    return
                }
                step = max(options.minimumTemperatureStepK, step / 2)
                temperature += step
            }
        }
    }

    private func traceMixtureBranch(
        _ branch: NativeSRKEnvelopeBranch,
        composition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool,
        points: inout [NativeSRKEnvelopePoint],
        gaps: inout [NativeSRKEnvelopeGap],
        attempted: inout Int,
        cancelled: inout Bool
    ) {
        var temperature = options.minimumTemperatureK
        var step = options.initialTemperatureStepK
        var failures = 0
        var pressureGuess: Double?
        var currentSegment: [BranchCandidate] = []
        var acceptedSegments: [[BranchCandidate]] = []
        let components = composition.map(\.component)
        let fractions = composition.map(\.moleFraction)

        while temperature <= options.maximumTemperatureK {
            if shouldCancel() {
                cancelled = true
                return
            }
            attempted += 1
            do {
                let outcome: SolveOutcome
                switch branch {
                case .bubble:
                    outcome = try solveBubble(
                        temperatureK: temperature,
                        liquidFractions: fractions,
                        components: components,
                        options: options,
                        initialPressurePa: pressureGuess,
                        shouldCancel: shouldCancel
                    )
                case .dew:
                    outcome = try solveDew(
                        temperatureK: temperature,
                        vaporFractions: fractions,
                        components: components,
                        options: options,
                        initialPressurePa: pressureGuess,
                        shouldCancel: shouldCancel
                    )
                }
                currentSegment.append(.init(temperatureK: temperature, outcome: outcome))
                pressureGuess = outcome.pressurePa
                failures = 0
                step = min(options.maximumTemperatureStepK, step * 1.15)
                temperature += step
            } catch {
                if !currentSegment.isEmpty {
                    acceptedSegments.append(currentSegment)
                    currentSegment.removeAll()
                }
                gaps.append(.init(branch: branch, temperatureK: temperature, reason: "\(error)"))
                failures += 1
                if pressureGuess != nil, failures >= options.maximumConsecutiveFailures {
                    pressureGuess = nil
                    failures = 0
                }
                step = max(options.minimumTemperatureStepK, step / 2)
                temperature += step
            }
        }
        if !currentSegment.isEmpty {
            acceptedSegments.append(currentSegment)
        }

        var selectedSegment = selectedContinuousSegment(acceptedSegments)
        let selectedAnchorTemperature = selectedSegment.first?.temperatureK
        if selectedSegment.count >= 2 {
            continueSelectedSegmentWithPseudoArc(
                branch,
                selectedSegment: &selectedSegment,
                composition: composition,
                options: options,
                shouldCancel: shouldCancel,
                gaps: &gaps,
                attempted: &attempted,
                cancelled: &cancelled
            )
        }
        points.append(contentsOf: selectedSegment.map {
            point(
                branch: branch,
                temperatureK: $0.temperatureK,
                outcome: $0.outcome,
                components: components
            )
        })
        let rejectedSegments = acceptedSegments.filter { segment in
            guard let first = segment.first, let selectedAnchorTemperature else { return false }
            return abs(first.temperatureK - selectedAnchorTemperature) > 1e-9
        }
        for segment in rejectedSegments {
            for candidate in segment {
                gaps.append(.init(
                    branch: branch,
                    temperatureK: candidate.temperatureK,
                    reason: "Converged seed rejected because it is detached from the selected continuous pseudo-arc branch."
                ))
            }
        }
    }

    private func selectedContinuousSegment(_ segments: [[BranchCandidate]]) -> [BranchCandidate] {
        segments.max { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            return (lhs.last?.temperatureK ?? -.infinity) < (rhs.last?.temperatureK ?? -.infinity)
        } ?? []
    }

    private func continueSelectedSegmentWithPseudoArc(
        _ branch: NativeSRKEnvelopeBranch,
        selectedSegment: inout [BranchCandidate],
        composition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool,
        gaps: inout [NativeSRKEnvelopeGap],
        attempted: inout Int,
        cancelled: inout Bool
    ) {
        continueSelectedSegmentWithPseudoArc(
            branch,
            selectedSegment: &selectedSegment,
            composition: composition,
            options: options,
            shouldCancel: shouldCancel,
            gaps: &gaps,
            attempted: &attempted,
            cancelled: &cancelled,
            direction: .forward
        )
        if !cancelled {
            continueSelectedSegmentWithPseudoArc(
                branch,
                selectedSegment: &selectedSegment,
                composition: composition,
                options: options,
                shouldCancel: shouldCancel,
                gaps: &gaps,
                attempted: &attempted,
                cancelled: &cancelled,
                direction: .backward
            )
        }
    }

    private enum PseudoArcDirection {
        case forward
        case backward
    }

    private func continueSelectedSegmentWithPseudoArc(
        _ branch: NativeSRKEnvelopeBranch,
        selectedSegment: inout [BranchCandidate],
        composition: [NativeSRKMixtureFraction],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool,
        gaps: inout [NativeSRKEnvelopeGap],
        attempted: inout Int,
        cancelled: inout Bool,
        direction: PseudoArcDirection
    ) {
        let components = composition.map(\.component)
        var arcStepCount = 0
        while arcStepCount < 12, selectedSegment.count >= 2 {
            if shouldCancel() {
                cancelled = true
                return
            }
            let previous: BranchCandidate
            let current: BranchCandidate
            switch direction {
            case .forward:
                previous = selectedSegment[selectedSegment.count - 2]
                current = selectedSegment[selectedSegment.count - 1]
            case .backward:
                previous = selectedSegment[1]
                current = selectedSegment[0]
            }
            attempted += 1
            do {
                let diagnostic = try pseudoArcLengthDiagnosticStep(
                    branch: branch,
                    previousTemperatureK: previous.temperatureK,
                    previousPressurePa: previous.outcome.pressurePa,
                    previousIncipientCarbonDioxideMoleFraction: incipientCarbonDioxideFraction(
                        branch: branch,
                        outcome: previous.outcome,
                        components: components
                    ),
                    currentTemperatureK: current.temperatureK,
                    currentPressurePa: current.outcome.pressurePa,
                    currentIncipientCarbonDioxideMoleFraction: incipientCarbonDioxideFraction(
                        branch: branch,
                        outcome: current.outcome,
                        components: components
                    ),
                    feedComposition: composition,
                    options: options,
                    shouldCancel: shouldCancel
                )
                guard diagnostic.isContinuousWithSeed,
                      let corrected = diagnostic.correctedPoint,
                      acceptsPseudoArcCandidate(
                        corrected,
                        current: current,
                        direction: direction,
                        selectedSegment: selectedSegment,
                        options: options
                      )
                else {
                    gaps.append(.init(
                        branch: branch,
                        temperatureK: diagnostic.predictedTemperatureK,
                        reason: "Pseudo-arc \(direction) continuation rejected non-continuous, duplicate, reversing, or out-of-domain candidate: \(diagnostic.terminationReason)"
                    ))
                    return
                }
                let candidate = BranchCandidate(
                    temperatureK: corrected.temperatureK,
                    outcome: SolveOutcome(
                        pressurePa: corrected.pressurePa,
                        iterations: corrected.iterations,
                        liquidFractions: components.map { corrected.liquidMoleFractions[$0] ?? 0 },
                        vaporFractions: components.map { corrected.vaporMoleFractions[$0] ?? 0 },
                        finalResidualNorm: corrected.finalResidualNorm,
                        finalStepNorm: corrected.finalStepNorm,
                        liquidRootCount: corrected.liquidRootCount,
                        vaporRootCount: corrected.vaporRootCount,
                        selectedLiquidRoot: corrected.selectedLiquidRoot,
                        selectedVaporRoot: corrected.selectedVaporRoot,
                        stabilityAssessment: corrected.stabilityAssessment,
                        terminationReason: corrected.terminationReason
                    )
                )
                switch direction {
                case .forward:
                    selectedSegment.append(candidate)
                case .backward:
                    selectedSegment.insert(candidate, at: 0)
                }
                arcStepCount += 1
            } catch {
                gaps.append(.init(
                    branch: branch,
                    temperatureK: current.temperatureK,
                    reason: "Pseudo-arc \(direction) continuation failed: \(error)"
                ))
                return
            }
        }
    }

    private func acceptsPseudoArcCandidate(
        _ point: NativeSRKEnvelopePoint,
        current: BranchCandidate,
        direction: PseudoArcDirection,
        selectedSegment: [BranchCandidate],
        options: NativeSRKEnvelopeOptions
    ) -> Bool {
        guard point.temperatureK >= options.minimumTemperatureK,
              point.temperatureK <= options.maximumTemperatureK,
              point.pressurePa >= options.minimumPressurePa,
              point.pressurePa <= options.maximumPressurePa,
              point.finalResidualNorm.isFinite,
              point.finalResidualNorm <= sqrt(options.relativeTolerance)
        else {
            return false
        }
        let temperatureDelta = point.temperatureK - current.temperatureK
        switch direction {
        case .forward:
            guard temperatureDelta > 1e-6 else { return false }
        case .backward:
            guard temperatureDelta < -1e-6 else { return false }
        }
        let pressureJump = abs(log(point.pressurePa / current.outcome.pressurePa))
        guard pressureJump <= log(3.0) else { return false }
        guard !selectedSegment.contains(where: { abs($0.temperatureK - point.temperatureK) < 1e-5 }) else {
            return false
        }
        return true
    }

    private func incipientCarbonDioxideFraction(
        branch: NativeSRKEnvelopeBranch,
        outcome: SolveOutcome,
        components: [ComponentID]
    ) -> Double {
        let fractions = branch == .bubble ? outcome.vaporFractions : outcome.liquidFractions
        guard let index = components.firstIndex(of: .carbonDioxide) else { return fractions[0] }
        return fractions[index]
    }

    private func solveBubble(
        temperatureK: Double,
        liquidFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialPressurePa: Double?,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        if components.count == 1 {
            return try solvePureSaturation(
                temperatureK: temperatureK,
                options: options,
                shouldCancel: shouldCancel
            )
        }
        return try solveBinaryEquilibrium(
            branch: .bubble,
            temperatureK: temperatureK,
            feedFractions: liquidFractions,
            components: components,
            options: options,
            initialPressurePa: initialPressurePa
                ?? wilsonBubblePressure(temperatureK: temperatureK, fractions: liquidFractions, components: components),
            shouldCancel: shouldCancel
        )
    }

    private func solveDew(
        temperatureK: Double,
        vaporFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialPressurePa: Double?,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        if components.count == 1 {
            return try solvePureSaturation(
                temperatureK: temperatureK,
                options: options,
                shouldCancel: shouldCancel
            )
        }
        return try solveBinaryEquilibrium(
            branch: .dew,
            temperatureK: temperatureK,
            feedFractions: vaporFractions,
            components: components,
            options: options,
            initialPressurePa: initialPressurePa
                ?? wilsonDewPressure(temperatureK: temperatureK, fractions: vaporFractions, components: components),
            shouldCancel: shouldCancel
        )
    }

    private func pressureParameterizedBubbleReason(
        startingTemperatureK: Double,
        startingPressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) -> String {
        let pressureSeeds = uniqueBounded(
            [
                startingPressurePa * 0.90,
                startingPressurePa,
                startingPressurePa * 1.10
            ],
            lower: options.minimumPressurePa,
            upper: options.maximumPressurePa
        )
        var failures: [String] = []
        for pressure in pressureSeeds.prefix(3) {
            if shouldCancel() { return "cancelled before pressure-parameterized bubble search" }
            do {
                let candidate = try solveBubbleTemperatureAtPressure(
                    pressurePa: pressure,
                    initialTemperatureK: startingTemperatureK - options.minimumTemperatureStepK,
                    feedFractions: feedFractions,
                    components: components,
                    options: options,
                    shouldCancel: shouldCancel
                )
                let temperatureDistance = startingTemperatureK - candidate.temperatureK
                if temperatureDistance > 0, temperatureDistance <= max(4.0, options.maximumTemperatureStepK) {
                    return "pressure-parameterized bubble solve advanced continuously to \(candidate.temperatureK) K"
                }
                failures.append("pressure \(pressure) Pa converged outside continuity neighborhood at \(candidate.temperatureK) K")
            } catch {
                failures.append("\(error)")
            }
        }
        return "pressure-parameterized bubble search found no continuous cold-side state: "
            + failures.prefix(3).joined(separator: " | ")
    }

    private func solveBubbleTemperatureAtPressure(
        pressurePa: Double,
        initialTemperatureK: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) throws -> (temperatureK: Double, incipient: [Double], residualNorm: Double) {
        var state = [
            clamp(initialTemperatureK, options.minimumTemperatureK, options.maximumTemperatureK),
            logit(incipientCompositionSeeds(
                branch: .bubble,
                temperatureK: clamp(initialTemperatureK, options.minimumTemperatureK, options.maximumTemperatureK),
                pressurePa: pressurePa,
                feedFractions: feedFractions,
                components: components
            ).first?[0] ?? feedFractions[0])
        ]
        var bestNorm = Double.infinity
        for _ in 1...min(options.maximumIterationsPerSolve, 40) {
            if shouldCancel() { throw CancellationError() }
            let residual = try fixedPressureBubbleResidual(
                pressurePa: pressurePa,
                state: state,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let norm = vectorNorm(residual)
            bestNorm = min(bestNorm, norm)
            if norm <= sqrt(options.relativeTolerance) {
                return (state[0], binaryFractions(fromLogit: state[1]), norm)
            }
            let jacobian = try fixedPressureBubbleJacobian(
                pressurePa: pressurePa,
                state: state,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let determinant = jacobian[0][0] * jacobian[1][1] - jacobian[0][1] * jacobian[1][0]
            guard determinant.isFinite, abs(determinant) > 1e-10 else {
                throw NativeSRKError.invalidComposition(
                    "pressure-parameterized bubble system is singular; best residual norm \(bestNorm)."
                )
            }
            let rawStep = [
                (-residual[0] * jacobian[1][1] + jacobian[0][1] * residual[1]) / determinant,
                (jacobian[1][0] * residual[0] - jacobian[0][0] * residual[1]) / determinant
            ]
            guard rawStep.allSatisfy(\.isFinite) else {
                throw NativeSRKError.invalidComposition("pressure-parameterized bubble step is non-finite.")
            }
            let boundedStep = [
                clamp(rawStep[0], -max(1.0, options.maximumTemperatureStepK), max(1.0, options.maximumTemperatureStepK)),
                clamp(rawStep[1], -1.5, 1.5)
            ]
            var damping = 1.0
            var accepted: [Double]?
            while damping >= 1.0 / 64.0 {
                if shouldCancel() { throw CancellationError() }
                let candidate = [
                    clamp(state[0] + damping * boundedStep[0], options.minimumTemperatureK, options.maximumTemperatureK),
                    clamp(state[1] + damping * boundedStep[1], -30, 30)
                ]
                do {
                    let candidateNorm = vectorNorm(try fixedPressureBubbleResidual(
                        pressurePa: pressurePa,
                        state: candidate,
                        feedFractions: feedFractions,
                        components: components,
                        options: options
                    ))
                    if candidateNorm.isFinite, candidateNorm < norm {
                        accepted = candidate
                        break
                    }
                } catch {
                    damping /= 2
                    continue
                }
                damping /= 2
            }
            guard let accepted else {
                throw NativeSRKError.invalidComposition(
                    "pressure-parameterized bubble line search failed; best residual norm \(bestNorm)."
                )
            }
            state = accepted
        }
        throw NativeSRKError.invalidComposition(
            "pressure-parameterized bubble solve did not converge; best residual norm \(bestNorm)."
        )
    }

    private func fixedPressureBubbleResidual(
        pressurePa: Double,
        state: [Double],
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [Double] {
        try coupledResidual(
            branch: .bubble,
            temperatureK: clamp(state[0], options.minimumTemperatureK, options.maximumTemperatureK),
            feedFractions: feedFractions,
            state: [log(pressurePa), state[1]],
            components: components,
            options: options
        )
    }

    private func fixedPressureBubbleJacobian(
        pressurePa: Double,
        state: [Double],
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [[Double]] {
        let steps = [max(1e-3, state[0] * 1e-6), 1e-4]
        var columns: [[Double]] = []
        for index in 0..<2 {
            var lower = state
            var upper = state
            lower[index] -= steps[index]
            upper[index] += steps[index]
            lower[0] = clamp(lower[0], options.minimumTemperatureK, options.maximumTemperatureK)
            upper[0] = clamp(upper[0], options.minimumTemperatureK, options.maximumTemperatureK)
            lower[1] = clamp(lower[1], -30, 30)
            upper[1] = clamp(upper[1], -30, 30)
            let lowerResidual = try fixedPressureBubbleResidual(
                pressurePa: pressurePa,
                state: lower,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let upperResidual = try fixedPressureBubbleResidual(
                pressurePa: pressurePa,
                state: upper,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let denominator = upper[index] - lower[index]
            guard denominator.isFinite, abs(denominator) > .ulpOfOne else {
                throw NativeSRKError.invalidComposition("pressure-parameterized finite-difference step collapsed.")
            }
            columns.append([
                (upperResidual[0] - lowerResidual[0]) / denominator,
                (upperResidual[1] - lowerResidual[1]) / denominator
            ])
        }
        return [
            [columns[0][0], columns[1][0]],
            [columns[0][1], columns[1][1]]
        ]
    }

    private func boundedColdFlashSearch(
        startingTemperatureK: Double,
        startingPressurePa: Double,
        startingIncipient: [Double],
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) -> (attempts: Int, converged: [NativeSRKFlashDiagnostic], failureReason: String) {
        let temperatureOffsets = [0.0, -0.5, -1.0, -2.0, -4.0, -8.0, -16.0, -32.0]
        let pressureScales = [1.0, 0.95, 1.05, 0.85, 1.15]
        let baseK = zip(startingIncipient, feedFractions).map { clamp($0 / max($1, 1e-12), 1e-8, 1e8) }
        let betaSeeds = [1e-4, 1e-3, 0.01, 0.05, 0.20]
        var attempts = 0
        var converged: [NativeSRKFlashDiagnostic] = []
        var failures: [String] = []
        for offset in temperatureOffsets {
            for scale in pressureScales {
                for beta in betaSeeds {
                    if shouldCancel() {
                        return (attempts, converged, "cancelled during bounded flash search")
                    }
                    attempts += 1
                    let temperature = clamp(
                        startingTemperatureK + offset,
                        options.minimumTemperatureK,
                        options.maximumTemperatureK
                    )
                    let pressure = clamp(
                        startingPressurePa * scale,
                        options.minimumPressurePa,
                        options.maximumPressurePa
                    )
                    do {
                        let diagnostic = try solveTwoPhaseFlash(
                            temperatureK: temperature,
                            pressurePa: pressure,
                            feedFractions: feedFractions,
                            components: components,
                            initialState: [log(baseK[0]), log(baseK[1]), logit(beta)],
                            options: options,
                            shouldCancel: shouldCancel
                        )
                        if !converged.contains(where: {
                            abs($0.temperatureK - diagnostic.temperatureK) < 1e-9
                                && abs(log($0.pressurePa / diagnostic.pressurePa)) < 1e-8
                                && abs($0.vaporFraction - diagnostic.vaporFraction) < 1e-8
                        }) {
                            converged.append(diagnostic)
                        }
                    } catch {
                        if failures.count < 5 {
                            failures.append("\(error)")
                        }
                    }
                }
            }
        }
        return (
            attempts,
            converged.sorted {
                if $0.temperatureK != $1.temperatureK { return $0.temperatureK < $1.temperatureK }
                return $0.pressurePa < $1.pressurePa
            },
            failures.joined(separator: " | ")
        )
    }

    private func betaLimitDiagnostic(
        flashStates: [NativeSRKFlashDiagnostic],
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) -> NativeSRKBetaLimitDiagnostic {
        let schedule = [1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 3e-5, 1e-5, 3e-6, 1e-6]
        guard let start = flashStates
            .filter({ $0.vaporFraction > 1e-5 })
            .min(by: { abs($0.vaporFraction - 0.01) < abs($1.vaporFraction - 0.01) })
        else {
            return NativeSRKBetaLimitDiagnostic(
                startingTemperatureK: nil,
                startingPressurePa: nil,
                startingVaporFraction: nil,
                betaSchedule: schedule,
                attemptedStateCount: 0,
                acceptedStateCount: 0,
                lowestAcceptedBeta: nil,
                lowestAcceptedTemperatureK: nil,
                verifiedBubbleLimit: false,
                bubbleResidualNorm: nil,
                sumZKMinusOne: nil,
                terminationReason: "no continuity-compatible finite-beta flash state available for beta-limit continuation"
            )
        }
        let baseK = zip(start.vaporFractions, start.liquidFractions).map {
            clamp($0 / max($1, 1e-12), 1e-8, 1e8)
        }
        var accepted: [NativeSRKFlashDiagnostic] = []
        var attempts = 0
        var previous = start
        var failures: [String] = []
        for beta in schedule {
            if shouldCancel() {
                return NativeSRKBetaLimitDiagnostic(
                    startingTemperatureK: start.temperatureK,
                    startingPressurePa: start.pressurePa,
                    startingVaporFraction: start.vaporFraction,
                    betaSchedule: schedule,
                    attemptedStateCount: attempts,
                    acceptedStateCount: accepted.count,
                    lowestAcceptedBeta: accepted.map(\.vaporFraction).min(),
                    lowestAcceptedTemperatureK: accepted.map(\.temperatureK).min(),
                    verifiedBubbleLimit: false,
                    bubbleResidualNorm: nil,
                    sumZKMinusOne: nil,
                    terminationReason: "cancelled during beta-limit continuation"
                )
            }
            attempts += 1
            do {
                let diagnostic = try solveTwoPhaseFlash(
                    temperatureK: previous.temperatureK,
                    pressurePa: previous.pressurePa,
                    feedFractions: feedFractions,
                    components: components,
                    initialState: [log(baseK[0]), log(baseK[1]), logit(beta)],
                    options: options,
                    shouldCancel: shouldCancel
                )
                guard diagnostic.vaporFraction <= max(beta * 10, previous.vaporFraction),
                      abs(diagnostic.temperatureK - previous.temperatureK) <= 4,
                      abs(log(diagnostic.pressurePa / previous.pressurePa)) <= log(1.5),
                      maxRelativeDelta(diagnostic.vaporFractions, previous.vaporFractions) <= 0.75
                else {
                    failures.append("beta \(beta) converged outside continuity bounds")
                    break
                }
                accepted.append(diagnostic)
                previous = diagnostic
            } catch {
                failures.append("beta \(beta): \(error)")
                break
            }
        }
        let last = accepted.last
        let kValues = last.map { zip($0.vaporFractions, $0.liquidFractions).map { $0 / max($1, 1e-12) } }
        let sumZKMinusOne = kValues.map { zip(feedFractions, $0).reduce(0.0) { $0 + $1.0 * $1.1 } - 1 }
        let bubbleResidual = last.flatMap { diagnostic -> Double? in
            let incipientCO2 = diagnostic.vaporFractions.first ?? .nan
            guard incipientCO2.isFinite else { return nil }
            do {
                let residual = try coupledResidual(
                    branch: .bubble,
                    temperatureK: diagnostic.temperatureK,
                    feedFractions: feedFractions,
                    state: [log(diagnostic.pressurePa), logit(incipientCO2)],
                    components: components,
                    options: options
                )
                return vectorNorm(residual)
            } catch {
                return nil
            }
        }
        let verified = (last?.vaporFraction ?? 1) <= 1e-6
            && (bubbleResidual ?? .infinity) <= sqrt(options.relativeTolerance)
            && abs(sumZKMinusOne ?? .infinity) <= sqrt(options.relativeTolerance)
            && (last?.rootDiagnostic.phaseCompositionDistance ?? 0) > 1e-5
        let reason: String
        if verified {
            reason = "finite-beta continuation reached a verified bubble limit"
        } else if let last {
            reason = "finite-beta path remains diagnostic-only; beta \(last.vaporFraction), bubble residual \(bubbleResidual ?? .infinity), sum zK minus one \(sumZKMinusOne ?? .infinity). "
                + (failures.first ?? "beta schedule ended before boundary acceptance")
        } else {
            reason = failures.first ?? "no beta-limit flash state accepted"
        }
        return NativeSRKBetaLimitDiagnostic(
            startingTemperatureK: start.temperatureK,
            startingPressurePa: start.pressurePa,
            startingVaporFraction: start.vaporFraction,
            betaSchedule: schedule,
            attemptedStateCount: attempts,
            acceptedStateCount: accepted.count,
            lowestAcceptedBeta: accepted.map(\.vaporFraction).min(),
            lowestAcceptedTemperatureK: accepted.map(\.temperatureK).min(),
            verifiedBubbleLimit: verified,
            bubbleResidualNorm: bubbleResidual,
            sumZKMinusOne: sumZKMinusOne,
            terminationReason: reason
        )
    }

    private func solveTwoPhaseFlash(
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        initialState: [Double],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) throws -> NativeSRKFlashDiagnostic {
        var state = boundedFlashState(initialState)
        var bestNorm = Double.infinity
        for iteration in 1...min(options.maximumIterationsPerSolve, 60) {
            if shouldCancel() { throw CancellationError() }
            let residual = try flashResidual(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                feedFractions: feedFractions,
                components: components,
                state: state
            )
            let norm = vectorNorm(residual)
            bestNorm = min(bestNorm, norm)
            if norm <= sqrt(options.relativeTolerance) {
                return try flashDiagnostic(
                    temperatureK: temperatureK,
                    pressurePa: pressurePa,
                    feedFractions: feedFractions,
                    components: components,
                    state: state,
                    residual: residual,
                    terminationReason: "two-phase flash converged in \(iteration) iterations"
                )
            }
            let jacobian = try flashJacobian(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                feedFractions: feedFractions,
                components: components,
                state: state
            )
            let step = try solveLinear3(jacobian, residual.map { -$0 })
            let boundedStep = [
                clamp(step[0], -1.5, 1.5),
                clamp(step[1], -1.5, 1.5),
                clamp(step[2], -1.5, 1.5)
            ]
            var damping = 1.0
            var accepted: [Double]?
            while damping >= 1.0 / 64.0 {
                if shouldCancel() { throw CancellationError() }
                let candidate = boundedFlashState(zip(state, boundedStep).map { $0 + damping * $1 })
                do {
                    let candidateNorm = vectorNorm(try flashResidual(
                        temperatureK: temperatureK,
                        pressurePa: pressurePa,
                        feedFractions: feedFractions,
                        components: components,
                        state: candidate
                    ))
                    if candidateNorm.isFinite, candidateNorm < norm {
                        accepted = candidate
                        break
                    }
                } catch {
                    damping /= 2
                    continue
                }
                damping /= 2
            }
            guard let accepted else {
                throw NativeSRKError.invalidComposition("two-phase flash line search failed; best residual norm \(bestNorm).")
            }
            state = accepted
        }
        throw NativeSRKError.invalidComposition("two-phase flash did not converge; best residual norm \(bestNorm).")
    }

    private func flashResidual(
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        state: [Double]
    ) throws -> [Double] {
        let split = flashSplit(feedFractions: feedFractions, state: state)
        let liquid = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: split.liquid,
            components: components,
            useLiquidRoot: true
        )
        let vapor = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: split.vapor,
            components: components,
            useLiquidRoot: false
        )
        let fugacityResiduals = feedFractions.indices.map { index in
            log(max(split.liquid[index], 1e-15)) + log(max(liquid[index], 1e-15))
                - log(max(split.vapor[index], 1e-15)) - log(max(vapor[index], 1e-15))
        }
        return [fugacityResiduals[0], fugacityResiduals[1], split.rachfordRice]
    }

    private func flashJacobian(
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        state: [Double]
    ) throws -> [[Double]] {
        let steps = [1e-4, 1e-4, 1e-4]
        var columns: [[Double]] = []
        for index in 0..<3 {
            var lower = state
            var upper = state
            lower[index] -= steps[index]
            upper[index] += steps[index]
            lower = boundedFlashState(lower)
            upper = boundedFlashState(upper)
            let lowerResidual = try flashResidual(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                feedFractions: feedFractions,
                components: components,
                state: lower
            )
            let upperResidual = try flashResidual(
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                feedFractions: feedFractions,
                components: components,
                state: upper
            )
            let denominator = upper[index] - lower[index]
            guard denominator.isFinite, abs(denominator) > .ulpOfOne else {
                throw NativeSRKError.invalidComposition("flash finite-difference step collapsed.")
            }
            columns.append([
                (upperResidual[0] - lowerResidual[0]) / denominator,
                (upperResidual[1] - lowerResidual[1]) / denominator,
                (upperResidual[2] - lowerResidual[2]) / denominator
            ])
        }
        return [
            [columns[0][0], columns[1][0], columns[2][0]],
            [columns[0][1], columns[1][1], columns[2][1]],
            [columns[0][2], columns[1][2], columns[2][2]]
        ]
    }

    private func flashDiagnostic(
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        state: [Double],
        residual: [Double],
        terminationReason: String
    ) throws -> NativeSRKFlashDiagnostic {
        let split = flashSplit(feedFractions: feedFractions, state: state)
        guard split.vaporFraction > 1e-8, split.vaporFraction < 1 - 1e-8 else {
            throw NativeSRKError.invalidComposition("flash converged outside finite two-phase vapor-fraction bounds.")
        }
        guard maxRelativeDelta(split.liquid, split.vapor) > 1e-5 else {
            throw NativeSRKError.invalidComposition("flash converged to a trivial phase split.")
        }
        let rootDiagnostic = try rootSelectionDiagnostic(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            liquidFractions: split.liquid,
            vaporFractions: split.vapor,
            components: components
        )
        return NativeSRKFlashDiagnostic(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            vaporFraction: split.vaporFraction,
            liquidFractions: split.liquid,
            vaporFractions: split.vapor,
            fugacityResidualNorm: vectorNorm([residual[0], residual[1]]),
            materialBalanceResidual: abs(residual[2]),
            rootDiagnostic: rootDiagnostic,
            terminationReason: terminationReason
        )
    }

    private func solveBinaryEquilibrium(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialPressurePa: Double,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        guard components.count == 2, feedFractions.count == 2 else {
            throw NativeSRKError.invalidComposition("Coupled SRK prototype currently supports binary mixtures only.")
        }

        if branch == .dew {
            let pressure = clamp(initialPressurePa, options.minimumPressurePa, options.maximumPressurePa)
            let wilson = wilsonKValues(temperatureK: temperatureK, pressurePa: pressure, components: components)
            let incipientGuess = boundedBinaryFractions(normalized(zip(feedFractions, wilson).map { $0 / $1 }))
            return try solveBinaryEquilibriumFromState(
                branch: branch,
                temperatureK: temperatureK,
                feedFractions: feedFractions,
                components: components,
                options: options,
                initialState: [log(pressure), logit(incipientGuess[0])],
                shouldCancel: shouldCancel
            )
        }

        var candidates: [[Double]] = []
        var failureReasons: [String] = []
        let pressureSeeds = pressureSeeds(
            temperatureK: temperatureK,
            feedFractions: feedFractions,
            components: components,
            initialPressurePa: initialPressurePa,
            options: options
        )
        for pressure in pressureSeeds {
            if shouldCancel() { throw CancellationError() }
            for composition in incipientCompositionSeeds(
                branch: branch,
                temperatureK: temperatureK,
                pressurePa: pressure,
                feedFractions: feedFractions,
                components: components
            ) {
                let state = [log(pressure), logit(composition[0])]
                if !candidates.contains(where: { maxRelativeDelta($0, state) < 1e-8 }) {
                    candidates.append(state)
                }
            }
        }

        var bestOutcome: SolveOutcome?
        var bestScore = Double.infinity
        let referencePressure = clamp(initialPressurePa, options.minimumPressurePa, options.maximumPressurePa)
        for state in candidates.prefix(18) {
            if shouldCancel() { throw CancellationError() }
            do {
                let outcome = try solveBinaryEquilibriumFromState(
                    branch: branch,
                    temperatureK: temperatureK,
                    feedFractions: feedFractions,
                    components: components,
                    options: options,
                    initialState: state,
                    shouldCancel: shouldCancel
                )
                let pressureScore = abs(log(outcome.pressurePa / referencePressure))
                let residualScore = log10(max(outcome.finalResidualNorm, 1e-15)) * 1e-3
                let score = pressureScore + residualScore
                if score.isFinite, score < bestScore {
                    bestScore = score
                    bestOutcome = outcome
                }
            } catch {
                failureReasons.append("\(error)")
            }
        }

        if let bestOutcome {
            return bestOutcome
        }

        throw NativeSRKError.invalidComposition(
            "\(branch.rawValue) coupled solve failed for \(min(candidates.count, 18)) bounded seeds; "
                + failureReasons.prefix(3).joined(separator: " | ")
        )
    }

    private func solveBinaryEquilibriumFromState(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialState: [Double],
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        var state = boundedState(initialState, options: options)
        var previousNorm = Double.infinity
        var finalStepNorm = Double.infinity
        var bestResidual = [Double.infinity, Double.infinity]
        var bestNorm = Double.infinity

        for iteration in 1...options.maximumIterationsPerSolve {
            if shouldCancel() { throw CancellationError() }
            let residual = try coupledResidual(
                branch: branch,
                temperatureK: temperatureK,
                feedFractions: feedFractions,
                state: state,
                components: components,
                options: options
            )
            let residualNorm = vectorNorm(residual)
            if residualNorm < bestNorm {
                bestNorm = residualNorm
                bestResidual = residual
            }
            if residualNorm <= options.relativeTolerance {
                return try coupledOutcome(
                    branch: branch,
                    temperatureK: temperatureK,
                    feedFractions: feedFractions,
                    state: state,
                    components: components,
                    iterations: iteration,
                    residualNorm: residualNorm,
                    stepNorm: finalStepNorm.isFinite ? finalStepNorm : 0,
                    terminationReason: "coupled fugacity system converged"
                )
            }

            let jacobian = try finiteDifferenceJacobian(
                branch: branch,
                temperatureK: temperatureK,
                feedFractions: feedFractions,
                state: state,
                components: components,
                options: options
            )
            let determinant = jacobian[0][0] * jacobian[1][1] - jacobian[0][1] * jacobian[1][0]
            guard determinant.isFinite, abs(determinant) > 1e-10 else {
                throw NativeSRKError.invalidComposition(
                    "\(branch.rawValue) coupled solve has singular Jacobian; residual norm \(residualNorm)."
                )
            }
            let rawStep = [
                (-residual[0] * jacobian[1][1] + jacobian[0][1] * residual[1]) / determinant,
                (jacobian[1][0] * residual[0] - jacobian[0][0] * residual[1]) / determinant
            ]
            guard rawStep.allSatisfy(\.isFinite) else {
                throw NativeSRKError.invalidComposition("\(branch.rawValue) Newton step is non-finite.")
            }
            let boundedStep = [
                clamp(rawStep[0], -log(2), log(2)),
                clamp(rawStep[1], -2.0, 2.0)
            ]
            var acceptedState: [Double]?
            var acceptedNorm = residualNorm
            var damping = 1.0
            while damping >= 1.0 / 64.0 {
                if shouldCancel() { throw CancellationError() }
                let candidate = boundedState(
                    [
                        state[0] + damping * boundedStep[0],
                        state[1] + damping * boundedStep[1]
                    ],
                    options: options
                )
                do {
                    let candidateResidual = try coupledResidual(
                        branch: branch,
                        temperatureK: temperatureK,
                        feedFractions: feedFractions,
                        state: candidate,
                        components: components,
                        options: options
                    )
                    let candidateNorm = vectorNorm(candidateResidual)
                    if candidateNorm.isFinite, candidateNorm < residualNorm {
                        acceptedState = candidate
                        acceptedNorm = candidateNorm
                        break
                    }
                } catch {
                    damping /= 2
                    continue
                }
                damping /= 2
            }
            guard let nextState = acceptedState else {
                if residualNorm < previousNorm {
                    previousNorm = residualNorm
                    continue
                }
                throw NativeSRKError.invalidComposition(
                    "\(branch.rawValue) line search failed; best residual norm \(bestNorm), residuals \(bestResidual)."
                )
            }
            finalStepNorm = vectorNorm([
                nextState[0] - state[0],
                nextState[1] - state[1]
            ])
            state = nextState
            previousNorm = acceptedNorm

            if finalStepNorm <= 1e-9, acceptedNorm <= sqrt(options.relativeTolerance) {
                return try coupledOutcome(
                    branch: branch,
                    temperatureK: temperatureK,
                    feedFractions: feedFractions,
                    state: state,
                    components: components,
                    iterations: iteration,
                    residualNorm: acceptedNorm,
                    stepNorm: finalStepNorm,
                    terminationReason: "coupled fugacity system converged by bounded step"
                )
            }
        }

        throw NativeSRKError.invalidComposition(
            "\(branch.rawValue) coupled solve did not converge; best residual norm \(bestNorm), residuals \(bestResidual)."
        )
    }

    private func pressureSeeds(
        temperatureK: Double,
        feedFractions: [Double],
        components: [ComponentID],
        initialPressurePa: Double,
        options: NativeSRKEnvelopeOptions
    ) -> [Double] {
        let wilsonBubble = wilsonBubblePressure(
            temperatureK: temperatureK,
            fractions: feedFractions,
            components: components
        )
        let wilsonDew = wilsonDewPressure(
            temperatureK: temperatureK,
            fractions: feedFractions,
            components: components
        )
        let geometric: [Double] = [
            options.minimumPressurePa,
            100_000,
            1_000_000,
            10_000_000,
            options.maximumPressurePa
        ]
        return uniqueBounded([
            initialPressurePa,
            wilsonBubble,
            wilsonDew
        ] + geometric, lower: options.minimumPressurePa, upper: options.maximumPressurePa)
    }

    private func incipientCompositionSeeds(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID]
    ) -> [[Double]] {
        let wilson = wilsonKValues(temperatureK: temperatureK, pressurePa: pressurePa, components: components)
        let wilsonSeed: [Double]
        switch branch {
        case .bubble:
            wilsonSeed = normalized(zip(feedFractions, wilson).map { $0 * $1 })
        case .dew:
            wilsonSeed = normalized(zip(feedFractions, wilson).map { $0 / $1 })
        }
        let tpdType: NativeSRKTPDTrialType = branch == .bubble ? .vaporLike : .liquidLike
        let tpdSeed = try? minimizedTangentPlaneDistance(
            type: tpdType,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: feedFractions,
            components: components
        ).finalTrialComposition
        return uniqueCompositions([
            tpdSeed,
            wilsonSeed,
            [0.999, 0.001],
            [0.90, 0.10],
            [0.50, 0.50],
            [0.10, 0.90],
            [0.001, 0.999]
        ].compactMap { $0 }.map(boundedBinaryFractions))
    }

    private func coupledResidual(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        feedFractions: [Double],
        state: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [Double] {
        let pressurePa = clamp(exp(state[0]), options.minimumPressurePa, options.maximumPressurePa)
        let incipient = binaryFractions(fromLogit: state[1])
        let liquidFractions: [Double]
        let vaporFractions: [Double]
        switch branch {
        case .bubble:
            liquidFractions = feedFractions
            vaporFractions = incipient
        case .dew:
            liquidFractions = incipient
            vaporFractions = feedFractions
        }
        let liquid = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: liquidFractions,
            components: components,
            useLiquidRoot: true
        )
        let vapor = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: vaporFractions,
            components: components,
            useLiquidRoot: false
        )
        return liquidFractions.indices.map { index in
            let liquidFugacity = max(liquidFractions[index], 1e-15) * max(liquid.coefficients[index], 1e-15)
            let vaporFugacity = max(vaporFractions[index], 1e-15) * max(vapor.coefficients[index], 1e-15)
            return log(liquidFugacity) - log(vaporFugacity)
        }
    }

    private func finiteDifferenceJacobian(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        feedFractions: [Double],
        state: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [[Double]] {
        let steps = [1e-4, 1e-4]
        var columns: [[Double]] = []
        for index in 0..<2 {
            var lower = state
            var upper = state
            lower[index] -= steps[index]
            upper[index] += steps[index]
            lower = boundedState(lower, options: options)
            upper = boundedState(upper, options: options)
            let lowerResidual = try coupledResidual(
                branch: branch,
                temperatureK: temperatureK,
                feedFractions: feedFractions,
                state: lower,
                components: components,
                options: options
            )
            let upperResidual = try coupledResidual(
                branch: branch,
                temperatureK: temperatureK,
                feedFractions: feedFractions,
                state: upper,
                components: components,
                options: options
            )
            let denominator = upper[index] - lower[index]
            guard abs(denominator) > .ulpOfOne else {
                throw NativeSRKError.invalidComposition("Finite-difference Jacobian step collapsed.")
            }
            columns.append([
                (upperResidual[0] - lowerResidual[0]) / denominator,
                (upperResidual[1] - lowerResidual[1]) / denominator
            ])
        }
        return [
            [columns[0][0], columns[1][0]],
            [columns[0][1], columns[1][1]]
        ]
    }

    private func arcEquilibriumResidual(
        branch: NativeSRKEnvelopeBranch,
        state: ArcState,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [Double] {
        try coupledResidual(
            branch: branch,
            temperatureK: state.temperatureK,
            feedFractions: feedFractions,
            state: [state.logPressure, state.compositionLogit],
            components: components,
            options: options
        )
    }

    private func arcJacobian(
        branch: NativeSRKEnvelopeBranch,
        state: ArcState,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [[Double]] {
        let steps = [max(1e-3, state.temperatureK * 1e-6), 1e-4, 1e-4]
        var columns: [[Double]] = []
        for index in 0..<3 {
            var lower = state
            var upper = state
            switch index {
            case 0:
                lower = ArcState(
                    temperatureK: state.temperatureK - steps[index],
                    logPressure: state.logPressure,
                    compositionLogit: state.compositionLogit
                )
                upper = ArcState(
                    temperatureK: state.temperatureK + steps[index],
                    logPressure: state.logPressure,
                    compositionLogit: state.compositionLogit
                )
            case 1:
                lower = ArcState(
                    temperatureK: state.temperatureK,
                    logPressure: state.logPressure - steps[index],
                    compositionLogit: state.compositionLogit
                )
                upper = ArcState(
                    temperatureK: state.temperatureK,
                    logPressure: state.logPressure + steps[index],
                    compositionLogit: state.compositionLogit
                )
            default:
                lower = ArcState(
                    temperatureK: state.temperatureK,
                    logPressure: state.logPressure,
                    compositionLogit: state.compositionLogit - steps[index]
                )
                upper = ArcState(
                    temperatureK: state.temperatureK,
                    logPressure: state.logPressure,
                    compositionLogit: state.compositionLogit + steps[index]
                )
            }
            lower = boundedArcState(lower, options: options)
            upper = boundedArcState(upper, options: options)
            let lowerResidual = try arcEquilibriumResidual(
                branch: branch,
                state: lower,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let upperResidual = try arcEquilibriumResidual(
                branch: branch,
                state: upper,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let denominator: Double
            switch index {
            case 0:
                denominator = upper.temperatureK - lower.temperatureK
            case 1:
                denominator = upper.logPressure - lower.logPressure
            default:
                denominator = upper.compositionLogit - lower.compositionLogit
            }
            guard denominator.isFinite, abs(denominator) > .ulpOfOne else {
                throw NativeSRKError.invalidComposition("Pseudo-arc finite-difference step collapsed.")
            }
            columns.append([
                (upperResidual[0] - lowerResidual[0]) / denominator,
                (upperResidual[1] - lowerResidual[1]) / denominator
            ])
        }
        return [
            [columns[0][0], columns[1][0], columns[2][0]],
            [columns[0][1], columns[1][1], columns[2][1]]
        ]
    }

    private func arcTangent(
        branch: NativeSRKEnvelopeBranch,
        state: ArcState,
        preferredDirection: [Double],
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [Double] {
        let jacobian = try arcJacobian(
            branch: branch,
            state: state,
            feedFractions: feedFractions,
            components: components,
            options: options
        )
        let tangent = cross(jacobian[0], jacobian[1])
        guard tangent.allSatisfy(\.isFinite), vectorNorm(tangent) > 1e-12 else {
            throw NativeSRKError.invalidComposition("Pseudo-arc tangent null space is singular.")
        }
        var scaled = normalizeArcDirection(tangent)
        if dot(scaled, preferredDirection) < 0 {
            scaled = scaled.map { -$0 }
        }
        return scaled
    }

    private func correctPseudoArcLength(
        branch: NativeSRKEnvelopeBranch,
        predictor: ArcState,
        tangent: [Double],
        current: ArcState,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) throws -> ArcState {
        var state = predictor
        var bestNorm = Double.infinity
        let targetArc = scaledArcDistance(from: current, to: predictor)
        for _ in 1...min(options.maximumIterationsPerSolve, 32) {
            if shouldCancel() { throw CancellationError() }
            let residual = try borderedArcResidual(
                branch: branch,
                state: state,
                predictor: predictor,
                tangent: tangent,
                targetArc: targetArc,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let residualNorm = vectorNorm(residual)
            bestNorm = min(bestNorm, residualNorm)
            if residualNorm <= options.relativeTolerance {
                return state
            }
            let jacobian = try borderedArcJacobian(
                branch: branch,
                state: state,
                predictor: predictor,
                tangent: tangent,
                targetArc: targetArc,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let step = try solveLinear3(jacobian, residual.map { -$0 })
            let boundedStep = [
                clamp(step[0], -max(1.0, options.maximumTemperatureStepK), max(1.0, options.maximumTemperatureStepK)),
                clamp(step[1], -log(1.8), log(1.8)),
                clamp(step[2], -1.5, 1.5)
            ]
            var damping = 1.0
            var accepted: ArcState?
            while damping >= 1.0 / 64.0 {
                if shouldCancel() { throw CancellationError() }
                let candidate = boundedArcState(
                    ArcState(
                        temperatureK: state.temperatureK + damping * boundedStep[0],
                        logPressure: state.logPressure + damping * boundedStep[1],
                        compositionLogit: state.compositionLogit + damping * boundedStep[2]
                    ),
                    options: options
                )
                do {
                    let candidateResidual = try borderedArcResidual(
                        branch: branch,
                        state: candidate,
                        predictor: predictor,
                        tangent: tangent,
                        targetArc: targetArc,
                        feedFractions: feedFractions,
                        components: components,
                        options: options
                    )
                    if vectorNorm(candidateResidual) < residualNorm {
                        accepted = candidate
                        break
                    }
                } catch {
                    damping /= 2
                    continue
                }
                damping /= 2
            }
            guard let accepted else {
                throw NativeSRKError.invalidComposition(
                    "Pseudo-arc bordered corrector line search failed; best residual norm \(bestNorm)."
                )
            }
            state = accepted
        }
        throw NativeSRKError.invalidComposition(
            "Pseudo-arc bordered corrector did not converge; best residual norm \(bestNorm)."
        )
    }

    private func borderedArcResidual(
        branch: NativeSRKEnvelopeBranch,
        state: ArcState,
        predictor: ArcState,
        tangent: [Double],
        targetArc: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [Double] {
        let equilibrium = try arcEquilibriumResidual(
            branch: branch,
            state: state,
            feedFractions: feedFractions,
            components: components,
            options: options
        )
        let delta = arcDelta(from: predictor, to: state)
        let arc = dot(delta, tangent) / max(targetArc, 1e-12)
        return [equilibrium[0], equilibrium[1], arc]
    }

    private func borderedArcJacobian(
        branch: NativeSRKEnvelopeBranch,
        state: ArcState,
        predictor: ArcState,
        tangent: [Double],
        targetArc: Double,
        feedFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions
    ) throws -> [[Double]] {
        let steps = [max(1e-3, state.temperatureK * 1e-6), 1e-4, 1e-4]
        var columns: [[Double]] = []
        for index in 0..<3 {
            let lower = boundedArcState(offset(state, index: index, delta: -steps[index]), options: options)
            let upper = boundedArcState(offset(state, index: index, delta: steps[index]), options: options)
            let lowerResidual = try borderedArcResidual(
                branch: branch,
                state: lower,
                predictor: predictor,
                tangent: tangent,
                targetArc: targetArc,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let upperResidual = try borderedArcResidual(
                branch: branch,
                state: upper,
                predictor: predictor,
                tangent: tangent,
                targetArc: targetArc,
                feedFractions: feedFractions,
                components: components,
                options: options
            )
            let denominator = coordinate(upper, index: index) - coordinate(lower, index: index)
            guard denominator.isFinite, abs(denominator) > .ulpOfOne else {
                throw NativeSRKError.invalidComposition("Pseudo-arc bordered Jacobian step collapsed.")
            }
            columns.append([
                (upperResidual[0] - lowerResidual[0]) / denominator,
                (upperResidual[1] - lowerResidual[1]) / denominator,
                (upperResidual[2] - lowerResidual[2]) / denominator
            ])
        }
        return [
            [columns[0][0], columns[1][0], columns[2][0]],
            [columns[0][1], columns[1][1], columns[2][1]],
            [columns[0][2], columns[1][2], columns[2][2]]
        ]
    }

    private func coupledOutcome(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        feedFractions: [Double],
        state: [Double],
        components: [ComponentID],
        iterations: Int,
        residualNorm: Double,
        stepNorm: Double,
        terminationReason: String
    ) throws -> SolveOutcome {
        let pressurePa = exp(state[0])
        let incipient = binaryFractions(fromLogit: state[1])
        let liquidFractions: [Double]
        let vaporFractions: [Double]
        switch branch {
        case .bubble:
            liquidFractions = feedFractions
            vaporFractions = incipient
        case .dew:
            liquidFractions = incipient
            vaporFractions = feedFractions
        }
        let stability = try? stabilityAssessment(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            composition: zip(components, feedFractions).map {
                NativeSRKMixtureFraction(component: $0.0, moleFraction: $0.1)
            }
        )
        let phaseDifference = maxRelativeDelta(liquidFractions, vaporFractions)
        let minimumTPD = min(
            stability?.liquidLikeTangentPlaneDistance ?? .infinity,
            stability?.vaporLikeTangentPlaneDistance ?? .infinity
        )
        let acceptsNearBoundary = incipient.allSatisfy { $0 > 1e-12 && $0 < 1 - 1e-12 }
            && phaseDifference > 0.25
            && minimumTPD < -1e-6
        guard incipient.allSatisfy({ $0 > 1e-8 && $0 < 1 - 1e-8 }) || acceptsNearBoundary else {
            throw NativeSRKError.invalidComposition(
                "\(branch.rawValue) solve reached the incipient composition boundary."
            )
        }
        guard phaseDifference > 1e-5 else {
            throw NativeSRKError.invalidComposition("\(branch.rawValue) solve collapsed to a trivial incipient phase.")
        }
        let liquid = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: liquidFractions,
            components: components,
            useLiquidRoot: true
        )
        let vapor = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: vaporFractions,
            components: components,
            useLiquidRoot: false
        )
        return SolveOutcome(
            pressurePa: pressurePa,
            iterations: iterations,
            liquidFractions: liquidFractions,
            vaporFractions: vaporFractions,
            finalResidualNorm: residualNorm,
            finalStepNorm: stepNorm,
            liquidRootCount: liquid.rootCount,
            vaporRootCount: vapor.rootCount,
            selectedLiquidRoot: liquid.selectedRoot,
            selectedVaporRoot: vapor.selectedRoot,
            stabilityAssessment: stability,
            terminationReason: terminationReason
        )
    }

    private func solvePureSaturation(
        temperatureK: Double,
        options: NativeSRKEnvelopeOptions,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        let component = ComponentID.carbonDioxide
        let parameter = parameters[component]!
        guard temperatureK < parameter.criticalTemperatureK else {
            throw NativeSRKError.invalidTemperature(temperatureK)
        }

        let lower = log(options.minimumPressurePa)
        let upper = log(min(parameter.criticalPressurePa * 0.999, options.maximumPressurePa))
        let samples = 80
        var previousLogP: Double?
        var previousValue: Double?
        var bracket: (Double, Double)?

        for sample in 0...samples {
            if shouldCancel() { throw CancellationError() }
            let currentLogP = lower + (upper - lower) * Double(sample) / Double(samples)
            let currentValue: Double
            do {
                currentValue = try pureSaturationResidual(
                    temperatureK: temperatureK,
                    pressurePa: exp(currentLogP),
                    component: component
                )
            } catch {
                continue
            }
            if let previousLogP, let previousValue,
               (previousValue == 0 || previousValue.sign != currentValue.sign) {
                bracket = (previousLogP, currentLogP)
                break
            }
            previousLogP = currentLogP
            previousValue = currentValue
        }

        guard var (low, high) = bracket else {
            throw NativeSRKError.invalidComposition("Pure saturation root was not bracketed.")
        }

        var iterations = 0
        for iteration in 1...options.maximumIterationsPerSolve {
            if shouldCancel() { throw CancellationError() }
            iterations = iteration
            let middle = 0.5 * (low + high)
            let lowValue = try pureSaturationResidual(temperatureK: temperatureK, pressurePa: exp(low), component: component)
            let middleValue = try pureSaturationResidual(temperatureK: temperatureK, pressurePa: exp(middle), component: component)
            if abs(middleValue) < options.relativeTolerance || abs(high - low) < options.relativeTolerance {
                let pressure = exp(middle)
                let liquid = try fugacityResult(
                    temperatureK: temperatureK,
                    pressurePa: pressure,
                    fractions: [1],
                    components: [component],
                    useLiquidRoot: true
                )
                let vapor = try fugacityResult(
                    temperatureK: temperatureK,
                    pressurePa: pressure,
                    fractions: [1],
                    components: [component],
                    useLiquidRoot: false
                )
                return SolveOutcome(
                    pressurePa: pressure,
                    iterations: iterations,
                    liquidFractions: [1],
                    vaporFractions: [1],
                    finalResidualNorm: abs(middleValue),
                    finalStepNorm: abs(high - low),
                    liquidRootCount: liquid.rootCount,
                    vaporRootCount: vapor.rootCount,
                    selectedLiquidRoot: liquid.selectedRoot,
                    selectedVaporRoot: vapor.selectedRoot,
                    stabilityAssessment: nil,
                    terminationReason: "pure fugacity equality converged"
                )
            }
            if lowValue.sign == middleValue.sign {
                low = middle
            } else {
                high = middle
            }
        }

        throw NativeSRKError.invalidComposition("Pure saturation solve did not converge within \(iterations) iterations.")
    }

    private func pureSaturationResidual(
        temperatureK: Double,
        pressurePa: Double,
        component: ComponentID
    ) throws -> Double {
        let liquid = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: [1],
            components: [component],
            useLiquidRoot: true
        )
        let vapor = try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: [1],
            components: [component],
            useLiquidRoot: false
        )
        guard liquid.rootCount >= 2, vapor.rootCount >= 2,
              abs(vapor.selectedRoot - liquid.selectedRoot) > 1e-10 else {
            throw NativeSRKError.invalidComposition("Pure saturation roots have coalesced into a single phase.")
        }
        return log(liquid.coefficients[0]) - log(vapor.coefficients[0])
    }

    private func fugacityCoefficients(
        temperatureK: Double,
        pressurePa: Double,
        fractions: [Double],
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> [Double] {
        try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: fractions,
            components: components,
            useLiquidRoot: useLiquidRoot
        ).coefficients
    }

    private func fugacityResult(
        temperatureK: Double,
        pressurePa: Double,
        fractions: [Double],
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> FugacityResult {
        try fugacityResult(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: fractions,
            components: components,
            useLiquidRoot: useLiquidRoot,
            selectedRootOverride: nil
        )
    }

    private func fugacityResult(
        temperatureK: Double,
        pressurePa: Double,
        fractions: [Double],
        components: [ComponentID],
        useLiquidRoot: Bool,
        selectedRootOverride: Double?
    ) throws -> FugacityResult {
        let mixture = try mixtureTerm(temperatureK: temperatureK, fractions: fractions, components: components)
        let a = mixture.a
        let b = mixture.b
        guard a.isFinite, a > 0, b.isFinite, b > 0 else {
            throw NativeSRKError.invalidComposition("Mixture EOS parameters are invalid.")
        }
        let gasConstant = Self.gasConstant
        let reducedA = a * pressurePa / (gasConstant * gasConstant * temperatureK * temperatureK)
        let reducedB = b * pressurePa / (gasConstant * temperatureK)
        guard reducedB > 0, reducedB < 1 else {
            throw NativeSRKError.invalidComposition("Reduced co-volume is outside the SRK domain.")
        }
        let roots = cubicRealRoots(
            a: -1,
            b: reducedA - reducedB - reducedB * reducedB,
            c: -reducedA * reducedB
        ).filter { $0.isFinite && $0 > reducedB }
        let selectedRoot = selectedRootOverride.flatMap { candidate in
            roots.min { abs($0 - candidate) < abs($1 - candidate) }
        }
        guard let z = selectedRoot ?? (useLiquidRoot ? roots.min() : roots.max()) else {
            throw NativeSRKError.invalidComposition("No physical SRK compressibility root.")
        }
        let logTerm = log((z + reducedB) / z)
        let zMinusB = z - reducedB
        guard zMinusB > 0 else {
            throw NativeSRKError.invalidComposition("SRK logarithm domain failure.")
        }

        let coefficients = mixture.components.enumerated().map { index, component in
            let attractionSum = mixture.components.enumerated().reduce(0) { partial, pair in
                partial + pair.element.fraction * mixture.aij[index][pair.offset]
            }
            let attractionRatio = 2 * attractionSum / a
            let coVolumeRatio = component.b / b
            let lnPhi = coVolumeRatio * (z - 1)
                - log(zMinusB)
                - (reducedA / reducedB) * (attractionRatio - coVolumeRatio) * logTerm
            return exp(lnPhi)
        }
        return FugacityResult(
            coefficients: coefficients,
            rootCount: roots.count,
            selectedRoot: z
        )
    }

    private func physicalCompressibilityRoots(
        temperatureK: Double,
        pressurePa: Double,
        fractions: [Double],
        components: [ComponentID]
    ) throws -> [Double] {
        let mixture = try mixtureTerm(temperatureK: temperatureK, fractions: fractions, components: components)
        let gasConstant = Self.gasConstant
        let reducedA = mixture.a * pressurePa / (gasConstant * gasConstant * temperatureK * temperatureK)
        let reducedB = mixture.b * pressurePa / (gasConstant * temperatureK)
        guard reducedB > 0, reducedB < 1 else {
            throw NativeSRKError.invalidComposition("Reduced co-volume is outside the SRK domain.")
        }
        return cubicRealRoots(
            a: -1,
            b: reducedA - reducedB - reducedB * reducedB,
            c: -reducedA * reducedB
        ).filter { $0.isFinite && $0 > reducedB }.sorted()
    }

    private func rootSelectionDiagnostic(
        temperatureK: Double,
        pressurePa: Double,
        liquidFractions: [Double],
        vaporFractions: [Double],
        components: [ComponentID]
    ) throws -> NativeSRKRootSelectionDiagnostic {
        let liquidRoots = try physicalCompressibilityRoots(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: liquidFractions,
            components: components
        )
        let vaporRoots = try physicalCompressibilityRoots(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: vaporFractions,
            components: components
        )
        guard let selectedLiquid = liquidRoots.min(),
              let selectedVapor = vaporRoots.max()
        else {
            throw NativeSRKError.invalidComposition("No admissible root pairing.")
        }
        let liquidDensity = pressurePa / (selectedLiquid * Self.gasConstant * temperatureK)
        let vaporDensity = pressurePa / (selectedVapor * Self.gasConstant * temperatureK)
        let rootSeparation = abs(selectedVapor - selectedLiquid)
        let densitySeparation = abs(liquidDensity - vaporDensity)
        let phaseDistance = maxRelativeDelta(liquidFractions, vaporFractions)
        let classification: String
        if rootSeparation <= 1e-8 || densitySeparation <= 1e-6 {
            classification = "coalesced-root critical proximity"
        } else if phaseDistance <= 1e-5 {
            classification = "trivial phase-composition collapse"
        } else if liquidRoots.count > 1 || vaporRoots.count > 1 {
            classification = "multiple admissible roots with conventional min/max identity preserved"
        } else {
            classification = "single admissible root per phase calculation"
        }
        return NativeSRKRootSelectionDiagnostic(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            liquidCompressibilityRoots: liquidRoots,
            vaporCompressibilityRoots: vaporRoots,
            selectedLiquidRoot: selectedLiquid,
            selectedVaporRoot: selectedVapor,
            rootSeparation: rootSeparation,
            densitySeparationMolesPerCubicMeter: densitySeparation,
            phaseCompositionDistance: phaseDistance,
            classification: classification
        )
    }

    private func minimizedTangentPlaneDistance(
        type: NativeSRKTPDTrialType,
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID]
    ) throws -> NativeSRKTPDMinimum {
        guard let best = try rankedTPDStationaryPoints(
            type: type,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: feedFractions,
            components: components,
            additionalTrialCompositions: []
        ).first else {
            throw NativeSRKError.invalidComposition("no bounded TPD trial converged")
        }
        return NativeSRKTPDMinimum(
            trialType: best.trialType,
            minimumTangentPlaneDistance: best.minimumTangentPlaneDistance,
            iterations: best.iterations,
            finalTrialComposition: best.finalTrialComposition,
            residualNorm: best.residualNorm,
            terminationReason: best.terminationReason
        )
    }

    private func rankedTPDStationaryPoints(
        type: NativeSRKTPDTrialType,
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        additionalTrialCompositions: [[Double]]
    ) throws -> [NativeSRKTPDStationaryPoint] {
        let feedPhi = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: feedFractions,
            components: components,
            useLiquidRoot: type == .liquidLike
        )
        let trials = tpdInitialTrials(
            type: type,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            feedFractions: feedFractions,
            components: components,
            additionalTrialCompositions: additionalTrialCompositions
        )
        var stationaryPoints: [NativeSRKTPDStationaryPoint] = []
        var failureReason = "no bounded TPD trial converged"

        for trial in trials {
            do {
                let minimum = try minimizeTangentPlaneDistance(
                    trial: trial,
                    feedFractions: feedFractions,
                    feedPhi: feedPhi,
                    temperatureK: temperatureK,
                    pressurePa: pressurePa,
                    components: components
                )
                let stationaryPoint = NativeSRKTPDStationaryPoint(
                    trialType: minimum.trialType,
                    minimumTangentPlaneDistance: minimum.minimumTangentPlaneDistance,
                    iterations: minimum.iterations,
                    finalTrialComposition: minimum.finalTrialComposition,
                    residualNorm: minimum.residualNorm,
                    terminationReason: minimum.terminationReason,
                    isTrivialFeedStationaryPoint: collapsedComposition(minimum.finalTrialComposition, feedFractions),
                    isBoundaryPinned: minimum.finalTrialComposition.contains {
                        $0 <= 1e-10 || $0 >= 1 - 1e-10
                    }
                )
                if !stationaryPoints.contains(where: {
                    maxRelativeDelta($0.finalTrialComposition, stationaryPoint.finalTrialComposition) < 1e-6
                        && abs($0.minimumTangentPlaneDistance - stationaryPoint.minimumTangentPlaneDistance) < 1e-8
                }) {
                    stationaryPoints.append(stationaryPoint)
                }
            } catch {
                failureReason = "\(error)"
            }
        }

        guard !stationaryPoints.isEmpty else {
            throw NativeSRKError.invalidComposition(failureReason)
        }
        return stationaryPoints.sorted { lhs, rhs in
            if lhs.minimumTangentPlaneDistance != rhs.minimumTangentPlaneDistance {
                return lhs.minimumTangentPlaneDistance < rhs.minimumTangentPlaneDistance
            }
            if lhs.residualNorm != rhs.residualNorm {
                return lhs.residualNorm < rhs.residualNorm
            }
            return lhs.finalTrialComposition.lexicographicallyPrecedes(rhs.finalTrialComposition)
        }
    }

    private func tpdInitialTrials(
        type: NativeSRKTPDTrialType,
        temperatureK: Double,
        pressurePa: Double,
        feedFractions: [Double],
        components: [ComponentID],
        additionalTrialCompositions: [[Double]] = []
    ) -> [TPDTrial] {
        let wilson = wilsonKValues(temperatureK: temperatureK, pressurePa: pressurePa, components: components)
        let wilsonSeed: [Double]
        switch type {
        case .liquidLike:
            wilsonSeed = normalized(zip(feedFractions, wilson).map { $0 / $1 })
        case .vaporLike:
            wilsonSeed = normalized(zip(feedFractions, wilson).map { $0 * $1 })
        }
        let seeds = [
            wilsonSeed,
            feedFractions,
            [0.999, 0.001],
            [0.99, 0.01],
            [0.90, 0.10],
            [0.75, 0.25],
            [0.50, 0.50],
            [0.25, 0.75],
            [0.10, 0.90],
            [0.01, 0.99],
            [0.001, 0.999]
        ] + additionalTrialCompositions
        return uniqueCompositions(seeds.map(boundedBinaryFractions)).map {
            TPDTrial(type: type, composition: $0)
        }
    }

    private func minimizeTangentPlaneDistance(
        trial: TPDTrial,
        feedFractions: [Double],
        feedPhi: [Double],
        temperatureK: Double,
        pressurePa: Double,
        components: [ComponentID]
    ) throws -> NativeSRKTPDMinimum {
        var state = logit(trial.composition[0])
        var composition = binaryFractions(fromLogit: state)
        var bestComposition = composition
        var bestValue = try tangentPlaneDistance(
            trialFractions: composition,
            feedFractions: feedFractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: trial.type == .liquidLike
        )
        var finalResidual = Double.infinity
        var finalIteration = 0
        var termination = "TPD minimization reached iteration limit"

        for iteration in 1...40 {
            finalIteration = iteration
            let gradient = try finiteDifferenceTPDGradient(
                state: state,
                feedFractions: feedFractions,
                feedPhi: feedPhi,
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                components: components,
                useLiquidRoot: trial.type == .liquidLike
            )
            finalResidual = abs(gradient)
            if finalResidual <= 1e-9 {
                termination = collapsedComposition(composition, feedFractions)
                    ? "TPD minimization reached trivial stationary composition"
                    : "TPD minimization converged"
                break
            }

            let curvature = try finiteDifferenceTPDCurvature(
                state: state,
                feedFractions: feedFractions,
                feedPhi: feedPhi,
                temperatureK: temperatureK,
                pressurePa: pressurePa,
                components: components,
                useLiquidRoot: trial.type == .liquidLike
            )
            guard curvature.isFinite, abs(curvature) > 1e-12 else {
                termination = "TPD minimization stopped at singular curvature"
                break
            }
            let step = clamp(-gradient / curvature, -2.0, 2.0)
            var damping = 1.0
            var accepted = false
            while damping >= 1.0 / 64.0 {
                let candidateState = clamp(state + damping * step, -30, 30)
                let candidateComposition = binaryFractions(fromLogit: candidateState)
                let candidateValue = try tangentPlaneDistance(
                    trialFractions: candidateComposition,
                    feedFractions: feedFractions,
                    feedPhi: feedPhi,
                    temperatureK: temperatureK,
                    pressurePa: pressurePa,
                    components: components,
                    useLiquidRoot: trial.type == .liquidLike
                )
                guard candidateValue.isFinite else {
                    damping /= 2
                    continue
                }
                if candidateValue <= bestValue || abs(candidateValue - bestValue) <= 1e-12 {
                    state = candidateState
                    composition = candidateComposition
                    bestValue = candidateValue
                    bestComposition = candidateComposition
                    accepted = true
                    break
                }
                damping /= 2
            }
            guard accepted else {
                termination = "TPD minimization line search failed"
                break
            }
        }

        return NativeSRKTPDMinimum(
            trialType: trial.type,
            minimumTangentPlaneDistance: bestValue,
            iterations: finalIteration,
            finalTrialComposition: bestComposition,
            residualNorm: finalResidual,
            terminationReason: termination
        )
    }

    private func finiteDifferenceTPDGradient(
        state: Double,
        feedFractions: [Double],
        feedPhi: [Double],
        temperatureK: Double,
        pressurePa: Double,
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> Double {
        let step = 1e-4
        let lower = clamp(state - step, -30, 30)
        let upper = clamp(state + step, -30, 30)
        let lowerValue = try tangentPlaneDistance(
            trialFractions: binaryFractions(fromLogit: lower),
            feedFractions: feedFractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: useLiquidRoot
        )
        let upperValue = try tangentPlaneDistance(
            trialFractions: binaryFractions(fromLogit: upper),
            feedFractions: feedFractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: useLiquidRoot
        )
        let denominator = upper - lower
        guard abs(denominator) > .ulpOfOne else {
            throw NativeSRKError.invalidComposition("TPD finite-difference step collapsed.")
        }
        return (upperValue - lowerValue) / denominator
    }

    private func finiteDifferenceTPDCurvature(
        state: Double,
        feedFractions: [Double],
        feedPhi: [Double],
        temperatureK: Double,
        pressurePa: Double,
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> Double {
        let step = 1e-4
        let lower = try finiteDifferenceTPDGradient(
            state: clamp(state - step, -30, 30),
            feedFractions: feedFractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: useLiquidRoot
        )
        let upper = try finiteDifferenceTPDGradient(
            state: clamp(state + step, -30, 30),
            feedFractions: feedFractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: useLiquidRoot
        )
        return (upper - lower) / (2 * step)
    }

    private func tangentPlaneDistance(
        trialFractions: [Double],
        feedFractions: [Double],
        feedPhi: [Double],
        temperatureK: Double,
        pressurePa: Double,
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> Double {
        let trialPhi = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: trialFractions,
            components: components,
            useLiquidRoot: useLiquidRoot
        )
        return zip(trialFractions.indices, trialFractions).reduce(0.0) { partial, pair in
            let index = pair.0
            let trial = max(pair.1, 1e-15)
            let feed = max(feedFractions[index], 1e-15)
            let value = log(trial) + log(trialPhi[index]) - log(feed) - log(feedPhi[index])
            return partial + trial * value
        }
    }

    private func mixtureTerm(
        temperatureK: Double,
        fractions: [Double],
        components: [ComponentID]
    ) throws -> MixtureTerm {
        let terms = try zip(components, fractions).map { component, fraction -> ComponentIDTerm in
            guard let parameter = parameters[component] else {
                throw NativeSRKError.unsupportedComponent(component)
            }
            let reducedTemperature = temperatureK / parameter.criticalTemperatureK
            let m = 0.480 + 1.574 * parameter.acentricFactor
                - 0.176 * parameter.acentricFactor * parameter.acentricFactor
            let alpha = pow(1 + m * (1 - sqrt(reducedTemperature)), 2)
            let gasConstant = Self.gasConstant
            let a = 0.42747 * gasConstant * gasConstant
                * parameter.criticalTemperatureK * parameter.criticalTemperatureK
                / parameter.criticalPressurePa
                * alpha
            let b = 0.08664 * gasConstant * parameter.criticalTemperatureK
                / parameter.criticalPressurePa
            return ComponentIDTerm(component: component, fraction: fraction, a: a, b: b)
        }

        var attractionMatrix = Array(
            repeating: Array(repeating: 0.0, count: terms.count),
            count: terms.count
        )
        var mixtureAttraction = 0.0
        for i in terms.indices {
            for j in terms.indices {
                let kij = binaryInteraction[Set([terms[i].component, terms[j].component])] ?? 0
                let attraction = sqrt(terms[i].a * terms[j].a) * (1 - kij)
                attractionMatrix[i][j] = attraction
                mixtureAttraction += terms[i].fraction * terms[j].fraction * attraction
            }
        }
        let mixtureCoVolume = terms.reduce(0) { $0 + $1.fraction * $1.b }
        return MixtureTerm(
            a: mixtureAttraction,
            b: mixtureCoVolume,
            aij: attractionMatrix,
            components: terms
        )
    }

    private func validatedComposition(
        _ composition: [NativeSRKMixtureFraction]
    ) throws -> [NativeSRKMixtureFraction] {
        guard !composition.isEmpty else {
            throw NativeSRKError.invalidComposition("Composition is empty.")
        }
        var seen = Set<ComponentID>()
        var sum = 0.0
        for entry in composition {
            guard parameters[entry.component] != nil else {
                throw NativeSRKError.unsupportedComponent(entry.component)
            }
            guard seen.insert(entry.component).inserted else {
                throw NativeSRKError.duplicateComponent(entry.component)
            }
            guard entry.moleFraction.isFinite, entry.moleFraction > 0 else {
                throw NativeSRKError.invalidComposition("Mole fractions must be finite and positive.")
            }
            sum += entry.moleFraction
        }
        guard abs(sum - 1) < 1e-10 else {
            throw NativeSRKError.invalidComposition("Composition must be normalized before SRK tracing.")
        }
        return composition
    }

    private func point(
        branch: NativeSRKEnvelopeBranch,
        temperatureK: Double,
        outcome: SolveOutcome,
        components: [ComponentID]
    ) -> NativeSRKEnvelopePoint {
        NativeSRKEnvelopePoint(
            branch: branch,
            temperatureK: temperatureK,
            pressurePa: outcome.pressurePa,
            iterations: outcome.iterations,
            status: .converged,
            finalResidualNorm: outcome.finalResidualNorm,
            finalStepNorm: outcome.finalStepNorm,
            liquidRootCount: outcome.liquidRootCount,
            vaporRootCount: outcome.vaporRootCount,
            selectedLiquidRoot: outcome.selectedLiquidRoot,
            selectedVaporRoot: outcome.selectedVaporRoot,
            stabilityAssessment: outcome.stabilityAssessment,
            terminationReason: outcome.terminationReason,
            liquidMoleFractions: dictionary(components: components, values: outcome.liquidFractions),
            vaporMoleFractions: dictionary(components: components, values: outcome.vaporFractions)
        )
    }

    private func wilsonBubblePressure(
        temperatureK: Double,
        fractions: [Double],
        components: [ComponentID]
    ) -> Double {
        zip(fractions, components).reduce(0) { partial, pair in
            let parameter = parameters[pair.1]!
            let pressure = parameter.criticalPressurePa
                * exp(5.373 * (1 + parameter.acentricFactor) * (1 - parameter.criticalTemperatureK / temperatureK))
            return partial + pair.0 * pressure
        }
    }

    private func wilsonKValues(
        temperatureK: Double,
        pressurePa: Double,
        components: [ComponentID]
    ) -> [Double] {
        components.map { component in
            let parameter = parameters[component]!
            return parameter.criticalPressurePa / pressurePa
                * exp(5.373 * (1 + parameter.acentricFactor) * (1 - parameter.criticalTemperatureK / temperatureK))
        }
    }

    private func wilsonDewPressure(
        temperatureK: Double,
        fractions: [Double],
        components: [ComponentID]
    ) -> Double {
        let denominator = zip(fractions, components).reduce(0) { partial, pair in
            let parameter = parameters[pair.1]!
            let pressure = parameter.criticalPressurePa
                * exp(5.373 * (1 + parameter.acentricFactor) * (1 - parameter.criticalTemperatureK / temperatureK))
            return partial + pair.0 / max(pressure, 1)
        }
        return 1 / max(denominator, 1e-12)
    }
}

private func safeguardedPressureUpdate(
    pressurePa: Double,
    residual: Double,
    fallbackScale: Double,
    options: NativeSRKEnvelopeOptions,
    residualAtPressure: (Double) throws -> Double
) throws -> Double {
    let delta = 1e-4
    let lowerPressure = clamp(
        pressurePa * exp(-delta),
        options.minimumPressurePa,
        options.maximumPressurePa
    )
    let upperPressure = clamp(
        pressurePa * exp(delta),
        options.minimumPressurePa,
        options.maximumPressurePa
    )
    var fallback = clamp(
        pressurePa * clamp(fallbackScale, 0.5, 2.0),
        options.minimumPressurePa,
        options.maximumPressurePa
    )
    if abs(upperPressure - lowerPressure) <= .ulpOfOne {
        return fallback
    }
    let lowerResidual = try residualAtPressure(lowerPressure)
    let upperResidual = try residualAtPressure(upperPressure)
    let derivative = (upperResidual - lowerResidual) / (log(upperPressure) - log(lowerPressure))
    guard derivative.isFinite, abs(derivative) > 1e-10 else {
        return fallback
    }
    let boundedStep = clamp(-residual / derivative, -log(2), log(2))
    let candidate = clamp(
        pressurePa * exp(boundedStep),
        options.minimumPressurePa,
        options.maximumPressurePa
    )
    if candidate.isFinite {
        fallback = candidate
    }
    return fallback
}

private func cubicRealRoots(a: Double, b: Double, c: Double) -> [Double] {
    let q = (3 * b - a * a) / 9
    let r = (9 * a * b - 27 * c - 2 * a * a * a) / 54
    let discriminant = q * q * q + r * r
    let offset = -a / 3

    if discriminant > 0 {
        let sqrtD = sqrt(discriminant)
        let s = signedCubeRoot(r + sqrtD)
        let t = signedCubeRoot(r - sqrtD)
        return [offset + s + t]
    }

    if abs(discriminant) < 1e-14 {
        let s = signedCubeRoot(r)
        return Array(Set([offset + 2 * s, offset - s])).sorted()
    }

    let theta = acos(r / sqrt(-q * q * q))
    let scale = 2 * sqrt(-q)
    return [
        offset + scale * cos(theta / 3),
        offset + scale * cos((theta + 2 * .pi) / 3),
        offset + scale * cos((theta + 4 * .pi) / 3)
    ].sorted()
}

private func signedCubeRoot(_ value: Double) -> Double {
    value >= 0 ? pow(value, 1.0 / 3.0) : -pow(-value, 1.0 / 3.0)
}

private func normalized(_ values: [Double]) -> [Double] {
    let sum = values.reduce(0, +)
    guard sum.isFinite, sum > 0 else { return values }
    return values.map { $0 / sum }
}

private func damped(new: [Double], old: [Double], factor: Double) -> [Double] {
    normalized(zip(new, old).map { factor * $0 + (1 - factor) * $1 })
}

private func maxRelativeDelta(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).map { abs($0 - $1) / max(abs($1), 1e-12) }.max() ?? 0
}

private func vectorNorm(_ values: [Double]) -> Double {
    sqrt(values.map { $0 * $0 }.reduce(0, +))
}

private func cross(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
    [
        lhs[1] * rhs[2] - lhs[2] * rhs[1],
        lhs[2] * rhs[0] - lhs[0] * rhs[2],
        lhs[0] * rhs[1] - lhs[1] * rhs[0]
    ]
}

private func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).map(*).reduce(0, +)
}

private func normalizeArcDirection(_ value: [Double]) -> [Double] {
    let scaled = [value[0] / 20, value[1], value[2] / 2]
    let norm = max(vectorNorm(scaled), 1e-12)
    return [value[0] / norm, value[1] / norm, value[2] / norm]
}

private func boundedState(_ state: [Double], options: NativeSRKEnvelopeOptions) -> [Double] {
    [
        clamp(state[0], log(options.minimumPressurePa), log(options.maximumPressurePa)),
        clamp(state[1], -30, 30)
    ]
}

private func boundedFlashState(_ state: [Double]) -> [Double] {
    [
        clamp(state[0], -20, 20),
        clamp(state[1], -20, 20),
        clamp(state[2], -20, 20)
    ]
}

private func flashSplit(feedFractions: [Double], state: [Double]) -> (
    liquid: [Double],
    vapor: [Double],
    vaporFraction: Double,
    rachfordRice: Double
) {
    let kValues = [exp(clamp(state[0], -20, 20)), exp(clamp(state[1], -20, 20))]
    let beta = 1 / (1 + exp(-clamp(state[2], -20, 20)))
    let denominators = kValues.map { max(1e-12, 1 + beta * ($0 - 1)) }
    let rawLiquid = zip(feedFractions, denominators).map { $0 / $1 }
    let liquid = boundedBinaryFractions(rawLiquid)
    let vapor = boundedBinaryFractions(zip(kValues, liquid).map(*))
    let rachfordRice = zip(feedFractions, kValues).reduce(0.0) {
        $0 + $1.0 * ($1.1 - 1) / max(1e-12, 1 + beta * ($1.1 - 1))
    }
    return (liquid, vapor, beta, rachfordRice)
}

private func boundedArcState(
    _ state: NativeSRKPhaseEnvelopeTracer.ArcState,
    options: NativeSRKEnvelopeOptions
) -> NativeSRKPhaseEnvelopeTracer.ArcState {
    NativeSRKPhaseEnvelopeTracer.ArcState(
        temperatureK: clamp(state.temperatureK, options.minimumTemperatureK, options.maximumTemperatureK),
        logPressure: clamp(state.logPressure, log(options.minimumPressurePa), log(options.maximumPressurePa)),
        compositionLogit: clamp(state.compositionLogit, -30, 30)
    )
}

private func arcDelta(
    from lhs: NativeSRKPhaseEnvelopeTracer.ArcState,
    to rhs: NativeSRKPhaseEnvelopeTracer.ArcState
) -> [Double] {
    [
        (rhs.temperatureK - lhs.temperatureK) / 20,
        rhs.logPressure - lhs.logPressure,
        (rhs.compositionLogit - lhs.compositionLogit) / 2
    ]
}

private func scaledArcDistance(
    from lhs: NativeSRKPhaseEnvelopeTracer.ArcState,
    to rhs: NativeSRKPhaseEnvelopeTracer.ArcState
) -> Double {
    vectorNorm(arcDelta(from: lhs, to: rhs))
}

private func offset(
    _ state: NativeSRKPhaseEnvelopeTracer.ArcState,
    index: Int,
    delta: Double
) -> NativeSRKPhaseEnvelopeTracer.ArcState {
    switch index {
    case 0:
        return NativeSRKPhaseEnvelopeTracer.ArcState(
            temperatureK: state.temperatureK + delta,
            logPressure: state.logPressure,
            compositionLogit: state.compositionLogit
        )
    case 1:
        return NativeSRKPhaseEnvelopeTracer.ArcState(
            temperatureK: state.temperatureK,
            logPressure: state.logPressure + delta,
            compositionLogit: state.compositionLogit
        )
    default:
        return NativeSRKPhaseEnvelopeTracer.ArcState(
            temperatureK: state.temperatureK,
            logPressure: state.logPressure,
            compositionLogit: state.compositionLogit + delta
        )
    }
}

private func coordinate(_ state: NativeSRKPhaseEnvelopeTracer.ArcState, index: Int) -> Double {
    switch index {
    case 0:
        return state.temperatureK
    case 1:
        return state.logPressure
    default:
        return state.compositionLogit
    }
}

private func solveLinear3(_ matrix: [[Double]], _ rhs: [Double]) throws -> [Double] {
    var augmented = [
        [matrix[0][0], matrix[0][1], matrix[0][2], rhs[0]],
        [matrix[1][0], matrix[1][1], matrix[1][2], rhs[1]],
        [matrix[2][0], matrix[2][1], matrix[2][2], rhs[2]]
    ]
    for pivot in 0..<3 {
        let pivotRow = (pivot..<3).max {
            abs(augmented[$0][pivot]) < abs(augmented[$1][pivot])
        }!
        augmented.swapAt(pivot, pivotRow)
        let pivotValue = augmented[pivot][pivot]
        guard pivotValue.isFinite, abs(pivotValue) > 1e-12 else {
            throw NativeSRKPhaseEnvelopeTracer.NativeSRKError.invalidComposition(
                "Pseudo-arc bordered system is singular or ill-conditioned."
            )
        }
        for column in pivot...3 {
            augmented[pivot][column] /= pivotValue
        }
        for row in 0..<3 where row != pivot {
            let factor = augmented[row][pivot]
            for column in pivot...3 {
                augmented[row][column] -= factor * augmented[pivot][column]
            }
        }
    }
    let solution = [augmented[0][3], augmented[1][3], augmented[2][3]]
    guard solution.allSatisfy(\.isFinite) else {
        throw NativeSRKPhaseEnvelopeTracer.NativeSRKError.invalidComposition(
            "Pseudo-arc bordered linear solve produced a non-finite step."
        )
    }
    return solution
}

private func binaryFractions(fromLogit value: Double) -> [Double] {
    let first = 1 / (1 + exp(-clamp(value, -30, 30)))
    return boundedBinaryFractions([first, 1 - first])
}

private func boundedBinaryFractions(_ values: [Double]) -> [Double] {
    guard values.count == 2 else { return values }
    let first = clamp(values[0], 1e-12, 1 - 1e-12)
    return normalized([first, 1 - first])
}

private func uniqueBounded(_ values: [Double], lower: Double, upper: Double) -> [Double] {
    var result: [Double] = []
    for value in values {
        guard value.isFinite else { continue }
        let bounded = clamp(value, lower, upper)
        if !result.contains(where: { abs(log($0) - log(bounded)) < 1e-8 }) {
            result.append(bounded)
        }
    }
    return result
}

private func uniqueCompositions(_ values: [[Double]]) -> [[Double]] {
    var result: [[Double]] = []
    for value in values {
        let bounded = boundedBinaryFractions(value)
        if !result.contains(where: { maxRelativeDelta($0, bounded) < 1e-8 }) {
            result.append(bounded)
        }
    }
    return result
}

private func branchNeighborhoodSeeds(feedFractions: [Double], incipient: [Double]) -> [[Double]] {
    let first = incipient[0]
    let perturbations = [-0.25, -0.10, -0.03, 0.03, 0.10, 0.25].map {
        boundedBinaryFractions([first + $0, 1 - first - $0])
    }
    let instabilityDirection = incipient[0] >= feedFractions[0] ? 1.0 : -1.0
    let directed = [0.02, 0.05, 0.10].map {
        boundedBinaryFractions([first + instabilityDirection * $0, 1 - first - instabilityDirection * $0])
    }
    return uniqueCompositions([
        incipient,
        feedFractions,
        boundedBinaryFractions([max(1e-6, first), min(1 - 1e-6, 1 - first)]),
        [1e-6, 1 - 1e-6],
        [1 - 1e-6, 1e-6]
    ] + perturbations + directed)
}

private func collapsedComposition(_ lhs: [Double], _ rhs: [Double]) -> Bool {
    maxRelativeDelta(lhs, rhs) <= 1e-5
}

private func logit(_ value: Double) -> Double {
    let bounded = clamp(value, 1e-12, 1 - 1e-12)
    return log(bounded / (1 - bounded))
}

private func dictionary(components: [ComponentID], values: [Double]) -> [ComponentID: Double] {
    Dictionary(uniqueKeysWithValues: zip(components, values))
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

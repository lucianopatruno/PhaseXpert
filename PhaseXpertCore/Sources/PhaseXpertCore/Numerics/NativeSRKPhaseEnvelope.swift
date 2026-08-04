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
}

public struct NativeSRKProvenance: Sendable, Equatable {
    public let modelIdentifier = "phasexpert-native-srk-prototype"
    public let eos = "Soave-Redlich-Kwong"
    public let alphaFunction = "Standard Soave alpha"
    public let mixingRule = "Classical van der Waals one-fluid quadratic mixing"
    public let stabilityTest =
        "Wilson-seeded tangent-plane-distance screen using SRK fugacity coefficients"
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
        let feedPhi = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: fractions,
            components: components,
            useLiquidRoot: false
        )
        let wilson = wilsonKValues(temperatureK: temperatureK, pressurePa: pressurePa, components: components)
        let vaporLike = normalized(zip(fractions, wilson).map { $0 * $1 })
        let liquidLike = normalized(zip(fractions, wilson).map { $0 / $1 })
        let vaporTPD = try tangentPlaneDistance(
            trialFractions: vaporLike,
            feedFractions: fractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: false
        )
        let liquidTPD = try tangentPlaneDistance(
            trialFractions: liquidLike,
            feedFractions: fractions,
            feedPhi: feedPhi,
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            components: components,
            useLiquidRoot: true
        )
        return NativeSRKStabilityAssessment(
            isStable: min(vaporTPD, liquidTPD) >= -1e-8,
            liquidLikeTangentPlaneDistance: liquidTPD,
            vaporLikeTangentPlaneDistance: vaporTPD
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

        while temperature <= min(options.maximumTemperatureK, criticalTemperature * 0.999) {
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
                if failures >= options.maximumConsecutiveFailures {
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
                points.append(point(
                    branch: branch,
                    temperatureK: temperature,
                    outcome: outcome,
                    components: components
                ))
                pressureGuess = outcome.pressurePa
                failures = 0
                step = min(options.maximumTemperatureStepK, step * 1.15)
                temperature += step
            } catch {
                gaps.append(.init(branch: branch, temperatureK: temperature, reason: "\(error)"))
                failures += 1
                if failures >= options.maximumConsecutiveFailures {
                    return
                }
                step = max(options.minimumTemperatureStepK, step / 2)
                temperature += step
            }
        }
    }

    private func solveBubble(
        temperatureK: Double,
        liquidFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialPressurePa: Double?,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        var pressure = clamp(
            initialPressurePa ?? wilsonBubblePressure(temperatureK: temperatureK, fractions: liquidFractions, components: components),
            options.minimumPressurePa,
            options.maximumPressurePa
        )
        var vaporFractions = liquidFractions
        var iterations = 0

        for iteration in 1...options.maximumIterationsPerSolve {
            if shouldCancel() { throw CancellationError() }
            iterations = iteration
            let liquidPhi = try fugacityCoefficients(
                temperatureK: temperatureK,
                pressurePa: pressure,
                fractions: liquidFractions,
                components: components,
                useLiquidRoot: true
            )
            let vaporPhi = try fugacityCoefficients(
                temperatureK: temperatureK,
                pressurePa: pressure,
                fractions: vaporFractions,
                components: components,
                useLiquidRoot: false
            )
            let kValues = zip(liquidPhi, vaporPhi).map { max(1e-12, min(1e12, $0 / $1)) }
            let sum = zip(liquidFractions, kValues).map(*).reduce(0, +)
            guard sum.isFinite, sum > 0 else { throw NativeSRKError.invalidComposition("Bubble residual is non-finite.") }
            let updatedVapor = normalized(zip(liquidFractions, kValues).map { $0 * $1 })
            let residual = log(sum)
            let nextPressure = try safeguardedPressureUpdate(
                pressurePa: pressure,
                residual: residual,
                fallbackScale: sum,
                options: options
            ) { trialPressure in
                let trialLiquidPhi = try fugacityCoefficients(
                    temperatureK: temperatureK,
                    pressurePa: trialPressure,
                    fractions: liquidFractions,
                    components: components,
                    useLiquidRoot: true
                )
                let trialVaporPhi = try fugacityCoefficients(
                    temperatureK: temperatureK,
                    pressurePa: trialPressure,
                    fractions: vaporFractions,
                    components: components,
                    useLiquidRoot: false
                )
                let trialK = zip(trialLiquidPhi, trialVaporPhi).map { max(1e-12, min(1e12, $0 / $1)) }
                return log(zip(liquidFractions, trialK).map { $0 * $1 }.reduce(0, +))
            }
            if abs(sum - 1) <= options.relativeTolerance, maxRelativeDelta(updatedVapor, vaporFractions) < 1e-7 {
                return SolveOutcome(
                    pressurePa: pressure,
                    iterations: iterations,
                    liquidFractions: liquidFractions,
                    vaporFractions: updatedVapor
                )
            }
            vaporFractions = damped(new: updatedVapor, old: vaporFractions, factor: 0.5)
            pressure = 0.65 * nextPressure + 0.35 * pressure
        }

        throw NativeSRKError.invalidComposition("Bubble solve did not converge within \(iterations) iterations.")
    }

    private func solveDew(
        temperatureK: Double,
        vaporFractions: [Double],
        components: [ComponentID],
        options: NativeSRKEnvelopeOptions,
        initialPressurePa: Double?,
        shouldCancel: @Sendable () -> Bool
    ) throws -> SolveOutcome {
        var pressure = clamp(
            initialPressurePa ?? wilsonDewPressure(temperatureK: temperatureK, fractions: vaporFractions, components: components),
            options.minimumPressurePa,
            options.maximumPressurePa
        )
        var liquidFractions = vaporFractions
        var iterations = 0

        for iteration in 1...options.maximumIterationsPerSolve {
            if shouldCancel() { throw CancellationError() }
            iterations = iteration
            let liquidPhi = try fugacityCoefficients(
                temperatureK: temperatureK,
                pressurePa: pressure,
                fractions: liquidFractions,
                components: components,
                useLiquidRoot: true
            )
            let vaporPhi = try fugacityCoefficients(
                temperatureK: temperatureK,
                pressurePa: pressure,
                fractions: vaporFractions,
                components: components,
                useLiquidRoot: false
            )
            let kValues = zip(liquidPhi, vaporPhi).map { max(1e-12, min(1e12, $0 / $1)) }
            let sum = zip(vaporFractions, kValues).map { $0 / $1 }.reduce(0, +)
            guard sum.isFinite, sum > 0 else { throw NativeSRKError.invalidComposition("Dew residual is non-finite.") }
            let updatedLiquid = normalized(zip(vaporFractions, kValues).map { $0 / $1 })
            let residual = log(sum)
            let nextPressure = try safeguardedPressureUpdate(
                pressurePa: pressure,
                residual: residual,
                fallbackScale: 1 / sum,
                options: options
            ) { trialPressure in
                let trialLiquidPhi = try fugacityCoefficients(
                    temperatureK: temperatureK,
                    pressurePa: trialPressure,
                    fractions: liquidFractions,
                    components: components,
                    useLiquidRoot: true
                )
                let trialVaporPhi = try fugacityCoefficients(
                    temperatureK: temperatureK,
                    pressurePa: trialPressure,
                    fractions: vaporFractions,
                    components: components,
                    useLiquidRoot: false
                )
                let trialK = zip(trialLiquidPhi, trialVaporPhi).map { max(1e-12, min(1e12, $0 / $1)) }
                return log(zip(vaporFractions, trialK).map { $0 / $1 }.reduce(0, +))
            }
            if abs(sum - 1) <= options.relativeTolerance, maxRelativeDelta(updatedLiquid, liquidFractions) < 1e-7 {
                return SolveOutcome(
                    pressurePa: pressure,
                    iterations: iterations,
                    liquidFractions: updatedLiquid,
                    vaporFractions: vaporFractions
                )
            }
            liquidFractions = damped(new: updatedLiquid, old: liquidFractions, factor: 0.5)
            pressure = 0.65 * nextPressure + 0.35 * pressure
        }

        throw NativeSRKError.invalidComposition("Dew solve did not converge within \(iterations) iterations.")
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
        var previousLogP = lower
        var previousValue = try pureSaturationResidual(
            temperatureK: temperatureK,
            pressurePa: exp(previousLogP),
            component: component
        )
        var bracket: (Double, Double)?

        for sample in 1...samples {
            if shouldCancel() { throw CancellationError() }
            let currentLogP = lower + (upper - lower) * Double(sample) / Double(samples)
            let currentValue = try pureSaturationResidual(
                temperatureK: temperatureK,
                pressurePa: exp(currentLogP),
                component: component
            )
            if previousValue == 0 || previousValue.sign != currentValue.sign {
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
            let lowValue = try pureSaturationResidual(
                temperatureK: temperatureK,
                pressurePa: exp(low),
                component: component
            )
            let middleValue = try pureSaturationResidual(
                temperatureK: temperatureK,
                pressurePa: exp(middle),
                component: component
            )
            if abs(middleValue) < options.relativeTolerance || abs(high - low) < options.relativeTolerance {
                return SolveOutcome(
                    pressurePa: exp(middle),
                    iterations: iterations,
                    liquidFractions: [1],
                    vaporFractions: [1]
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
        let liquid = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: [1],
            components: [component],
            useLiquidRoot: true
        )[0]
        let vapor = try fugacityCoefficients(
            temperatureK: temperatureK,
            pressurePa: pressurePa,
            fractions: [1],
            components: [component],
            useLiquidRoot: false
        )[0]
        return log(liquid) - log(vapor)
    }

    private func fugacityCoefficients(
        temperatureK: Double,
        pressurePa: Double,
        fractions: [Double],
        components: [ComponentID],
        useLiquidRoot: Bool
    ) throws -> [Double] {
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
        guard let z = useLiquidRoot ? roots.min() : roots.max() else {
            throw NativeSRKError.invalidComposition("No physical SRK compressibility root.")
        }
        let logTerm = log((z + reducedB) / z)
        let zMinusB = z - reducedB
        guard zMinusB > 0 else {
            throw NativeSRKError.invalidComposition("SRK logarithm domain failure.")
        }

        return mixture.components.enumerated().map { index, component in
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

private func dictionary(components: [ComponentID], values: [Double]) -> [ComponentID: Double] {
    Dictionary(uniqueKeysWithValues: zip(components, values))
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

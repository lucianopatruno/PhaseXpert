import Foundation

public enum PhaseMapResolution: Int, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case five = 5
    case ten = 10
    case twenty = 20

    public var id: Int { rawValue }

    public var gridPointCount: Int {
        rawValue * rawValue
    }

    public var expectedEvaluationCount: Int {
        gridPointCount
    }
}

public struct PhaseMapRange: Codable, Equatable, Sendable {
    public let pressureMinimumPa: Double
    public let pressureMaximumPa: Double
    public let temperatureMinimumK: Double
    public let temperatureMaximumK: Double

    public init(
        pressureMinimumPa: Double,
        pressureMaximumPa: Double,
        temperatureMinimumK: Double,
        temperatureMaximumK: Double
    ) {
        self.pressureMinimumPa = pressureMinimumPa
        self.pressureMaximumPa = pressureMaximumPa
        self.temperatureMinimumK = temperatureMinimumK
        self.temperatureMaximumK = temperatureMaximumK
    }

    public static func automatic(
        pressurePa: Double,
        temperatureK: Double
    ) -> PhaseMapRange {
        PhaseMapRange(
            pressureMinimumPa: pressurePa * 0.5,
            pressureMaximumPa: pressurePa * 1.5,
            temperatureMinimumK: temperatureK - 25,
            temperatureMaximumK: temperatureK + 25
        )
    }
}

public enum PhaseMapValidationCode: String, Codable, Equatable, Sendable {
    case invalidPressureRange
    case invalidTemperatureRange
    case operatingPointOutsideRange
    case invalidComposition
    case providerUnavailable
}

public struct PhaseMapValidationIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(code.rawValue)-\(message)" }

    public let code: PhaseMapValidationCode
    public let message: String

    public init(code: PhaseMapValidationCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum PhaseMapClassification: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case gas
    case liquid
    case multiphase
    case solid
    case dense
    case supercritical
    case unknown
    case failed

    public var id: String { rawValue }
}

public struct PhaseMapClassificationResult: Codable, Equatable, Sendable {
    public let classification: PhaseMapClassification
    public let displayName: String
    public let isSupported: Bool
    public let detail: String?

    public init(
        classification: PhaseMapClassification,
        displayName: String,
        isSupported: Bool,
        detail: String? = nil
    ) {
        self.classification = classification
        self.displayName = displayName
        self.isSupported = isSupported
        self.detail = detail
    }
}

public enum PhaseMapClassificationAdapter {
    public static func map(_ region: PhaseRegion) -> PhaseMapClassificationResult {
        switch region {
        case .gas:
            PhaseMapClassificationResult(classification: .gas, displayName: "Gas", isSupported: true)
        case .liquid:
            PhaseMapClassificationResult(classification: .liquid, displayName: "Liquid", isSupported: true)
        case .twoPhase:
            PhaseMapClassificationResult(classification: .multiphase, displayName: "Multiphase", isSupported: true)
        case .solid:
            PhaseMapClassificationResult(classification: .solid, displayName: "Solid", isSupported: true)
        case .dense:
            PhaseMapClassificationResult(classification: .dense, displayName: "Dense", isSupported: true)
        case .supercritical:
            PhaseMapClassificationResult(classification: .supercritical, displayName: "Supercritical", isSupported: true)
        case .unknown:
            PhaseMapClassificationResult(
                classification: .unknown,
                displayName: "Unknown",
                isSupported: false,
                detail: "The provider returned an unknown phase classification."
            )
        case .unavailable:
            PhaseMapClassificationResult(
                classification: .unknown,
                displayName: "Unavailable",
                isSupported: false,
                detail: "The provider did not return a supported phase classification."
            )
        }
    }
}

public struct PhaseMapGridPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(temperatureK)-\(pressurePa)-\(isOperatingPoint)" }

    public let pressurePa: Double
    public let temperatureK: Double
    public let isOperatingPoint: Bool

    public init(pressurePa: Double, temperatureK: Double, isOperatingPoint: Bool) {
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.isOperatingPoint = isOperatingPoint
    }
}

public struct PhaseMapEvaluation: Codable, Equatable, Sendable, Identifiable {
    public var id: String { point.id }

    public let point: PhaseMapGridPoint
    public let classification: PhaseMapClassificationResult
    public let solver: SolverMetadata?
    public let failureReason: String?

    public init(
        point: PhaseMapGridPoint,
        classification: PhaseMapClassificationResult,
        solver: SolverMetadata?,
        failureReason: String? = nil
    ) {
        self.point = point
        self.classification = classification
        self.solver = solver
        self.failureReason = failureReason
    }
}

public struct PhaseMapRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let modelID: String
    public let pressurePa: Double
    public let temperatureK: Double
    public let composition: [MixtureComponent]
    public let range: PhaseMapRange
    public let resolution: PhaseMapResolution
    public let clientVersion: String

    public init(
        requestID: UUID = UUID(),
        modelID: String,
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        range: PhaseMapRange,
        resolution: PhaseMapResolution,
        clientVersion: String
    ) {
        self.requestID = requestID
        self.modelID = modelID
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.composition = composition
        self.range = range
        self.resolution = resolution
        self.clientVersion = clientVersion
    }
}

public struct PhaseMapProgress: Codable, Equatable, Sendable {
    public let completedCount: Int
    public let totalCount: Int

    public init(completedCount: Int, totalCount: Int) {
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public struct PhaseMapResult: Codable, Equatable, Sendable {
    public let request: PhaseMapRequest
    public let model: ModelDescriptor
    public let calculatedAt: Date
    public let evaluations: [PhaseMapEvaluation]
    public let warnings: [String]

    public init(
        request: PhaseMapRequest,
        model: ModelDescriptor,
        calculatedAt: Date = Date(),
        evaluations: [PhaseMapEvaluation],
        warnings: [String]
    ) {
        self.request = request
        self.model = model
        self.calculatedAt = calculatedAt
        self.evaluations = evaluations
        self.warnings = warnings
    }

    public var successfulCount: Int {
        evaluations.filter { $0.failureReason == nil && $0.solver?.converged != false }.count
    }

    public var failedCount: Int {
        evaluations.filter { $0.failureReason != nil }.count
    }

    public var nonConvergedCount: Int {
        evaluations.filter { $0.failureReason == nil && $0.solver?.converged == false }.count
    }

    public var operatingPoint: PhaseMapEvaluation? {
        evaluations.first { $0.point.isOperatingPoint }
    }
}

public protocol PhaseMapProvidingModelProvider: ThermodynamicModelProvider {
    func phaseMap(
        _ request: PhaseMapRequest,
        progress: (@Sendable (PhaseMapProgress) async -> Void)?
    ) async throws -> PhaseMapResult
}

public enum PhaseMapGridBuilder {
    public static func validationIssues(for request: PhaseMapRequest) -> [PhaseMapValidationIssue] {
        var issues: [PhaseMapValidationIssue] = []
        if !request.range.pressureMinimumPa.isFinite
            || !request.range.pressureMaximumPa.isFinite
            || request.range.pressureMinimumPa <= 0
            || request.range.pressureMaximumPa <= 0
            || request.range.pressureMinimumPa >= request.range.pressureMaximumPa {
            issues.append(.init(
                code: .invalidPressureRange,
                message: "Pressure range must use positive absolute values with minimum below maximum."
            ))
        }
        if !request.range.temperatureMinimumK.isFinite
            || !request.range.temperatureMaximumK.isFinite
            || request.range.temperatureMinimumK <= 0
            || request.range.temperatureMaximumK <= 0
            || request.range.temperatureMinimumK >= request.range.temperatureMaximumK {
            issues.append(.init(
                code: .invalidTemperatureRange,
                message: "Temperature range must use finite absolute values with minimum below maximum."
            ))
        }
        if !request.pressurePa.isFinite
            || !request.temperatureK.isFinite
            || request.pressurePa <= 0
            || request.temperatureK <= 0
            || request.pressurePa <= request.range.pressureMinimumPa
            || request.pressurePa >= request.range.pressureMaximumPa
            || request.temperatureK <= request.range.temperatureMinimumK
            || request.temperatureK >= request.range.temperatureMaximumK {
            issues.append(.init(
                code: .operatingPointOutsideRange,
                message: "The operating point must lie strictly inside the selected pressure and temperature ranges."
            ))
        }
        if PhaseDiagramEligibility.evaluate(composition: request.composition) != .multicomponent {
            issues.append(.init(
                code: .invalidComposition,
                message: "Phase Map is available only for multicomponent compositions."
            ))
        }
        return issues
    }

    public static func points(for request: PhaseMapRequest) throws -> [PhaseMapGridPoint] {
        let issues = validationIssues(for: request)
        guard issues.isEmpty else {
            throw ProviderError.invalidRequest(issues.map(\.message).joined(separator: " "))
        }

        let pressureAxis = axis(
            minimum: request.range.pressureMinimumPa,
            maximum: request.range.pressureMaximumPa,
            count: request.resolution.rawValue,
            operatingValue: request.pressurePa
        )
        let temperatureAxis = axis(
            minimum: request.range.temperatureMinimumK,
            maximum: request.range.temperatureMaximumK,
            count: request.resolution.rawValue,
            operatingValue: request.temperatureK
        )

        var points: [PhaseMapGridPoint] = []
        points.reserveCapacity(request.resolution.gridPointCount + 1)
        for temperature in temperatureAxis {
            for pressure in pressureAxis {
                let isOperatingPoint = coordinatesMatch(
                    pressure,
                    request.pressurePa,
                    scale: max(abs(request.range.pressureMinimumPa), abs(request.range.pressureMaximumPa))
                ) && coordinatesMatch(
                    temperature,
                    request.temperatureK,
                    scale: max(abs(request.range.temperatureMinimumK), abs(request.range.temperatureMaximumK))
                )
                points.append(.init(
                    pressurePa: isOperatingPoint ? request.pressurePa : pressure,
                    temperatureK: isOperatingPoint ? request.temperatureK : temperature,
                    isOperatingPoint: isOperatingPoint
                ))
            }
        }
        if !points.contains(where: \.isOperatingPoint) {
            points.append(.init(
                pressurePa: request.pressurePa,
                temperatureK: request.temperatureK,
                isOperatingPoint: true
            ))
        }

        try validateConstructedPoints(points)
        return points
    }

    private static func validateConstructedPoints(
        _ points: [PhaseMapGridPoint]
    ) throws {
        var seenCoordinates: Set<CoordinateKey> = []
        var operatingPointCount = 0
        for point in points {
            if point.isOperatingPoint {
                operatingPointCount += 1
            }
            let key = CoordinateKey(pressurePa: point.pressurePa, temperatureK: point.temperatureK)
            guard seenCoordinates.insert(key).inserted else {
                throw ProviderError.invalidRequest(
                    "Phase Map grid construction produced duplicate pressure-temperature coordinates."
                )
            }
        }
        guard operatingPointCount == 1 else {
            throw ProviderError.invalidRequest(
                "Phase Map grid construction must include exactly one operating point."
            )
        }
    }

    private static func axis(
        minimum: Double,
        maximum: Double,
        count: Int,
        operatingValue: Double
    ) -> [Double] {
        guard count > 1 else { return [operatingValue] }
        let step = (maximum - minimum) / Double(count - 1)
        return (0..<count).map { index in
            if index == 0 { return minimum }
            if index == count - 1 { return maximum }
            return minimum + Double(index) * step
        }
    }

    private static func coordinatesMatch(_ lhs: Double, _ rhs: Double, scale: Double) -> Bool {
        abs(lhs - rhs) <= max(scale, 1) * 1e-12
    }
}

private struct CoordinateKey: Hashable {
    let pressurePa: Double
    let temperatureK: Double
}

public struct PhaseMapRunner: Sendable {
    private let provider: any ThermodynamicModelProvider

    public init(provider: any ThermodynamicModelProvider) {
        self.provider = provider
    }

    public func run(
        _ request: PhaseMapRequest,
        progress: (@Sendable (PhaseMapProgress) async -> Void)? = nil
    ) async throws -> PhaseMapResult {
        if let phaseMapProvider = provider as? any PhaseMapProvidingModelProvider {
            return try await phaseMapProvider.phaseMap(request, progress: progress)
        }
        guard provider.descriptor.availability != .unavailable else {
            throw ProviderError.modelUnavailable("The selected provider is not available.")
        }
        let points = try PhaseMapGridBuilder.points(for: request)
        var evaluations: [PhaseMapEvaluation] = []
        evaluations.reserveCapacity(points.count)

        for point in points {
            try Task.checkCancellation()
            do {
                let response = try await provider.calculate(CalculationRequest(
                    modelID: request.modelID,
                    pressurePa: point.pressurePa,
                    temperatureK: point.temperatureK,
                    composition: request.composition,
                    requestedProperties: [.density],
                    clientVersion: request.clientVersion
                ))
                let classification = PhaseMapClassificationAdapter.map(response.phase)
                evaluations.append(PhaseMapEvaluation(
                    point: point,
                    classification: response.solver.converged
                        ? classification
                        : PhaseMapClassificationResult(
                            classification: .failed,
                            displayName: "Non-converged",
                            isSupported: false,
                            detail: "The provider did not converge at this point."
                        ),
                    solver: response.solver,
                    failureReason: nil
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                evaluations.append(PhaseMapEvaluation(
                    point: point,
                    classification: PhaseMapClassificationResult(
                        classification: .failed,
                        displayName: "Failed",
                        isSupported: false,
                        detail: userMessage(for: error)
                    ),
                    solver: nil,
                    failureReason: userMessage(for: error)
                ))
            }
            await progress?(PhaseMapProgress(completedCount: evaluations.count, totalCount: points.count))
        }

        return PhaseMapResult(
            request: request,
            model: provider.descriptor,
            evaluations: evaluations,
            warnings: [
                "Phase Map classifies discrete provider flash points only; it is not a phase envelope and does not trace bubble or dew boundaries.",
                "Narrow phase regions can be missed between evaluated grid points."
            ]
        )
    }

    private func userMessage(for error: Error) -> String {
        guard let providerError = error as? ProviderError else {
            return "The provider failed at this point."
        }
        switch providerError {
        case let .modelUnavailable(message),
             let .invalidRequest(message),
             let .malformedResponse(message):
            return message
        case let .unsupportedComponent(component):
            return "\(component.symbol) is not supported by the selected provider."
        case .timeout:
            return "The provider timed out at this point."
        case .cancelled:
            return "The point evaluation was cancelled."
        }
    }
}

import Foundation

/// Independent variable used for a provider-backed property sweep.
public enum PropertySweepAxis: String, CaseIterable, Codable, Equatable, Sendable {
    case pressure
    case temperature
}

/// A bounded series of thermodynamic states evaluated at one fixed composition.
///
/// All values use the same internal SI convention as ``CalculationRequest``.
public struct PropertySweepRequest: Codable, Equatable, Sendable {
    public static let minimumPointCount = 2
    public static let maximumPointCount = 51

    public let id: UUID
    public let baseRequest: CalculationRequest
    public let axis: PropertySweepAxis
    public let startValueSI: Double
    public let endValueSI: Double
    public let pointCount: Int
    public let property: PropertyID

    public init(
        id: UUID = UUID(),
        baseRequest: CalculationRequest,
        axis: PropertySweepAxis,
        startValueSI: Double,
        endValueSI: Double,
        pointCount: Int,
        property: PropertyID
    ) {
        self.id = id
        self.baseRequest = baseRequest
        self.axis = axis
        self.startValueSI = startValueSI
        self.endValueSI = endValueSI
        self.pointCount = pointCount
        self.property = property
    }
}

/// One provider response in a sweep. Failures remain explicit and never receive an
/// interpolated or placeholder value.
public struct PropertySweepSample: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let index: Int
    public let pressurePa: Double
    public let temperatureK: Double
    public let response: CalculationResponse?
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        pressurePa: Double,
        temperatureK: Double,
        response: CalculationResponse?,
        errorMessage: String?
    ) {
        self.id = id
        self.index = index
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.response = response
        self.errorMessage = errorMessage
    }

    public func value(for property: PropertyID) -> PropertyValue? {
        response?.properties.first { $0.property == property }
    }
}

public struct PropertySweepResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { request.id }
    public let request: PropertySweepRequest
    public let generatedAt: Date
    public let durationMilliseconds: Double
    public let samples: [PropertySweepSample]

    public init(
        request: PropertySweepRequest,
        generatedAt: Date = Date(),
        durationMilliseconds: Double,
        samples: [PropertySweepSample]
    ) {
        self.request = request
        self.generatedAt = generatedAt
        self.durationMilliseconds = durationMilliseconds
        self.samples = samples
    }

    public var successfulSampleCount: Int {
        samples.filter {
            $0.value(for: request.property)?.hasFiniteCalculatedValue == true
        }.count
    }

    public var failedSampleCount: Int {
        samples.count - successfulSampleCount
    }
}

public enum PropertySweepError: Error, Equatable, Sendable {
    case invalidRange(String)
    case invalidPointCount(Int)
    case modelMismatch
    case unsupportedProperty(PropertyID)
    case fixedStateOutsideDomain
    case rangeOutsideDomain
}

extension PropertySweepError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidRange(message):
            message
        case let .invalidPointCount(count):
            "A sweep requires between \(PropertySweepRequest.minimumPointCount) and \(PropertySweepRequest.maximumPointCount) points; received \(count)."
        case .modelMismatch:
            "The sweep request model does not match the selected provider."
        case let .unsupportedProperty(property):
            "The selected provider does not support \(property.rawValue) for this sweep."
        case .fixedStateOutsideDomain:
            "The fixed operating condition is outside the provider domain."
        case .rangeOutsideDomain:
            "The sweep range is outside the provider domain."
        }
    }
}

/// Executes an ordered, cancellable sweep using real provider calculations.
///
/// Successful samples retain their complete provider response and provenance.
/// Provider failures are captured per point so charts and exports can show gaps.
public struct PropertySweepRunner: Sendable {
    public typealias ProgressHandler = @MainActor @Sendable (_ completed: Int, _ total: Int) -> Void

    private let provider: any ThermodynamicModelProvider

    public init(provider: any ThermodynamicModelProvider) {
        self.provider = provider
    }

    public func run(
        _ request: PropertySweepRequest,
        progress: ProgressHandler? = nil
    ) async throws -> PropertySweepResult {
        try validate(request)
        let started = Date()
        var samples: [PropertySweepSample] = []
        samples.reserveCapacity(request.pointCount)

        for index in 0..<request.pointCount {
            try Task.checkCancellation()
            let fraction = Double(index) / Double(request.pointCount - 1)
            let sweptValue = index == request.pointCount - 1
                ? request.endValueSI
                : request.startValueSI + (request.endValueSI - request.startValueSI) * fraction
            let pressurePa = request.axis == .pressure
                ? sweptValue
                : request.baseRequest.pressurePa
            let temperatureK = request.axis == .temperature
                ? sweptValue
                : request.baseRequest.temperatureK
            let calculation = CalculationRequest(
                modelID: request.baseRequest.modelID,
                pressurePa: pressurePa,
                temperatureK: temperatureK,
                composition: request.baseRequest.composition,
                requestedProperties: [request.property],
                clientVersion: request.baseRequest.clientVersion
            )

            do {
                let response = try await provider.calculate(calculation)
                samples.append(PropertySweepSample(
                    index: index,
                    pressurePa: pressurePa,
                    temperatureK: temperatureK,
                    response: response,
                    errorMessage: nil
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ProviderError where error == .cancelled {
                throw CancellationError()
            } catch {
                samples.append(PropertySweepSample(
                    index: index,
                    pressurePa: pressurePa,
                    temperatureK: temperatureK,
                    response: nil,
                    errorMessage: message(for: error)
                ))
            }
            await progress?(index + 1, request.pointCount)
        }

        return PropertySweepResult(
            request: request,
            durationMilliseconds: durationMilliseconds(since: started),
            samples: samples
        )
    }

    private func validate(_ request: PropertySweepRequest) throws {
        guard request.baseRequest.modelID == provider.descriptor.id else {
            throw PropertySweepError.modelMismatch
        }
        guard provider.descriptor.supportedProperties.contains(request.property) else {
            throw PropertySweepError.unsupportedProperty(request.property)
        }
        guard (PropertySweepRequest.minimumPointCount...PropertySweepRequest.maximumPointCount)
            .contains(request.pointCount)
        else {
            throw PropertySweepError.invalidPointCount(request.pointCount)
        }
        guard request.startValueSI.isFinite, request.endValueSI.isFinite,
              request.startValueSI < request.endValueSI
        else {
            throw PropertySweepError.invalidRange(
                "Sweep start and end must be finite, and the end must be greater than the start."
            )
        }

        let domain = provider.descriptor.domain
        switch request.axis {
        case .pressure:
            guard (domain.minimumTemperatureK...domain.maximumTemperatureK)
                .contains(request.baseRequest.temperatureK)
            else { throw PropertySweepError.fixedStateOutsideDomain }
            guard request.startValueSI >= domain.minimumPressurePa,
                  request.endValueSI <= domain.maximumPressurePa
            else { throw PropertySweepError.rangeOutsideDomain }
        case .temperature:
            guard (domain.minimumPressurePa...domain.maximumPressurePa)
                .contains(request.baseRequest.pressurePa)
            else { throw PropertySweepError.fixedStateOutsideDomain }
            guard request.startValueSI >= domain.minimumTemperatureK,
                  request.endValueSI <= domain.maximumTemperatureK
            else { throw PropertySweepError.rangeOutsideDomain }
        }
    }

    private func message(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case let .modelUnavailable(message),
                 let .invalidRequest(message),
                 let .malformedResponse(message):
                return message
            case let .unsupportedComponent(component):
                return "\(component.symbol) is not supported by the provider."
            case .timeout:
                return "The provider calculation timed out."
            case .cancelled:
                return "The provider calculation was cancelled."
            }
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func durationMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}

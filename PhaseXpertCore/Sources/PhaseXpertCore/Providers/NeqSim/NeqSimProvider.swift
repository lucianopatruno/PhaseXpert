import Foundation

public enum NeqSimConfiguration: Sendable {
    public static var environmentEndpoint: URL? {
        if
            let rawValue = ProcessInfo.processInfo.environment["PHASEXPERT_NEQSIM_ENDPOINT"],
            !rawValue.isEmpty
        {
            return URL(string: rawValue)
        }
        #if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8080")
        #else
        return nil
        #endif
    }
}

public struct NeqSimMetadata: Sendable {
    public static let providerID = "neqsim-remote-srk-classic"
    public static let apiSchemaVersion = "neqsim-provider.v1"
    public static let capabilityVersion = "2026.08-pr23"
    public static let serviceVersion = "0.1.0"
    public static let releaseVersion = "3.16.0"
    public static let sourceCommit = "3af7b560525b57f2d3da2c803a08e2b41a8d7f5a"
    public static let eos = "SystemSrkEos"
    public static let alphaFunction = "NeqSim default for SystemSrkEos component parameters"
    public static let mixingRule = "classic"
    public static let interactionData =
        "neqsim-v3.16.0:src/main/resources/data/INTER.csv:7452:CO2-nitrogen:Classic"
}

public protocol NeqSimRemoteClient: Sendable {
    func calculate(_ request: NeqSimStateRequest) async throws -> NeqSimStateResponse
    func phaseEnvelope(_ request: NeqSimEnvelopeRequest) async throws -> NeqSimEnvelopeResponse
}

public struct NeqSimHTTPClient: NeqSimRemoteClient {
    private let endpoint: URL
    private let session: URLSession
    private let timeoutSeconds: TimeInterval

    public init(
        endpoint: URL,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 20
    ) {
        self.endpoint = endpoint
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func calculate(_ request: NeqSimStateRequest) async throws -> NeqSimStateResponse {
        try await post(request, path: "v1/state", response: NeqSimStateResponse.self)
    }

    public func phaseEnvelope(_ request: NeqSimEnvelopeRequest) async throws -> NeqSimEnvelopeResponse {
        try await post(request, path: "v1/phase-envelope", response: NeqSimEnvelopeResponse.self)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ body: Request,
        path: String,
        response: Response.Type
    ) async throws -> Response {
        var url = endpoint
        url.append(path: path)
        guard url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else {
            throw ProviderError.modelUnavailable(
                "NeqSim remote endpoint must use HTTPS outside localhost development."
            )
        }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, urlResponse) = try await session.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw ProviderError.malformedResponse("NeqSim returned a non-HTTP response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ProviderError.malformedResponse(
                    "NeqSim returned HTTP \(httpResponse.statusCode)."
                )
            }
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ProviderError.timeout
            case .cancelled:
                throw ProviderError.cancelled
            default:
                throw ProviderError.modelUnavailable(
                    "NeqSim remote endpoint is offline or unreachable: \(error.localizedDescription)"
                )
            }
        } catch {
            throw ProviderError.malformedResponse("NeqSim response could not be decoded: \(error.localizedDescription)")
        }
    }
}

public struct NeqSimProvider<Client: NeqSimRemoteClient>: ThermodynamicModelProvider {
    private let client: Client?
    private let endpoint: URL?

    public init(endpoint: URL? = NeqSimConfiguration.environmentEndpoint) where Client == NeqSimHTTPClient {
        self.endpoint = endpoint
        self.client = endpoint.map { NeqSimHTTPClient(endpoint: $0) }
    }

    public init(client: Client) {
        self.client = client
        self.endpoint = URL(string: "https://configured.example.invalid")
    }

    public var descriptor: ModelDescriptor {
        ModelDescriptor(
            id: NeqSimMetadata.providerID,
            name: endpoint == nil ? "NeqSim Remote — Not configured" : "NeqSim Remote SRK — Preliminary",
            modelVersion: NeqSimMetadata.releaseVersion,
            providerVersion: "0.1.0",
            availability: endpoint == nil ? .unavailable : .preliminary,
            calculationMode: .remote,
            supportedComponents: endpoint == nil ? [] : [.carbonDioxide, .nitrogen],
            supportedProperties: endpoint == nil ? [] : [
                .density,
                .dynamicViscosity,
                .molarMass,
                .compressibilityFactor,
                .specificVolume
            ],
            domain: .initialCO2Transport,
            scientificBasis: "Remote NeqSim v3.16.0 SystemSrkEos provider for CO₂ and CO₂-N₂ calculations.",
            equationOrMethod:
                "NeqSim SystemSrkEos, setMixingRule(\"classic\"), TPflash for state calculations and calcPTphaseEnvelope for phase envelopes. CO₂/N₂ interaction data is the shipped Classic row in INTER.csv; PhaseXpert does not override or estimate interaction parameters.",
            coefficientSetVersion: NeqSimMetadata.interactionData,
            requiredResources: [
                "Configured HTTPS NeqSim provider endpoint; localhost HTTP is development-only."
            ],
            limitations: [
                "Remote integration is preliminary and has not completed independent PhaseXpert validation.",
                "No CoolProp fallback, cross-fill, interpolation, extrapolation or estimated NeqSim value is allowed.",
                "Only properties explicitly returned by the service are marked calculated.",
                "The 10 mol% N₂ cases are integration scenarios, not validated accuracy ranges.",
                "Production communication requires HTTPS; localhost HTTP is restricted to development."
            ],
            references: [
                SourceReference(
                    authors: "Equinor",
                    title: "NeqSim",
                    year: 2026,
                    doiOrURL: "https://github.com/equinor/neqsim"
                ),
                SourceReference(
                    authors: "Equinor",
                    title: "NeqSim Documentation",
                    year: 2026,
                    doiOrURL: "https://equinor.github.io/neqsim/"
                ),
                SourceReference(
                    authors: "Equinor",
                    title: "Phase Envelope and Critical Points Guide",
                    year: 2026,
                    doiOrURL: "https://github.com/equinor/neqsim/blob/master/docs/pvtsimulation/phase_envelope_guide.md"
                )
            ]
        )
    }

    public func applicabilityIssues(for composition: [MixtureComponent]) -> [ValidationIssue] {
        guard endpoint != nil else { return [] }
        let active = composition.filter { $0.moleFraction > 0 }
        let unsupported = Set(active.map(\.component)).subtracting([.carbonDioxide, .nitrogen])
        var issues: [ValidationIssue] = []
        if !unsupported.isEmpty {
            issues.append(.init(
                code: .unsupportedComponent,
                severity: .error,
                message: "NeqSim PR23 supports only CO₂ and N₂: \(unsupported.map(\.symbol).sorted().joined(separator: ", "))."
            ))
        }
        let nitrogen = active.first { $0.component == .nitrogen }?.moleFraction ?? 0
        if nitrogen > 0.10 {
            issues.append(.init(
                code: .componentOutsideModelRange,
                severity: .error,
                message: "PR23 NeqSim integration scenarios are limited to at most 10 mol% N₂. This is not a validated accuracy range."
            ))
        }
        return issues
    }

    public func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        try Task.checkCancellation()
        let client = try configuredClient()
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest("The request model ID does not match NeqSim.")
        }
        let remoteRequest = NeqSimStateRequest(from: request)
        let remote = try await client.calculate(remoteRequest)
        try validate(remote, requestID: remoteRequest.requestID)
        let propertyValues = try remote.properties.map(propertyValue(from:))
        return CalculationResponse(
            calculationID: UUID(uuidString: remote.calculationID) ?? UUID(),
            requestID: request.requestID,
            model: descriptorWith(remote.provenance),
            phase: phase(from: remote.phase),
            properties: propertyValues,
            solver: SolverMetadata(
                method: remote.convergence.method,
                converged: remote.convergence.converged,
                iterationCount: remote.convergence.iterationCount,
                durationMilliseconds: remote.convergence.durationMilliseconds
            ),
            warnings: [
                "NEQSIM REMOTE — VALIDATION PENDING: do not use this result for engineering, safety, commercial, or regulatory decisions."
            ] + remote.warnings,
            isScientificResult: true
        )
    }

    public func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
        try Task.checkCancellation()
        let client = try configuredClient()
        guard request.modelID == descriptor.id else {
            throw ProviderError.invalidRequest("The phase-envelope request model ID does not match NeqSim.")
        }
        let remoteRequest = NeqSimEnvelopeRequest(from: request)
        let remote = try await client.phaseEnvelope(remoteRequest)
        try validate(remote, requestID: remoteRequest.requestID)
        let points = remote.points.compactMap { point -> PhaseEnvelopePoint? in
            guard
                point.temperatureK.isFinite,
                point.temperatureK > 0,
                point.pressurePa.isFinite,
                point.pressurePa > 0,
                let branch = PhaseEnvelopePoint.Branch(rawValue: point.branch)
            else {
                return nil
            }
            return PhaseEnvelopePoint(
                temperatureK: point.temperatureK,
                pressurePa: point.pressurePa,
                branch: branch
            )
        }
        return PhaseEnvelopeResponse(
            requestID: request.requestID,
            points: points,
            warnings: [
                "NEQSIM REMOTE — VALIDATION PENDING: do not use this phase envelope for engineering, safety, commercial, or regulatory decisions.",
                "Straight chart segments are display-only connections between adjacent finite NeqSim points."
            ] + remote.warnings,
            isAvailable: remote.isAvailable && !points.isEmpty,
            boundaryKind: .mixtureEnvelope,
            model: descriptorWith(remote.provenance),
            generatedAt: Date(),
            solver: SolverMetadata(
                method: remote.convergence.method,
                converged: remote.convergence.converged && remote.isComplete,
                iterationCount: remote.convergence.iterationCount,
                durationMilliseconds: remote.convergence.durationMilliseconds
            )
        )
    }

    private func configuredClient() throws -> Client {
        guard let client else {
            throw ProviderError.modelUnavailable(
                "NeqSim remote endpoint is not configured. Set PHASEXPERT_NEQSIM_ENDPOINT to a development localhost URL or production HTTPS endpoint."
            )
        }
        return client
    }

    private func validate(_ response: NeqSimStateResponse, requestID: String) throws {
        guard response.schemaVersion == NeqSimMetadata.apiSchemaVersion else {
            throw ProviderError.malformedResponse("NeqSim API schema version mismatch.")
        }
        guard response.requestID == requestID else {
            throw ProviderError.malformedResponse("NeqSim response request ID mismatch.")
        }
        guard response.provenance.providerID == NeqSimMetadata.providerID else {
            throw ProviderError.malformedResponse("NeqSim provider ID mismatch.")
        }
    }

    private func validate(_ response: NeqSimEnvelopeResponse, requestID: String) throws {
        guard response.schemaVersion == NeqSimMetadata.apiSchemaVersion else {
            throw ProviderError.malformedResponse("NeqSim API schema version mismatch.")
        }
        guard response.requestID == requestID else {
            throw ProviderError.malformedResponse("NeqSim envelope request ID mismatch.")
        }
        guard response.provenance.providerID == NeqSimMetadata.providerID else {
            throw ProviderError.malformedResponse("NeqSim provider ID mismatch.")
        }
    }

    private func propertyValue(from remote: NeqSimPropertyResult) throws -> PropertyValue {
        guard let property = PropertyID(rawValue: remote.property) else {
            throw ProviderError.malformedResponse("NeqSim returned unsupported property \(remote.property).")
        }
        guard let status = PropertyStatus(rawValue: remote.status) else {
            throw ProviderError.malformedResponse("NeqSim returned invalid property status.")
        }
        if status == .calculated {
            guard remote.value?.isFinite == true else {
                throw ProviderError.malformedResponse("NeqSim marked \(remote.property) calculated without a finite value.")
            }
        }
        return PropertyValue(
            property: property,
            value: remote.value,
            unit: remote.unit,
            status: status,
            message: remote.message
        )
    }

    private func phase(from remote: String) -> PhaseRegion {
        PhaseRegion(rawValue: remote) ?? .unknown
    }

    private func descriptorWith(_ provenance: NeqSimProvenance) -> ModelDescriptor {
        var base = descriptor
        base = ModelDescriptor(
            id: provenance.providerID,
            name: descriptor.name,
            modelVersion: provenance.neqsimVersion,
            providerVersion: provenance.serviceVersion,
            availability: descriptor.availability,
            calculationMode: .remote,
            supportedComponents: descriptor.supportedComponents,
            supportedProperties: descriptor.supportedProperties,
            domain: descriptor.domain,
            scientificBasis: descriptor.scientificBasis,
            equationOrMethod:
                "\(provenance.eos); alpha: \(provenance.alphaFunction); mixing rule: \(provenance.mixingRule); API \(provenance.apiSchemaVersion); Java \(provenance.javaRuntimeVersion)",
            coefficientSetVersion: provenance.interactionData,
            requiredResources: descriptor.requiredResources,
            limitations: descriptor.limitations,
            references: descriptor.references
        )
        return base
    }
}

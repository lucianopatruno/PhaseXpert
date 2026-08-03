import XCTest
@testable import PhaseXpertCore

final class NeqSimProviderTests: XCTestCase {
    private final class HTTP422URLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = """
            {"detail":{"schema_version":"neqsim-provider.v1","request_id":"manual-pure-co2-150bar-20c","calculation_id":"422-regression","error":"neqsim_state_failed","message":"NeqSim Python bridge is not importable"}}
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 422,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private struct MockNeqSimClient: NeqSimRemoteClient {
        var state: @Sendable (NeqSimStateRequest) async throws -> NeqSimStateResponse
        var envelope: @Sendable (NeqSimEnvelopeRequest) async throws -> NeqSimEnvelopeResponse

        func calculate(_ request: NeqSimStateRequest) async throws -> NeqSimStateResponse {
            try await state(request)
        }

        func phaseEnvelope(_ request: NeqSimEnvelopeRequest) async throws -> NeqSimEnvelopeResponse {
            try await envelope(request)
        }
    }

    func testDefaultRegistryContainsUnavailableNeqSimWhenEndpointIsMissing() {
        let provider = ProviderRegistry().provider(id: NeqSimMetadata.providerID)

        XCTAssertEqual(provider?.descriptor.id, NeqSimMetadata.providerID)
        XCTAssertEqual(provider?.descriptor.availability, .unavailable)
        XCTAssertEqual(provider?.descriptor.calculationMode, .remote)
        XCTAssertTrue(provider?.descriptor.requiredResources.first?.contains("HTTPS") == true)
    }

    func testPinnedNeqSimIdentityAndLicenceMetadataAreTraceable() {
        let descriptor = NeqSimProvider(
            client: mockClient()
        ).descriptor

        XCTAssertEqual(descriptor.modelVersion, "3.16.0")
        XCTAssertEqual(descriptor.coefficientSetVersion, NeqSimMetadata.interactionData)
        XCTAssertTrue(descriptor.equationOrMethod.contains("SystemSrkEos"))
        XCTAssertTrue(descriptor.equationOrMethod.contains("classic"))
        XCTAssertTrue(descriptor.references.contains {
            $0.doiOrURL == "https://github.com/equinor/neqsim"
        })
    }

    func testUnavailableEndpointThrowsPreciseModelUnavailableError() async {
        let provider = NeqSimProvider<NeqSimHTTPClient>(endpoint: nil)
        let request = CalculationRequest(
            modelID: NeqSimMetadata.providerID,
            pressurePa: 1_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Expected unavailable endpoint failure.")
        } catch let ProviderError.modelUnavailable(message) {
            XCTAssertTrue(message.contains("PHASEXPERT_NEQSIM_ENDPOINT"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOfflineEndpointReportsModelUnavailableWithoutFallback() async {
        let provider = NeqSimProvider<NeqSimHTTPClient>(
            endpoint: URL(string: "http://127.0.0.1:9")!
        )
        let request = CalculationRequest(
            modelID: NeqSimMetadata.providerID,
            pressurePa: 1_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Expected offline endpoint failure.")
        } catch let ProviderError.modelUnavailable(message) {
            XCTAssertTrue(message.contains("offline") || message.contains("unreachable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPValidationDetailIsPreservedForNonSuccessResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTP422URLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = NeqSimHTTPClient(
            endpoint: URL(string: "http://127.0.0.1:8080")!,
            session: session
        )
        let request = CalculationRequest(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000422")!,
            modelID: NeqSimMetadata.providerID,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            clientVersion: "1.0 (3)"
        )
        let remoteRequest = NeqSimStateRequest(from: request)
        let encoded = try JSONEncoder().encode(remoteRequest)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"pressure_pa\":15000000"))
        XCTAssertTrue(json.contains("\"temperature_k\":293.15"))
        XCTAssertTrue(json.contains("\"component\":\"co2\""))
        XCTAssertTrue(json.contains("\"mole_fraction\":1"))
        XCTAssertTrue(json.contains("\"requested_properties\""))

        do {
            _ = try await client.calculate(remoteRequest)
            XCTFail("Expected HTTP validation detail to be surfaced.")
        } catch let ProviderError.malformedResponse(message) {
            XCTAssertTrue(message.contains("HTTP 422"))
            XCTAssertTrue(message.contains("neqsim_state_failed"))
            XCTAssertTrue(message.contains("NeqSim Python bridge is not importable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStateRequestPreservesCompositionBasisAndProviderIdentity() async throws {
        let provider = NeqSimProvider(client: mockClient())
        let request = CalculationRequest(
            requestID: UUID(),
            modelID: NeqSimMetadata.providerID,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            requestedProperties: [.density, .dynamicViscosity, .thermalConductivity],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)

        XCTAssertEqual(response.model.id, NeqSimMetadata.providerID)
        XCTAssertEqual(response.model.modelVersion, NeqSimMetadata.releaseVersion)
        XCTAssertEqual(response.phase, .gas)
        XCTAssertEqual(response.properties.first { $0.property == .density }?.status, .calculated)
        XCTAssertEqual(
            response.properties.first { $0.property == .thermalConductivity }?.status,
            .unavailable
        )
        XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
        XCTAssertTrue(response.solver.converged)
    }

    func testNonFiniteCalculatedStateValueIsRejected() async {
        let provider = NeqSimProvider(
            client: MockNeqSimClient(
                state: { request in
                    NeqSimStateResponse(
                        requestID: request.requestID,
                        pressurePa: request.pressurePa,
                        temperatureK: request.temperatureK,
                        composition: request.composition,
                        phase: "gas",
                        properties: [
                            .init(property: "density", value: .nan, unit: "kg/m³", status: "calculated")
                        ],
                        warnings: [],
                        convergence: .init(
                            method: "mock",
                            converged: true,
                            durationMilliseconds: 1,
                            status: "completed"
                        )
                    )
                },
                envelope: { _ in throw ProviderError.modelUnavailable("unused") }
            )
        )
        let request = CalculationRequest(
            modelID: NeqSimMetadata.providerID,
            pressurePa: 1_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Expected non-finite value rejection.")
        } catch let ProviderError.malformedResponse(message) {
            XCTAssertTrue(message.contains("finite"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPhaseEnvelopeUsesOnlyFiniteProviderReturnedBubbleAndDewPoints() async throws {
        let provider = NeqSimProvider(client: mockClient())
        let request = PhaseEnvelopeRequest(
            modelID: NeqSimMetadata.providerID,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.90),
                .init(component: .nitrogen, moleFraction: 0.10)
            ]
        )

        let response = try await provider.phaseEnvelope(request)

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.boundaryKind, .mixtureEnvelope)
        XCTAssertEqual(response.points.filter { $0.branch == .bubble }.count, 2)
        XCTAssertEqual(response.points.filter { $0.branch == .dew }.count, 2)
        XCTAssertTrue(response.points.allSatisfy {
            $0.temperatureK.isFinite && $0.pressurePa.isFinite
        })
        XCTAssertTrue(response.solver?.converged == true)
        XCTAssertTrue(response.warnings.contains { $0.contains("display-only") })
    }

    func testEndpointRejectsPlainHTTPOutsideLocalhost() async {
        let provider = NeqSimProvider<NeqSimHTTPClient>(
            endpoint: URL(string: "http://example.com")!
        )
        let request = CalculationRequest(
            modelID: NeqSimMetadata.providerID,
            pressurePa: 1_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Expected insecure endpoint rejection.")
        } catch let ProviderError.modelUnavailable(message) {
            XCTAssertTrue(message.contains("HTTPS"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func mockClient() -> MockNeqSimClient {
        MockNeqSimClient(
            state: { request in
                NeqSimStateResponse(
                    requestID: request.requestID,
                    pressurePa: request.pressurePa,
                    temperatureK: request.temperatureK,
                    composition: request.composition,
                    phase: "gas",
                    properties: request.requestedProperties.map {
                        switch $0 {
                        case "density":
                            .init(property: $0, value: 42.0, unit: "kg/m³", status: "calculated")
                        case "dynamicViscosity":
                            .init(property: $0, value: 0.000012, unit: "Pa·s", status: "calculated")
                        default:
                            .init(
                                property: $0,
                                value: nil,
                                unit: "",
                                status: "unavailable",
                                message: "Non-scientific mock unavailable property."
                            )
                        }
                    },
                    warnings: ["Non-scientific mock response for transport testing."],
                    convergence: .init(
                        method: "Non-scientific mock",
                        converged: true,
                        durationMilliseconds: 3,
                        status: "completed"
                    )
                )
            },
            envelope: { request in
                NeqSimEnvelopeResponse(
                    requestID: request.requestID,
                    points: [
                        .init(temperatureK: 240, pressurePa: 900_000, branch: "bubble"),
                        .init(temperatureK: 250, pressurePa: 1_200_000, branch: "bubble"),
                        .init(temperatureK: 260, pressurePa: 1_300_000, branch: "dew"),
                        .init(temperatureK: 270, pressurePa: 1_100_000, branch: "dew"),
                        .init(temperatureK: .nan, pressurePa: 1_000_000, branch: "dew")
                    ],
                    isAvailable: true,
                    isComplete: true,
                    warnings: ["Non-scientific mock envelope."],
                    convergence: .init(
                        method: "Non-scientific mock envelope",
                        converged: true,
                        durationMilliseconds: 5,
                        status: "completed"
                    )
                )
            }
        )
    }
}

import PhaseXpertCore
import SwiftData
import XCTest
@testable import PhaseXpert

final class PhaseXpertTests: XCTestCase {
    @MainActor
    func testIFEContactMailLinkIncludesSubject() throws {
        let url = IFEContactMailLink.url

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.absoluteString, "mailto:firmapost@ife.no?subject=PhaseXpert")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "firmapost@ife.no")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "subject" })?.value,
            "PhaseXpert"
        )
    }

    @MainActor
    func testImpuritySelectorsAreAlphabeticalByVisibleSymbol() {
        let viewModel = CalculatorViewModel()
        XCTAssertEqual(
            viewModel.supportedImpurityComponents.map(\.symbol),
            ["Ar", "CH₄", "CO", "H₂", "H₂O", "H₂S", "N₂", "O₂"]
        )

        let streamMixing = StreamMixingViewModel()
        let streamID = streamMixing.streams[0].id
        let streamSymbols = streamMixing.impurityOptions(
            streamID: streamID,
            including: .argon
        ).map(\.symbol)
        XCTAssertEqual(
            streamSymbols,
            streamSymbols.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        )
    }

    @MainActor
    func testPhoneCaseSixtyCelsiusFortyBarRunsEquilibriumWhenHomogeneousIsUnavailable() async throws {
        let viewModel = wetGeneralViewModel(pressureBar: 40, temperatureCelsius: 60)
        viewModel.validate()

        XCTAssertFalse(viewModel.homogeneousWetPropertiesAreInPreliminaryDomain)
        XCTAssertTrue(viewModel.canRunCalculation)
        XCTAssertEqual(
            viewModel.calculationNotice,
            CalculatorViewModel.independentWaterEquilibriumNotice
        )

        await viewModel.calculate()

        let result = try XCTUnwrap(viewModel.standaloneWaterEquilibriumResult)
        XCTAssertEqual(result.waterStatus, .belowSaturation)
        XCTAssertEqual(try XCTUnwrap(result.currentWaterPPM), 500, accuracy: 1e-9)
        XCTAssertGreaterThan(result.waterInCarbonDioxideRichPhasePPM, 500)
        XCTAssertGreaterThan(try XCTUnwrap(result.marginToSaturationPPM), 0)
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.calculationError)
    }

    @MainActor
    func testPhoneCaseOneHundredCelsiusOneHundredBarRunsEquilibriumWhenHomogeneousIsUnavailable() async throws {
        let viewModel = wetGeneralViewModel(pressureBar: 100, temperatureCelsius: 100)
        viewModel.validate()

        XCTAssertFalse(viewModel.homogeneousWetPropertiesAreInPreliminaryDomain)
        XCTAssertTrue(viewModel.canRunCalculation)
        await viewModel.calculate()

        let result = try XCTUnwrap(viewModel.standaloneWaterEquilibriumResult)
        XCTAssertEqual(result.waterStatus, .belowSaturation)
        XCTAssertEqual(try XCTUnwrap(result.currentWaterPPM), 500, accuracy: 1e-9)
        XCTAssertEqual(result.waterInCarbonDioxideRichPhasePPM, 17_914.32, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(result.marginToSaturationPPM), 17_414.32, accuracy: 0.1)
        XCTAssertEqual(result.carbonDioxideInWaterRichPhaseMoleFraction * 100, 1.410471, accuracy: 0.00001)
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.calculationError)
    }

    @MainActor
    func testWetStateOutsideBothCapabilityDomainsReturnsNoFabricatedResult() async {
        let viewModel = wetGeneralViewModel(pressureBar: 100, temperatureCelsius: 20)
        viewModel.validate()

        XCTAssertFalse(viewModel.homogeneousWetPropertiesAreInPreliminaryDomain)
        XCTAssertFalse(viewModel.canRunCalculation)
        XCTAssertNil(viewModel.waterEquilibriumPreview)
        XCTAssertEqual(
            viewModel.waterEquilibriumUnavailableMessage,
            "Water calculations are unavailable at this condition. Validated water-equilibrium ranges are \(SpycherPruess2003WaterEquilibrium.validatedRangeSummary)"
        )
        await viewModel.calculate()
        XCTAssertNil(viewModel.standaloneWaterEquilibriumResult)
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNotNil(viewModel.operatingRangeGuidance?.currentInputIssues.first {
            $0.severity == .unsupported
        })
    }

    @MainActor
    func testHomogeneousWetPropertiesCanRunOutsideWaterEquilibriumDomain() async throws {
        let viewModel = wetGeneralViewModel(pressureBar: 40, temperatureCelsius: 100)
        viewModel.validate()

        XCTAssertTrue(viewModel.validationReport.canCalculate)
        XCTAssertTrue(viewModel.canRunCalculation)
        XCTAssertTrue(viewModel.homogeneousWetPropertiesAreInPreliminaryDomain)
        XCTAssertNil(viewModel.waterEquilibriumPreview)
        await viewModel.calculate()
        XCTAssertNotNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.standaloneWaterEquilibriumResult)
        XCTAssertNil(viewModel.calculationRecord?.response.waterEquilibrium)
    }

    @MainActor
    private func wetGeneralViewModel(
        pressureBar: Double,
        temperatureCelsius: Double
    ) -> CalculatorViewModel {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "coolprop-heos"
        viewModel.pressureText = String(pressureBar)
        viewModel.temperatureText = String(temperatureCelsius)
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "999500"),
            CompositionInput(component: .water, value: "500")
        ]
        return viewModel
    }

    @MainActor
    private func advancedNitrogenViewModel(
        pressureBar: Double,
        temperatureCelsius: Double,
        nitrogenPPM: Double
    ) -> CalculatorViewModel {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = String(format: "%.12g", pressureBar)
        viewModel.temperatureText = String(format: "%.12g", temperatureCelsius)
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: String(format: "%.12g", 1_000_000 - nitrogenPPM)),
            CompositionInput(component: .nitrogen, value: String(format: "%.12g", nitrogenPPM))
        ]
        return viewModel
    }

    @MainActor
    func testWaterEquilibriumPreviewIsBinaryOnlyAndIndependentOfHomogeneousGate() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "coolprop-heos"
        viewModel.pressureText = "47.1"
        viewModel.temperatureText = "100.12"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "999500"),
            CompositionInput(component: .water, value: "500")
        ]

        let equilibrium = try XCTUnwrap(viewModel.waterEquilibriumPreview)
        XCTAssertEqual(equilibrium.waterStatus, .belowSaturation)
        XCTAssertGreaterThan(equilibrium.waterInCarbonDioxideRichPhasePPM, 20_000)
        XCTAssertEqual(equilibrium.currentWaterPPM, 500)

        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "980000"),
            CompositionInput(component: .water, value: "20000")
        ]
        let dropoutPreview = try XCTUnwrap(viewModel.waterEquilibriumPreview)
        XCTAssertNotNil(dropoutPreview.waterDropoutPressurePa)
        XCTAssertEqual(dropoutPreview.waterStatus, .belowSaturation)

        viewModel.composition.append(
            CompositionInput(component: .nitrogen, value: "100")
        )
        XCTAssertNil(viewModel.waterEquilibriumPreview)
    }

    @MainActor
    func testExpandedWaterEquilibriumPreviewIncludesDropoutTemperatureOutsideHomogeneousTemperatureGate() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "coolprop-heos"
        viewModel.pressureText = "30.012"
        viewModel.temperatureText = "60.03"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "991713"),
            CompositionInput(component: .water, value: "8287")
        ]
        let equilibrium = try XCTUnwrap(viewModel.waterEquilibriumPreview)
        XCTAssertEqual(try XCTUnwrap(equilibrium.waterDropoutTemperatureK), 333.46436, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(equilibrium.waterSaturationRatio), 1.012, accuracy: 0.002)
    }
    private static let testDescriptor = ModelDescriptor(
        id: "test-calculation-provider",
        name: "Test calculation provider",
        modelVersion: "test",
        providerVersion: "test",
        availability: .available,
        calculationMode: .local,
        supportedComponents: [.carbonDioxide, .nitrogen],
        supportedProperties: [.density],
        domain: .initialCO2Transport,
        scientificBasis: "Test double for app-state tests.",
        equationOrMethod: "Test double",
        limitations: ["Not a production provider."],
        references: []
    )

    private struct TestCalculationProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: .dense,
                properties: [
                    PropertyValue(
                        property: .density,
                        value: 800,
                        unit: "kg/m³",
                        status: .calculated,
                        message: "Test density."
                    )
                ],
                solver: SolverMetadata(
                    method: "Test calculation",
                    converged: true,
                    durationMilliseconds: 1
                ),
                warnings: [],
                isScientificResult: false
            )
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [],
                isAvailable: false
            )
        }
    }

    private final class PhaseEnvelopeCallCounter: @unchecked Sendable {
        private(set) var callCount = 0

        func recordCall() {
            callCount += 1
        }
    }

    private final class PhaseMapCallCounter: @unchecked Sendable {
        private(set) var calculationCount = 0
        private(set) var envelopeCount = 0

        func recordCalculation() {
            calculationCount += 1
        }

        func recordEnvelope() {
            envelopeCount += 1
        }
    }

    private struct CountingPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor
        let counter: PhaseEnvelopeCallCounter
        var delayNanoseconds: UInt64 = 0

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            try await TestCalculationProvider().calculate(request)
        }

        func phaseEnvelope(
            _ request: PhaseEnvelopeRequest
        ) async throws -> PhaseEnvelopeResponse {
            counter.recordCall()
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [
                    .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                    .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
                ],
                warnings: ["PRELIMINARY — validation pending."],
                isAvailable: true,
                boundaryKind: .pureFluidSaturation,
                model: descriptor,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                solver: .init(
                    method: "Deterministic test saturation",
                    converged: true,
                    durationMilliseconds: 1
                )
            )
        }
    }

    private struct AdvancedPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor: ModelDescriptor
        let supportsMethaneEnvelope: Bool

        init(supportsMethaneEnvelope: Bool) {
            self.supportsMethaneEnvelope = supportsMethaneEnvelope
            descriptor = ModelDescriptor(
                id: "teqp-pure-co2-experimental",
                name: "Advanced CCS Properties",
                modelVersion: "teqp v0.23.1",
                providerVersion: "test",
                availability: .preliminary,
                calculationMode: .local,
                supportedComponents: [.carbonDioxide, .methane, .hydrogen],
                supportedProperties: [.density],
                domain: .initialCO2Transport,
                scientificBasis: "Test Advanced CCS descriptor.",
                equationOrMethod: "EOS-CG-2021",
                limitations: [],
                references: []
            )
        }

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            guard abs(request.temperatureK - 293.13) <= 0.02
                    || abs(request.temperatureK - 298.142) <= 0.02
            else {
                throw ProviderError.invalidRequest(
                    "CO₂+CH₄ VLE is validated only at the ordinary Petropoulou et al. 2018 isotherms 293.13 K (19.98 °C) and 298.14 K (24.99 °C) for xCH₄ = 0.05."
                )
            }
            return CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: .twoPhase,
                properties: [
                    PropertyValue(
                        property: .density,
                        value: nil,
                        unit: "kg/m³",
                        status: .unavailable,
                        message: "No bulk two-phase density."
                    ),
                    PropertyValue(
                        property: .vapourFraction,
                        value: nil,
                        unit: "",
                        status: .unavailable,
                        message: "No fabricated phase fraction."
                    )
                ],
                solver: SolverMetadata(
                    method: "CO₂+CH₄ binary VLE classification",
                    converged: true,
                    durationMilliseconds: 1
                ),
                warnings: ["Bulk density, phase fraction and critical termination unavailable."],
                isScientificResult: true
            )
        }

        func phaseEnvelope(
            _ request: PhaseEnvelopeRequest
        ) async throws -> PhaseEnvelopeResponse {
            if supportsMethaneEnvelope {
                return PhaseEnvelopeResponse(
                    requestID: request.requestID,
                    points: [
                        .init(temperatureK: 293.13, pressurePa: 6_500_000, branch: .dew),
                        .init(temperatureK: 293.13, pressurePa: 7_000_000, branch: .bubble),
                        .init(temperatureK: .nan, pressurePa: 7_100_000, branch: .bubble),
                        .init(temperatureK: 298.142, pressurePa: 6_900_000, branch: .dew),
                        .init(temperatureK: 298.142, pressurePa: 7_500_000, branch: .bubble)
                    ],
                    warnings: [
                        "Critical termination is not drawn for xCH₄ = 0.05."
                    ],
                    isAvailable: true,
                    boundaryKind: .mixtureEnvelope,
                    model: descriptor,
                    generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    solver: .init(
                        method: "CO₂+CH₄ binary VLE phase-envelope points",
                        converged: true,
                        durationMilliseconds: 1
                    )
                )
            }
            throw ProviderError.invalidRequest(
                "Advanced CCS Properties phase diagrams are available only for pure CO₂ or the validated CO₂+CH₄ VLE gate at xCH₄ = 0.05. H₂ phase envelopes remain unavailable and no CoolProp fallback is used."
            )
        }
    }

    private struct DelayedPhaseEnvelopeProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor
        let delayNanoseconds: UInt64

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            try await TestCalculationProvider().calculate(request)
        }

        func phaseEnvelope(
            _ request: PhaseEnvelopeRequest
        ) async throws -> PhaseEnvelopeResponse {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: ["Delayed test provider completed."],
                isAvailable: false
            )
        }
    }

    private struct CountingPhaseMapProvider: ThermodynamicModelProvider {
        let descriptor = PhaseXpertTests.testDescriptor
        let counter: PhaseMapCallCounter
        var delayNanoseconds: UInt64 = 0

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            counter.recordCalculation()
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: request.pressurePa > 15_000_000 ? .liquid : .gas,
                properties: [
                    PropertyValue(
                        property: .density,
                        value: 100,
                        unit: "kg/m³",
                        status: .calculated,
                        message: "Test density."
                    )
                ],
                solver: SolverMetadata(
                    method: "Test flash",
                    converged: true,
                    durationMilliseconds: 1
                ),
                warnings: [],
                isScientificResult: false
            )
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            counter.recordEnvelope()
            return PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [],
                warnings: [],
                isAvailable: false
            )
        }
    }

    func testDefaultRegistryContainsBothFutureProductionProviders() {
        let registry = ProviderRegistry()
        let identifiers = Set(registry.descriptors.map(\.id))
        XCTAssertTrue(identifiers.contains("coolprop-heos"))
        XCTAssertTrue(identifiers.contains("ife-model"))
        XCTAssertFalse(identifiers.contains("architecture-demo"))
        XCTAssertNil(registry.provider(id: "ife-model"))
        XCTAssertEqual(
            registry.provider(id: "coolprop-heos")?.descriptor.availability,
            expectedDefaultCoolPropAvailability
        )
    }

    @MainActor
    func testAdvancedCCSPropertiesShowsOnlyValidatedImpurities() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        XCTAssertEqual(viewModel.selectedDescriptor?.name, "Advanced CCS Properties")
        XCTAssertEqual(
            Set(viewModel.supportedImpurityComponents),
            [.oxygen, .argon, .methane, .hydrogen, .nitrogen, .hydrogenSulfide]
        )
        XCTAssertTrue(viewModel.supportedImpurityComponents.contains(.nitrogen))
        XCTAssertTrue(viewModel.supportedImpurityComponents.contains(.oxygen))
        XCTAssertTrue(viewModel.supportedImpurityComponents.contains(.argon))

        let firstID = try XCTUnwrap(viewModel.addImpurity())
        XCTAssertEqual(
            viewModel.composition.first { $0.id == firstID }?.component,
            .argon
        )
        let methaneOptions = viewModel.impurityOptions(including: .methane)
        XCTAssertEqual(
            Set(methaneOptions),
            [.oxygen, .argon, .methane, .hydrogen, .nitrogen, .hydrogenSulfide]
        )
        XCTAssertTrue(methaneOptions.contains(.nitrogen))
        XCTAssertTrue(methaneOptions.contains(.oxygen))
        XCTAssertTrue(methaneOptions.contains(.argon))

        let secondID = try XCTUnwrap(viewModel.addImpurity())
        XCTAssertEqual(
            viewModel.composition.first { $0.id == secondID }?.component,
            .methane
        )
        viewModel.updateImpurity(id: firstID, component: .nitrogen)
        XCTAssertEqual(
            Set(viewModel.composition.map(\.component)),
            [.carbonDioxide, .nitrogen, .methane]
        )
    }

    @MainActor
    func testAdvancedNitrogenValidatedStateActivatesScientificShield() throws {
        let viewModel = advancedNitrogenViewModel(
            pressureBar: 40,
            temperatureCelsius: 10,
            nitrogenPPM: 12_700
        )
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.validate()

        XCTAssertTrue(viewModel.scientificShieldIsActive)
        let guidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertTrue(guidance.currentInputIssues.isEmpty)
        XCTAssertTrue(guidance.propertyAvailability.contains {
            $0.title == "Cp/Cv/speed"
                && $0.severity == .unsupported
        })
    }

    @MainActor
    func testAdvancedNitrogenInvalidTemperatureNeutralizesScientificShield() throws {
        let viewModel = advancedNitrogenViewModel(
            pressureBar: 40,
            temperatureCelsius: 20,
            nitrogenPPM: 12_700
        )
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.validate()

        XCTAssertFalse(viewModel.scientificShieldIsActive)
        let guidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertTrue(guidance.currentInputIssues.contains {
            $0.title == "Temperature outside validated range"
                && $0.detail.contains("Current: 20 °C")
                && $0.detail.contains("Validated: 10 °C")
        })
    }

    @MainActor
    func testAdvancedNitrogenInvalidCompositionNeutralizesScientificShield() throws {
        let viewModel = advancedNitrogenViewModel(
            pressureBar: 40,
            temperatureCelsius: 10,
            nitrogenPPM: 12_801
        )
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.validate()

        XCTAssertFalse(viewModel.scientificShieldIsActive)
        let guidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertTrue(guidance.currentInputIssues.contains {
            $0.title == "Composition outside validated range"
                && $0.detail.contains("Current N₂: 12801 ppm")
                && $0.detail.contains("Validated N₂: 1.27 mol%")
        })
    }

    @MainActor
    func testGeneralPureCarbonDioxideKeepsNeutralScientificShieldState() {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "coolprop-heos"
        viewModel.pressureText = "50"
        viewModel.temperatureText = "20"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "1000000")
        ]
        viewModel.validate()

        XCTAssertFalse(viewModel.scientificShieldIsActive)
    }

    @MainActor
    func testPreliminaryUnsupportedMixtureKeepsNeutralScientificShieldState() {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "40"
        viewModel.temperatureText = "10"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "970000"),
            CompositionInput(component: .nitrogen, value: "30000")
        ]
        viewModel.validate()

        XCTAssertFalse(viewModel.scientificShieldIsActive)
    }

    @MainActor
    func testAdvancedCCSPropertiesHydrogenCalculationUsesValidatedDensityDomain() async throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.pressureText = "30"
        viewModel.temperatureText = "20"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "94.638"),
            .init(component: .hydrogen, value: "5.362")
        ]

        await viewModel.calculate()

        let record = try XCTUnwrap(viewModel.calculationRecord)
        XCTAssertEqual(record.request.modelID, "teqp-pure-co2-experimental")
        XCTAssertEqual(record.response.model.name, "Advanced CCS Properties")
        XCTAssertEqual(record.response.phase, .gas)
        XCTAssertEqual(
            record.response.properties.first { $0.property == .density }?.status,
            .calculated
        )
        XCTAssertEqual(
            record.response.properties.first { $0.property == .speedOfSound }?.status,
            .unavailable
        )
        XCTAssertTrue(record.response.solver.method.contains("generic N-component density solve"))
        XCTAssertTrue(record.response.solver.method.contains("EOSCGDirectTeqpDensityProbeResults"))
        XCTAssertTrue(record.response.warnings.contains { $0.contains("Souissi") })
        XCTAssertTrue(record.response.warnings.contains { $0.contains("no fallback provider") })
    }

    @MainActor
    func testAdvancedCCSPropertiesMethaneCalculationUsesValidatedDensityDomain() async throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.pressureText = "49.7979"
        viewModel.temperatureText = "27.997"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "95"),
            .init(component: .methane, value: "5")
        ]

        await viewModel.calculate()

        let record = try XCTUnwrap(viewModel.calculationRecord)
        XCTAssertEqual(record.request.modelID, "teqp-pure-co2-experimental")
        XCTAssertEqual(record.response.model.name, "Advanced CCS Properties")
        XCTAssertEqual(record.response.phase, .gas)
        XCTAssertEqual(
            record.response.properties.first { $0.property == .density }?.status,
            .calculated
        )
        XCTAssertEqual(
            record.response.properties.first { $0.property == .isobaricHeatCapacity }?.status,
            .unavailable
        )
        XCTAssertTrue(record.response.solver.method.contains("generic N-component density solve"))
        XCTAssertTrue(record.response.solver.method.contains("MethaneDensityDomainExpansion2026-08-15"))
        XCTAssertTrue(record.response.warnings.contains { $0.contains("Ghafri") })
    }

    @MainActor
    func testAdvancedCCSMethaneVLERejectsMinusZeroPointZeroTwoCelsiusBecauseItIs273K() async throws {
        let provider = AdvancedPhaseEnvelopeProvider(supportsMethaneEnvelope: true)
        let viewModel = CalculatorViewModel(
            registry: ProviderRegistry(providers: [provider])
        )
        viewModel.selectedModelID = provider.descriptor.id
        viewModel.pressureText = "66"
        viewModel.temperatureText = "-0.02"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "950000"),
            .init(component: .methane, value: "50000")
        ]

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertTrue(
            viewModel.calculationError?.contains("293.13 K (19.98 °C)") == true,
            viewModel.calculationError ?? "nil"
        )
    }

    @MainActor
    func testAdvancedCCSMethaneVLEAcceptsDisplayCelsiusEquivalentToSupportedIsotherms() async throws {
        for input in [
            (celsius: "19.98", expectedKelvin: 293.13),
            (celsius: "19.999", expectedKelvin: 293.149),
            (celsius: "24.99", expectedKelvin: 298.14)
        ] {
            let provider = AdvancedPhaseEnvelopeProvider(supportsMethaneEnvelope: true)
            let viewModel = CalculatorViewModel(
                registry: ProviderRegistry(providers: [provider])
            )
            viewModel.selectedModelID = provider.descriptor.id
            viewModel.pressureText = "66"
            viewModel.temperatureText = input.celsius
            viewModel.compositionBasis = .partsPerMillion
            viewModel.composition = [
                .init(component: .carbonDioxide, value: "950000"),
                .init(component: .methane, value: "50000")
            ]

            await viewModel.calculate()

            let record = try XCTUnwrap(viewModel.calculationRecord)
            XCTAssertNil(viewModel.calculationError)
            XCTAssertEqual(record.request.temperatureK, input.expectedKelvin, accuracy: 1e-12)
            XCTAssertEqual(record.response.phase, .twoPhase)
            XCTAssertEqual(
                record.response.properties.first { $0.property == .density }?.status,
                .unavailable
            )
            XCTAssertTrue(record.response.solver.method.contains("CO₂+CH₄ binary VLE"))
        }
    }

    @MainActor
    func testAdvancedCCSMethaneVLERejectsDisplayCelsiusOutsideIsothermTolerance() async throws {
        let provider = AdvancedPhaseEnvelopeProvider(supportsMethaneEnvelope: true)
        let viewModel = CalculatorViewModel(
            registry: ProviderRegistry(providers: [provider])
        )
        viewModel.selectedModelID = provider.descriptor.id
        viewModel.pressureText = "66"
        viewModel.temperatureText = "20.01"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "950000"),
            .init(component: .methane, value: "50000")
        ]

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertTrue(
            viewModel.calculationError?.contains("298.14 K (24.99 °C)") == true,
            viewModel.calculationError ?? "nil"
        )
    }

    @MainActor
    func testAdvancedCCSPropertiesRejectsOutOfDomainMixtureState() async throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        guard viewModel.selectedDescriptor?.availability != .unavailable else {
            throw XCTSkip("Native teqp XCFramework is not linked in this test runtime.")
        }

        viewModel.pressureText = "80"
        viewModel.temperatureText = "27.99"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "95"),
            .init(component: .methane, value: "5")
        ]

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertTrue(
            viewModel.calculationError?.contains("outside the validated range") == true,
            viewModel.calculationError ?? "nil"
        )
    }

    @MainActor
    func testAdvancedCCSHydrogenMixtureReportsProviderPhaseDiagramUnavailable() async throws {
        let descriptor = try XCTUnwrap(
            ProviderRegistry().descriptors.first {
                $0.id == "teqp-pure-co2-experimental"
            }
        )
        let record = try await makeRecord(
            modelID: "teqp-pure-co2-experimental",
            modelDescriptor: descriptor,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.94638),
                .init(component: .hydrogen, moleFraction: 0.05362)
            ]
        )
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                AdvancedPhaseEnvelopeProvider(supportsMethaneEnvelope: false)
            ])
        )

        viewModel.load(for: record)
        try await waitUntil { viewModel.errorMessage != nil }

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.response)
        XCTAssertNil(viewModel.phaseMapRecord)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("cannot be shown for this calculation") == true,
            viewModel.errorMessage ?? "nil"
        )
    }

    @MainActor
    func testAdvancedCCSMethaneMixtureLoadsProviderPhaseEnvelope() async throws {
        let provider = AdvancedPhaseEnvelopeProvider(supportsMethaneEnvelope: true)
        let record = try await makeRecord(
            modelID: provider.descriptor.id,
            modelDescriptor: provider.descriptor,
            pressureValue: 67,
            pressurePa: 6_700_000,
            temperatureValue: -0.02,
            temperatureK: 293.13,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .methane, moleFraction: 0.05)
            ]
        )
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [provider])
        )

        viewModel.load(for: record)
        try await waitUntil { viewModel.response != nil }

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.scopeMessage)
        XCTAssertNil(viewModel.phaseMapRecord)
        XCTAssertEqual(viewModel.response?.boundaryKind, .mixtureEnvelope)
        XCTAssertEqual(viewModel.response?.points.filter { $0.branch == .bubble }.count, 3)
        XCTAssertEqual(viewModel.response?.points.filter { $0.branch == .dew }.count, 2)
        XCTAssertTrue(viewModel.response?.points.contains { !$0.temperatureK.isFinite } == true)
        XCTAssertFalse(viewModel.response?.points.contains { $0.branch == .critical } == true)
        XCTAssertTrue(
            viewModel.response?.warnings.contains {
                $0.contains("Critical termination is not drawn")
            } == true
        )
    }

    @MainActor
    func testAdvancedProviderIDSavedCaseCompatibility() async throws {
        let descriptor = try XCTUnwrap(
            ProviderRegistry().descriptors.first {
                $0.id == "teqp-pure-co2-experimental"
            }
        )
        let record = try await makeRecord(
            modelID: "teqp-pure-co2-experimental",
            modelDescriptor: descriptor,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let viewModel = CalculatorViewModel()

        viewModel.loadInputs(from: record)

        XCTAssertEqual(viewModel.selectedModelID, "teqp-pure-co2-experimental")
        XCTAssertEqual(record.response.model.id, "teqp-pure-co2-experimental")
    }

    @MainActor
    func testIFEModelIsVisibleUnavailableAndCannotCalculateOrFallback() async throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "ife-model"
        viewModel.validate()

        XCTAssertEqual(viewModel.selectedDescriptor?.name, "IFE Model")
        XCTAssertEqual(viewModel.selectedDescriptor?.availability, .unavailable)
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .modelUnavailable
                && $0.message == "This model is not available in this version."
        })

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.calculationError)
        XCTAssertNil(ProviderRegistry().provider(id: "ife-model"))
    }

    @MainActor
    func testLegacyIFESavedCaseLoadsAsUnavailableWithoutChangingProvenance() async throws {
        let legacy = try await makeRecord(
            modelID: "ife-model",
            modelDescriptor: ProviderRegistry.ifeModelDescriptor,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let viewModel = CalculatorViewModel()

        viewModel.loadInputs(from: legacy)

        XCTAssertEqual(viewModel.selectedModelID, "ife-model")
        XCTAssertEqual(viewModel.selectedDescriptor?.availability, .unavailable)
        XCTAssertEqual(legacy.response.model.id, "ife-model")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .modelUnavailable
        })
    }

    @MainActor
    func testPhaseDiagramStopsSpinningAndAcceptsLatePureCO2Completion() async throws {
        let record = try await makeRecord()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                DelayedPhaseEnvelopeProvider(delayNanoseconds: 120_000_000)
            ]),
            timeoutNanoseconds: 20_000_000
        )

        viewModel.load(for: record)
        XCTAssertTrue(viewModel.isLoading)

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.errorMessage?.contains("will appear automatically") == true)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.response)
    }

    @MainActor
    func testMixturePhaseDiagramExposesPhaseMapWithoutProviderCall() async throws {
        let counter = PhaseMapCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseMapProvider(counter: counter)
            ])
        )

        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.999999),
            .init(component: .nitrogen, moleFraction: 0.000001)
        ]))

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.response)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.scopeMessage)
        XCTAssertNotNil(viewModel.phaseMapRecord)
        XCTAssertEqual(viewModel.phaseMapResolution, .five)
        XCTAssertEqual(viewModel.phaseMapProgress.totalCount, 25)
        XCTAssertEqual(counter.calculationCount, 0)
        XCTAssertEqual(counter.envelopeCount, 0)
    }

    @MainActor
    func testMulticomponentPhaseMapCalculatesDiscreteFlashPoints() async throws {
        let counter = PhaseMapCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseMapProvider(counter: counter)
            ])
        )
        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ]))

        viewModel.calculatePhaseMap()
        try await waitUntil { viewModel.phaseMapResult != nil }

        XCTAssertEqual(viewModel.phaseMapResult?.evaluations.count, 25)
        XCTAssertEqual(viewModel.phaseMapResult?.operatingPoint?.point.pressurePa, 15_000_000)
        XCTAssertEqual(viewModel.phaseMapResult?.operatingPoint?.point.temperatureK, 293.15)
        XCTAssertEqual(counter.calculationCount, 25)
        XCTAssertEqual(counter.envelopeCount, 0)
        XCTAssertEqual(viewModel.phaseMapResult?.warnings.count, 2)
    }

    @MainActor
    func testPureToMixtureTransitionClearsResultAndRejectsLateCompletion() async throws {
        let counter = PhaseEnvelopeCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseEnvelopeProvider(
                    counter: counter,
                    delayNanoseconds: 80_000_000
                )
            ])
        )
        let pure = try await makeRecord()
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])

        viewModel.load(for: pure)
        XCTAssertTrue(viewModel.isLoading)

        viewModel.load(for: mixture)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.phaseMapRecord)
        XCTAssertNil(viewModel.scopeMessage)
        XCTAssertNil(viewModel.response)

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(viewModel.response)
        XCTAssertEqual(counter.callCount, 1)
    }

    @MainActor
    func testMixtureToPureTransitionRestoresPhaseDiagramAvailability() async throws {
        let counter = PhaseEnvelopeCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseEnvelopeProvider(counter: counter)
            ])
        )
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])

        viewModel.load(for: mixture)
        XCTAssertEqual(counter.callCount, 0)
        XCTAssertNotNil(viewModel.phaseMapRecord)
        XCTAssertNil(viewModel.scopeMessage)

        viewModel.load(for: try await makeRecord())
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(viewModel.scopeMessage)
        XCTAssertNil(viewModel.phaseMapRecord)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.response)
        XCTAssertEqual(counter.callCount, 1)
    }

    @MainActor
    func testPhaseMapInputChangesMarkResultStaleAndPreservePhysicalUnits() async throws {
        let counter = PhaseMapCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseMapProvider(counter: counter)
            ])
        )
        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ]))
        viewModel.calculatePhaseMap()
        try await waitUntil { viewModel.phaseMapResult != nil }

        viewModel.changePhaseMapPressureUnit(to: .megapascalAbsolute)
        XCTAssertEqual(try numericValue(viewModel.pressureMinimumText), 7.5, accuracy: 0.000_001)
        XCTAssertEqual(try numericValue(viewModel.pressureMaximumText), 22.5, accuracy: 0.000_001)
        XCTAssertTrue(viewModel.isPhaseMapResultStale)

        viewModel.changePhaseMapTemperatureUnit(to: .kelvin)
        XCTAssertEqual(try numericValue(viewModel.temperatureMinimumText), 268.15, accuracy: 0.000_001)
        XCTAssertEqual(try numericValue(viewModel.temperatureMaximumText), 318.15, accuracy: 0.000_001)
    }

    @MainActor
    func testPhaseMapInvalidUnitChangePreservesEnteredValuesAndUnit() async throws {
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseMapProvider(counter: PhaseMapCallCounter())
            ])
        )
        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ]))
        viewModel.pressureMinimumText = "not numeric"
        viewModel.changePhaseMapPressureUnit(to: .psiAbsolute)

        XCTAssertEqual(viewModel.phaseMapPressureUnit, .barAbsolute)
        XCTAssertEqual(viewModel.pressureMinimumText, "not numeric")
        XCTAssertTrue(viewModel.phaseMapIssues.contains { $0.code == .invalidPressureRange })
    }

    @MainActor
    func testPhaseMapSupersedesLateResultsAfterInputChange() async throws {
        let counter = PhaseMapCallCounter()
        let viewModel = PhaseDiagramViewModel(
            registry: ProviderRegistry(providers: [
                CountingPhaseMapProvider(counter: counter, delayNanoseconds: 20_000_000)
            ])
        )
        viewModel.load(for: try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ]))

        viewModel.calculatePhaseMap()
        viewModel.phaseMapResolution = .ten
        viewModel.calculatePhaseMap()
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            viewModel.phaseMapResult?.evaluations.count == 101
        }

        XCTAssertEqual(viewModel.phaseMapResult?.request.resolution, .ten)
        XCTAssertEqual(counter.envelopeCount, 0)
    }

    @MainActor
    func testPhaseDiagramExportRejectsMulticomponentAndPreservesPureCO2Export() async throws {
        let pure = try await makeRecord()
        let mixture = try await makeRecord(composition: [
            .init(component: .carbonDioxide, moleFraction: 0.99),
            .init(component: .nitrogen, moleFraction: 0.01)
        ])
        let pureResponse = PhaseEnvelopeResponse(
            requestID: pure.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_400_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: pure.response.model
        )
        let mixtureResponse = PhaseEnvelopeResponse(
            requestID: mixture.request.requestID,
            points: [
                .init(temperatureK: 240, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 268, pressurePa: 2_900_000, branch: .dew)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .mixtureEnvelope,
            model: mixture.response.model
        )

        XCTAssertNoThrow(
            try PhaseDiagramImageExporter().attachment(
                for: pure,
                response: pureResponse
            )
        )
        let artifacts = try PhaseDiagramImageExporter().writeTemporaryReportFiles(
            for: pure,
            response: pureResponse
        )
        XCTAssertEqual(Set(artifacts.files.map(\.pathExtension)), ["pdf", "csv"])
        for file in artifacts.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            try? FileManager.default.removeItem(at: file)
        }
        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().attachment(
                for: mixture,
                response: mixtureResponse
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
            )
        }
    }

    @MainActor
    func testPhaseBoundarySegmentsTerminateAtInvalidPointsBranchChangesAndCriticalPoints() {
        let response = PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 240, pressurePa: 1_500_000, branch: .bubble),
                .init(temperatureK: .nan, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 2_000_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: -1, branch: .bubble),
                .init(temperatureK: 270, pressurePa: 2_500_000, branch: .bubble),
                .init(temperatureK: 280, pressurePa: 2_800_000, branch: .dew),
                .init(temperatureK: 290, pressurePa: 3_000_000, branch: .dew),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical),
                .init(temperatureK: 300, pressurePa: 6_000_000, branch: .bubble),
                .init(temperatureK: 301, pressurePa: 6_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        )

        let plotData = PhaseBoundarySeriesBuilder.plotData(for: response)

        XCTAssertEqual(plotData.receivedPointCount, 11)
        XCTAssertEqual(plotData.validPointCount, 9)
        XCTAssertEqual(plotData.plottedPointCount, 7)
        XCTAssertEqual(plotData.criticalPoints.map(\.originalIndex), [8])
        XCTAssertEqual(plotData.segments.map { $0.points.map(\.originalIndex) }, [
            [0, 1],
            [6, 7],
            [9, 10]
        ])
        XCTAssertTrue(plotData.segments.allSatisfy { segment in
            Set(segment.points.map(\.branch)) == [segment.branch]
        })
    }

    @MainActor
    func testPhaseBoundaryPlotCountsSingletonBoundaryAsValidButNotPlotted() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [.init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble)],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.receivedPointCount, 1)
        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 0)
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsTwoAdjacentBoundaryPointsAsPlotted() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 2)
        XCTAssertEqual(plotData.plottedPointCount, 2)
        XCTAssertEqual(plotData.segments.first?.points.map(\.originalIndex), [0, 1])
    }

    @MainActor
    func testPhaseBoundaryPlotDropsSingletonBetweenGaps() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: .nan, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: -1, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.receivedPointCount, 3)
        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 0)
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsCriticalOnlyWhenRenderedButNoLineSegment() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [.init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 1)
        XCTAssertEqual(plotData.plottedPointCount, 1)
        XCTAssertEqual(plotData.criticalPoints.map(\.originalIndex), [0])
        XCTAssertTrue(plotData.segments.isEmpty)
    }

    @MainActor
    func testPhaseBoundaryPlotCountsLineSegmentPlusCriticalPoint() {
        let plotData = PhaseBoundarySeriesBuilder.plotData(for: PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation
        ))

        XCTAssertEqual(plotData.validPointCount, 3)
        XCTAssertEqual(plotData.plottedPointCount, 3)
        XCTAssertEqual(plotData.segments.first?.points.count, 2)
        XCTAssertEqual(plotData.criticalPoints.count, 1)
    }

    @MainActor
    func testPhaseDiagramExportRejectsResponseWithoutRenderableBoundarySegment() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 304.1282, pressurePa: 7_377_300, branch: .critical)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: true, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response
            )
        )
    }

    @MainActor
    func testPhaseDiagramExportRejectsNonConvergedResponse() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: ["Synthetic non-converged response."],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: false, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response
            )
        )
    }

    @MainActor
    func testPhaseDiagramTemporaryStoreCleansOnlyOwnedArtifacts() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let owned = store.directory.appendingPathComponent("PhaseXpert-Phase-Diagram-test.pdf")
        let unrelated = store.directory.appendingPathComponent("Other.txt")
        try Data("owned".utf8).write(to: owned)
        try Data("other".utf8).write(to: unrelated)

        try store.cleanStaleArtifacts()

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansPreparedArtifactsWhenViewCleansUp() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        let artifacts = try makeTemporaryDiagramArtifacts(in: store, id: "cleanup")

        try lifecycle.prepareReplacement { artifacts }
        lifecycle.cleanupIfIdle()

        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansAfterShareCompletionAndCancellation() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "completed")
        }
        let completed = try XCTUnwrap(lifecycle.artifacts)
        lifecycle.beginSharing()
        lifecycle.cleanupIfIdle()
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed.files[0].path))
        lifecycle.completeSharing()
        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: completed.files[0].path))

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "cancelled")
        }
        let cancelled = try XCTUnwrap(lifecycle.artifacts)
        lifecycle.beginSharing()
        lifecycle.completeSharing()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleCleansOnCalculationChangeWhenIdle() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        let artifacts = try makeTemporaryDiagramArtifacts(in: store, id: "changed")

        try lifecycle.prepareReplacement { artifacts }
        lifecycle.calculationChanged()

        XCTAssertNil(lifecycle.artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportLifecycleReplacementCleansStaleOwnedFilesOnly() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PhaseDiagramTemporaryExportStore(baseDirectory: base)
        let lifecycle = PhaseDiagramExportLifecycle(store: store)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let stale = store.directory.appendingPathComponent("PhaseXpert-Phase-Diagram-stale.pdf")
        let unrelated = store.directory.appendingPathComponent("external.pdf")
        try Data("stale".utf8).write(to: stale)
        try Data("external".utf8).write(to: unrelated)

        try lifecycle.prepareReplacement {
            try makeTemporaryDiagramArtifacts(in: store, id: "replacement")
        }
        let replacement = try XCTUnwrap(lifecycle.artifacts)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.files[0].path))
        try? FileManager.default.removeItem(at: base)
    }

    @MainActor
    func testPhaseDiagramExportRemovesPDFWhenCSVWriteFails() async throws {
        let record = try await makeRecord()
        let response = PhaseEnvelopeResponse(
            requestID: record.request.requestID,
            points: [
                .init(temperatureK: 250, pressurePa: 1_800_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 2_100_000, branch: .bubble)
            ],
            warnings: [],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: record.response.model,
            solver: .init(method: "test", converged: true, durationMilliseconds: 1)
        )

        XCTAssertThrowsError(
            try PhaseDiagramImageExporter().writeTemporaryReportFiles(
                for: record,
                response: response,
                csvWriter: { _, _ in throw CalculationExportError.textEncodingFailed }
            )
        )

        let store = PhaseDiagramTemporaryExportStore()
        let pdfURL = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(record.response.calculationID.uuidString.prefix(8)).pdf"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @MainActor
    func testCalculatorStartsWithCoolPropSelected() {
        let viewModel = CalculatorViewModel()
        XCTAssertEqual(viewModel.selectedModelID, "coolprop-heos")
        XCTAssertEqual(viewModel.compositionBasis, .partsPerMillion)
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 1_000_000)
    }

    @MainActor
    func testCalculatorExposesNativeTeqpAsSelectableWhenLinked() throws {
        let viewModel = CalculatorViewModel()
        guard NativeTeqpEngine().isAvailable else {
            throw XCTSkip("The generated teqp XCFramework is not linked to this build.")
        }

        let descriptor = viewModel.descriptors.first {
            $0.id == "teqp-pure-co2-experimental"
        }
        XCTAssertEqual(descriptor?.availability, .preliminary)
        XCTAssertTrue(
            viewModel.selectableDescriptors.contains {
                $0.id == "teqp-pure-co2-experimental"
            }
        )

        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        XCTAssertEqual(viewModel.selectedDescriptor?.availability, .preliminary)
    }

    @MainActor
    func testCalculatorCalculatesReportedTeqpCompressedCO2State() async throws {
        let viewModel = CalculatorViewModel()
        guard NativeTeqpEngine().isAvailable else {
            throw XCTSkip("The generated teqp XCFramework is not linked to this build.")
        }

        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "150"
        viewModel.temperatureText = "20"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "1000000")
        ]

        await viewModel.calculate()

        XCTAssertNil(viewModel.calculationError)
        let record = try XCTUnwrap(viewModel.calculationRecord)
        XCTAssertEqual(record.response.model.id, "teqp-pure-co2-experimental")
        XCTAssertEqual(record.response.phase, .liquid)
        let density = try XCTUnwrap(
            record.response.properties.first { $0.property == .density }
        )
        XCTAssertEqual(density.status, .calculated)
        XCTAssertEqual(
            try XCTUnwrap(density.value),
            903.956424708662,
            accuracy: 0.001
        )
    }

    @MainActor
    func testSavedCaseDefaultNameIncludesActiveMixtureComposition() {
        XCTAssertEqual(
            SavedCaseNameFormatter.compositionLabel(for: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ]),
            "CO₂ 95 mol% + N₂ 5 mol%"
        )
        XCTAssertEqual(
            SavedCaseNameFormatter.compositionLabel(for: [
                .init(component: .carbonDioxide, moleFraction: 1)
            ]),
            "CO₂"
        )
    }

    @MainActor
    func testNewImpurityStartsEmptyAndReturnsItsFocusIdentity() {
        let viewModel = CalculatorViewModel()

        let addedID = viewModel.addImpurity()

        XCTAssertEqual(viewModel.composition.count, 2)
        XCTAssertEqual(viewModel.composition.last?.id, addedID)
        XCTAssertEqual(viewModel.composition.last?.value, "")
    }

    @MainActor
    func testPPMInputCompletesCarbonDioxideRemainderWithoutNormalization() throws {
        let viewModel = CalculatorViewModel()
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "12500"
        viewModel.validate()

        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 987_500, accuracy: 1e-12)
        XCTAssertFalse(viewModel.canNormalize)
        XCTAssertFalse(viewModel.validationReport.issues.contains { $0.code == .compositionTotal })
    }

    @MainActor
    func testMolePercentInputCompletesCarbonDioxideRemainderWithoutNormalization() throws {
        let viewModel = CalculatorViewModel()
        viewModel.changeCompositionBasis(to: .molePercent)
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "12.5"
        viewModel.validate()

        XCTAssertEqual(viewModel.carbonDioxideMolePercent, 87.5, accuracy: 1e-12)
        XCTAssertEqual(
            viewModel.displayedCompositionValue(for: viewModel.composition[0]),
            "87.5"
        )
        XCTAssertFalse(viewModel.canNormalize)
        XCTAssertFalse(
            viewModel.validationReport.issues.contains { $0.code == .compositionTotal }
        )
    }

    @MainActor
    func testImpurityCanBeRemovedByIdentityAndRemainderUpdates() throws {
        let viewModel = CalculatorViewModel()
        let firstID = try XCTUnwrap(viewModel.addImpurity())
        let secondID = try XCTUnwrap(viewModel.addImpurity())
        _ = try XCTUnwrap(viewModel.addImpurity())

        for index in viewModel.composition.indices
        where viewModel.composition[index].component != .carbonDioxide {
            viewModel.composition[index].value = "10000"
        }
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 970_000, accuracy: 1e-12)

        viewModel.removeImpurity(id: secondID)

        XCTAssertEqual(viewModel.composition.count, 3)
        XCTAssertEqual(viewModel.composition.first?.component, .carbonDioxide)
        XCTAssertTrue(viewModel.composition.contains { $0.id == firstID })
        XCTAssertFalse(viewModel.composition.contains { $0.id == secondID })
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 980_000, accuracy: 1e-12)
    }

    @MainActor
    func testCompositionBasisRoundTripPreservesMoleFractions() throws {
        let viewModel = CalculatorViewModel()
        _ = viewModel.addImpurity()
        let impurityIndex = try XCTUnwrap(
            viewModel.composition.firstIndex { $0.component != .carbonDioxide }
        )
        viewModel.composition[impurityIndex].value = "10000"

        viewModel.changeCompositionBasis(to: .molePercent)
        XCTAssertEqual(viewModel.carbonDioxideMolePercent, 99, accuracy: 1e-12)
        XCTAssertEqual(
            viewModel.displayedCompositionValue(for: viewModel.composition[0]),
            "99"
        )
        XCTAssertEqual(viewModel.composition[impurityIndex].value, "1")

        viewModel.changeCompositionBasis(to: .partsPerMillion)
        XCTAssertEqual(viewModel.carbonDioxidePartsPerMillion, 990_000, accuracy: 1e-12)
        XCTAssertEqual(viewModel.composition[impurityIndex].value, "10000")
    }

    @MainActor
    func testPressureUnitChangePreservesPhysicalSIValue() {
        let viewModel = CalculatorViewModel()
        viewModel.pressureText = "150"
        viewModel.validate()

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)

        XCTAssertEqual(Double(viewModel.pressureText) ?? .nan, 15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.pressureDisplayUnit, .megapascalAbsolute)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .psiAbsolute)
        XCTAssertEqual(
            Double(viewModel.pressureText) ?? .nan,
            15_000_000 / UnitConstants.psiToPascal,
            accuracy: 1e-7
        )
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        for _ in 0..<10 {
            viewModel.changePressureDisplayUnit(to: .barAbsolute)
            viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)
            viewModel.changePressureDisplayUnit(to: .psiAbsolute)
        }
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: Double(viewModel.pressureText) ?? .nan),
            15_000_000,
            accuracy: 1e-3
        )
    }

    @MainActor
    func testPSIAbsolutePressureDisplayUnitConvertsToAndFromPascal() {
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: 1),
            6_894.757_293_168,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.displayValue(from: 6_894.757_293_168),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            CalculationInputSnapshot(
                pressureValue: 2_175.566_119_4,
                pressureUnit: .psia,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: []
            ).pressureDisplayUnitLabel,
            "psi(a)"
        )
        XCTAssertEqual(
            CalculationInputSnapshot(
                pressureValue: 2_175.566_119_4,
                pressureUnit: .psi,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: []
            ).pressureDisplayUnitLabel,
            "psi"
        )
    }

    @MainActor
    func testCalculationSnapshotPreservesMegapascalAndKelvinEntryUnits() async throws {
        let record = try await makeRecord(
            pressureValue: 15,
            pressureUnit: .megapascal,
            pressurePa: 15_000_000,
            temperatureValue: 293.15,
            temperatureUnit: .kelvin,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        XCTAssertEqual(record.input.pressureValue, 15, accuracy: 1e-12)
        XCTAssertEqual(record.input.pressureUnit, .megapascal)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "MPa(a)")
        XCTAssertEqual(record.input.pressurePa, 15_000_000, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureValue, 293.15, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureUnit, .kelvin)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testCalculationSnapshotPreservesPSIAndFahrenheitEntryUnits() async throws {
        let pressurePsi = 2_175.566_119_4
        let pressurePa = PressureUnit.psia.toPascal(pressurePsi)
        let record = try await makeRecord(
            pressureValue: pressurePsi,
            pressureUnit: .psia,
            pressurePa: pressurePa,
            temperatureValue: 68,
            temperatureUnit: .fahrenheit,
            temperatureK: TemperatureUnit.fahrenheit.toKelvin(68),
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        XCTAssertEqual(record.input.pressureValue, pressurePsi, accuracy: 1e-12)
        XCTAssertEqual(record.input.pressureUnit, .psia)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "psi(a)")
        XCTAssertEqual(record.input.pressurePa, pressurePa, accuracy: 1e-6)
        XCTAssertEqual(record.input.temperatureValue, 68, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureUnit, .fahrenheit)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testViewModelCalculationPreservesPSIAndFahrenheitProvenance() async throws {
        let viewModel = CalculatorViewModel()
        let pressurePsi = PressureUnit.psia.fromPascal(15_000_000)
        viewModel.pressureDisplayUnit = .psiAbsolute
        viewModel.temperatureDisplayUnit = .fahrenheit
        viewModel.pressureText = String(pressurePsi)
        viewModel.temperatureText = "68"
        viewModel.validate()

        await viewModel.calculate()

        let record = try XCTUnwrap(viewModel.calculationRecord)
        XCTAssertEqual(record.input.pressureUnit, .psia)
        XCTAssertEqual(record.input.pressureDisplayUnitLabel, "psi(a)")
        XCTAssertEqual(record.input.pressureValue, pressurePsi, accuracy: 1e-10)
        XCTAssertEqual(record.input.pressurePa, 15_000_000, accuracy: 1e-3)
        XCTAssertEqual(record.input.temperatureUnit, .fahrenheit)
        XCTAssertEqual(record.input.temperatureValue, 68, accuracy: 1e-12)
        XCTAssertEqual(record.input.temperatureK, 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testHistoricalBarCelsiusRecordDecodesWithoutReinterpretingUnits() async throws {
        let historical = try await makeRecord(
            pressureValue: 150,
            pressureUnit: .bara,
            pressurePa: 15_000_000,
            temperatureValue: 20,
            temperatureUnit: .celsius,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let data = try JSONEncoder().encode(historical)

        let decoded = try JSONDecoder().decode(CalculationRecord.self, from: data)

        XCTAssertEqual(decoded.input.pressureValue, 150, accuracy: 1e-12)
        XCTAssertEqual(decoded.input.pressureUnit, .bara)
        XCTAssertEqual(decoded.input.pressureDisplayUnitLabel, "bar(a)")
        XCTAssertEqual(decoded.input.temperatureValue, 20, accuracy: 1e-12)
        XCTAssertEqual(decoded.input.temperatureUnit, .celsius)
    }

    @MainActor
    func testTemperatureUnitChangePreservesPhysicalSIValue() {
        let viewModel = CalculatorViewModel()
        viewModel.temperatureText = "20"
        viewModel.validate()

        viewModel.changeTemperatureDisplayUnit(to: .kelvin)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 293.15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .kelvin)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)
        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 68, accuracy: 1e-10)
        XCTAssertTrue(viewModel.validationReport.canCalculate)

        for _ in 0..<10 {
            viewModel.changeTemperatureDisplayUnit(to: .celsius)
            viewModel.changeTemperatureDisplayUnit(to: .kelvin)
            viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)
        }
        XCTAssertEqual(
            TemperatureDisplayUnit.fahrenheit.kelvin(from: Double(viewModel.temperatureText) ?? .nan),
            293.15,
            accuracy: 1e-10
        )
    }

    @MainActor
    func testFahrenheitTemperatureDisplayUnitConvertsToAndFromKelvin() {
        XCTAssertEqual(
            TemperatureDisplayUnit.fahrenheit.kelvin(from: 0),
            255.3722222222222,
            accuracy: 1e-12
        )
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.kelvin(from: 32), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.kelvin(from: 212), 373.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.displayValue(from: 273.15), 32, accuracy: 1e-12)
        XCTAssertEqual(TemperatureDisplayUnit.fahrenheit.displayValue(from: 373.15), 212, accuracy: 1e-12)
    }

    @MainActor
    func testInvalidOperatingPointEntryDoesNotCorruptLastValidDisplayUnitConversion() {
        let viewModel = CalculatorViewModel()
        viewModel.pressureText = "150"
        viewModel.temperatureText = "20"
        viewModel.validate()

        viewModel.pressureText = "not-a-number"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)

        XCTAssertEqual(Double(viewModel.pressureText) ?? .nan, 15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.pressureDisplayUnit, .megapascalAbsolute)

        viewModel.pressureText = "-"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changePressureDisplayUnit(to: .psiAbsolute)

        XCTAssertEqual(
            PressureDisplayUnit.psiAbsolute.pascal(from: Double(viewModel.pressureText) ?? .nan),
            15_000_000,
            accuracy: 1e-3
        )
        XCTAssertEqual(viewModel.pressureDisplayUnit, .psiAbsolute)

        viewModel.temperatureText = ""
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .kelvin)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 293.15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .kelvin)

        viewModel.temperatureText = "-"
        viewModel.validate()
        XCTAssertFalse(viewModel.validationReport.canCalculate)

        viewModel.changeTemperatureDisplayUnit(to: .fahrenheit)

        XCTAssertEqual(Double(viewModel.temperatureText) ?? .nan, 68, accuracy: 1e-10)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .fahrenheit)
    }

    @MainActor
    func testMovingImpuritiesKeepsCO2FirstAndPreservesStableIDs() throws {
        let viewModel = CalculatorViewModel()
        let firstID = try XCTUnwrap(viewModel.addImpurity())
        let secondID = try XCTUnwrap(viewModel.addImpurity())
        viewModel.composition[1].value = "100"
        viewModel.composition[2].value = "200"

        viewModel.moveImpurities(from: IndexSet(integer: 2), to: 1)

        XCTAssertEqual(viewModel.composition.first?.component, .carbonDioxide)
        XCTAssertEqual(viewModel.composition.map(\.id).dropFirst(), [secondID, firstID])
        XCTAssertEqual(viewModel.composition[1].value, "200")
        XCTAssertEqual(viewModel.composition[2].value, "100")
    }

    @MainActor
    func testEngineeringFormatterConvertsDisplayUnitsWithoutChangingSIValue() {
        let enthalpy = PropertyValue(
            property: .enthalpy,
            value: 300_000,
            unit: "J/kg",
            status: .calculated
        )
        let viscosity = PropertyValue(
            property: .dynamicViscosity,
            value: 0.000_093,
            unit: "Pa·s",
            status: .calculated
        )

        let displayedEnthalpy = EngineeringPropertyFormatter.measurement(for: enthalpy)
        let displayedViscosity = EngineeringPropertyFormatter.measurement(for: viscosity)
        XCTAssertEqual(displayedEnthalpy?.value ?? .nan, 300, accuracy: 1e-12)
        XCTAssertEqual(displayedEnthalpy?.unit, "kJ/kg")
        XCTAssertEqual(displayedViscosity?.value ?? .nan, 0.093, accuracy: 1e-12)
        XCTAssertEqual(displayedViscosity?.unit, "mPa·s")
        XCTAssertEqual(enthalpy.value, 300_000)
        XCTAssertEqual(enthalpy.unit, "J/kg")
    }

    @MainActor
    func testUnsupportedPropertyFormattingRemainsExplicitlyUnavailable() {
        let property = PropertyValue(
            property: .enthalpy,
            value: nil,
            unit: "J/kg",
            status: .unavailable,
            message: "Expanded pure-fluid property unavailable for this composition."
        )

        XCTAssertEqual(EngineeringPropertyFormatter.text(for: property), "Unavailable")
        XCTAssertEqual(EngineeringPropertyFormatter.effectiveStatus(for: property), .unavailable)
    }

    @MainActor
    func testPropertyResultRowPresentationExposesCopyOnlyForFiniteValues() {
        let available = PropertyResultPresentation(property: PropertyValue(
            property: .density,
            value: 903.5,
            unit: "kg/m³",
            status: .calculated,
            message: "Calculated density."
        ))
        let unavailable = PropertyResultPresentation(property: PropertyValue(
            property: .enthalpy,
            value: nil,
            unit: "J/kg",
            status: .unavailable,
            message: "Unavailable for this composition."
        ))
        let nonFinite = PropertyResultPresentation(property: PropertyValue(
            property: .density,
            value: .nan,
            unit: "kg/m³",
            status: .calculated
        ))

        XCTAssertEqual(available.title, "Density")
        XCTAssertFalse(available.value.isEmpty)
        XCTAssertNotEqual(available.value, "Unavailable")
        XCTAssertEqual(available.unit, "kg/m³")
        XCTAssertEqual(available.copyValue, "903.5 kg/m³")
        XCTAssertTrue(available.statusText.contains("Calculated"))
        XCTAssertNil(unavailable.copyValue)
        XCTAssertNil(nonFinite.copyValue)
        XCTAssertEqual(unavailable.value, "Unavailable")
    }

    @MainActor
    func testReferenceLinkResolverAcceptsOnlyHTTPSAndDOIIdentifiers() {
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "10.1016/j.fluid.2020.112"),
            URL(string: "https://doi.org/10.1016/j.fluid.2020.112")
        )
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "doi:10.1021/acs.jced.1c00123"),
            URL(string: "https://doi.org/10.1021/acs.jced.1c00123")
        )
        XCTAssertEqual(
            ReferenceLinkResolver.url(for: "https://example.org/reference"),
            URL(string: "https://example.org/reference")
        )
        XCTAssertNil(ReferenceLinkResolver.url(for: "http://example.org/reference"))
        XCTAssertNil(ReferenceLinkResolver.url(for: "10/not-a-doi"))
        XCTAssertNil(ReferenceLinkResolver.url(for: "   "))
        XCTAssertNil(ReferenceLinkResolver.url(for: "ftp://example.org/reference"))
    }

    private var expectedDefaultCoolPropAvailability: ModelAvailability {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        .preliminary
        #else
        .unavailable
        #endif
    }

    @MainActor
    func testSavedCalculationPersistsAndPreservesRecord() async throws {
        let record = try await makeRecord()
        let schema = Schema(versionedSchema: PhaseXpertSchemaV1.self)
        let configuration = ModelConfiguration(
            "PhaseXpertTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PhaseXpertMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let savedCase = try SavedCalculation(
            name: "Pipeline inlet",
            notes: "Reference operating point",
            record: record
        )

        context.insert(savedCase)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavedCalculation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Pipeline inlet")
        XCTAssertEqual(fetched.first?.calculationRecord, record)
        XCTAssertEqual(fetched.first?.recordFormatVersion, 1)
    }

    @MainActor
    func testSavedCalculationDuplicateGetsNewIdentityAndKeepsProvenance() async throws {
        let record = try await makeRecord()
        let savedCase = try SavedCalculation(name: "Ship tank", record: record)
        let duplicate = savedCase.duplicate()

        XCTAssertNotEqual(duplicate.id, savedCase.id)
        XCTAssertEqual(duplicate.name, "Ship tank — Copy")
        XCTAssertEqual(duplicate.calculationID, savedCase.calculationID)
        XCTAssertEqual(duplicate.calculationRecord, record)
    }

    @MainActor
    func testBuiltInCasesLoadIntoCalculatorWithDefaultsAndComposition() throws {
        let viewModel = CalculatorViewModel()
        let porthos = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("porthos-pipeline-specification-example"))

        viewModel.loadInputs(from: porthos)

        XCTAssertEqual(viewModel.pressureText, "31")
        XCTAssertEqual(viewModel.temperatureText, "20")
        XCTAssertEqual(viewModel.compositionBasis, .molePercent)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: viewModel.composition.map { ($0.component, $0.value) }),
            [
                .carbonDioxide: "96",
                .nitrogen: "2.4",
                .methane: "1",
                .argon: "0.4",
                .hydrogen: "0.2"
            ]
        )

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)
        viewModel.changeTemperatureDisplayUnit(to: .kelvin)

        XCTAssertEqual(try numericValue(viewModel.pressureText), 3.1, accuracy: 1e-12)
        XCTAssertEqual(try numericValue(viewModel.temperatureText), 293.15, accuracy: 1e-12)
    }

    @MainActor
    func testBuiltInCasesRemainSeparateFromUserPersistenceAndDuplicateToMyCases() throws {
        let schema = Schema(versionedSchema: PhaseXpertSchemaV1.self)
        let configuration = ModelConfiguration(
            "PhaseXpertBuiltInCasesTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PhaseXpertMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedCalculation>()).count, 0)

        let builtInCase = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("aramis-ship-specification-example"))
        let savedCase = try SavedCalculation(
            name: "\(builtInCase.name) — Copy",
            notes: builtInCase.modelingBasis,
            record: builtInCase.inputSnapshotRecord()
        )
        context.insert(savedCase)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavedCalculation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "Aramis ship specification example — Copy")
        XCTAssertEqual(fetched[0].pressureBarAbsolute, 16)
        XCTAssertEqual(fetched[0].temperatureCelsius, -25, accuracy: 1e-12)
        XCTAssertEqual(BuiltInCaseCatalog.cases.count, 5)
    }

    @MainActor
    func testBuiltInCasesLoadIndependentlyIntoStreamAAndStreamBAndRemainEditable() throws {
        let viewModel = StreamMixingViewModel()
        let streamA = try XCTUnwrap(viewModel.streams.first?.id)
        let streamB = try XCTUnwrap(viewModel.streams.dropFirst().first?.id)
        let porthos = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("porthos-pipeline-specification-example"))
        let aramis = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("aramis-ship-specification-example"))

        viewModel.changeStreamPressureUnit(streamID: streamA, to: .megapascalAbsolute)
        viewModel.changeStreamTemperatureUnit(streamID: streamA, to: .kelvin)
        viewModel.loadBuiltInCase(porthos, into: streamA)

        XCTAssertEqual(try numericValue(viewModel.streams[0].pressureText), 3.1, accuracy: 1e-12)
        XCTAssertEqual(try numericValue(viewModel.streams[0].temperatureText), 293.15, accuracy: 1e-12)
        XCTAssertEqual(viewModel.streams[1].name, "Stream 2")

        viewModel.loadBuiltInCase(aramis, into: streamB)

        XCTAssertEqual(viewModel.streams[0].name, "Porthos pipeline specification example")
        XCTAssertEqual(viewModel.streams[1].name, "Aramis ship specification example")
        XCTAssertEqual(try numericValue(viewModel.streams[1].pressureText), 16, accuracy: 1e-12)
        XCTAssertEqual(try numericValue(viewModel.streams[1].temperatureText), -25, accuracy: 1e-12)

        viewModel.updateTemperatureText(streamID: streamA, value: "300")
        XCTAssertEqual(viewModel.streams[0].temperatureText, "300")
        XCTAssertEqual(try numericValue(viewModel.streams[1].temperatureText), -25, accuracy: 1e-12)
    }

    @MainActor
    func testMoreTabStateKeepsStableStreamMixingViewModelIdentityAndValues() throws {
        let state = MoreTabState()
        let firstReference = state.streamMixingViewModel
        let streamID = try XCTUnwrap(firstReference.streams.first?.id)

        firstReference.updateStreamName(streamID: streamID, value: "Retained Stream A")
        firstReference.updateFlowText(streamID: streamID, value: "123.45")
        firstReference.changeStreamPressureUnit(streamID: streamID, to: .megapascalAbsolute)
        firstReference.updatePressureText(streamID: streamID, value: "1.75")
        firstReference.updateTemperatureText(streamID: streamID, value: "-12.5")

        let secondReference = state.streamMixingViewModel

        XCTAssertTrue(firstReference === secondReference)
        XCTAssertEqual(secondReference.streams.first?.name, "Retained Stream A")
        XCTAssertEqual(secondReference.streams.first?.flowText, "123.45")
        XCTAssertEqual(secondReference.streams.first?.pressureDisplayUnit, .megapascalAbsolute)
        XCTAssertEqual(secondReference.streams.first?.pressureText, "1.75")
        XCTAssertEqual(secondReference.streams.first?.temperatureText, "-12.5")
    }

    @MainActor
    func testPhaseMapMarkerStylesKeepDenseSupercriticalAndFailedDistinct() {
        let dense = PhaseMapMarkerStyle.style(for: .dense)
        let supercritical = PhaseMapMarkerStyle.style(for: .supercritical)
        let unknown = PhaseMapMarkerStyle.style(for: .unknown)
        let failed = PhaseMapMarkerStyle.failed

        XCTAssertEqual(dense.systemImage, "diamond.fill")
        XCTAssertEqual(supercritical.systemImage, "triangle.fill")
        XCTAssertEqual(unknown.systemImage, "questionmark.diamond")
        XCTAssertNotEqual(dense.systemImage, supercritical.systemImage)
        XCTAssertNotEqual(unknown.systemImage, failed.systemImage)
        XCTAssertTrue(dense.accessibilityDescription.contains("Dense"))
        XCTAssertTrue(supercritical.accessibilityDescription.contains("Supercritical"))
        XCTAssertTrue(unknown.accessibilityDescription.contains("unknown"))
        XCTAssertEqual(failed.systemImage, "circle.fill")
        XCTAssertTrue(failed.accessibilityDescription.contains("failed"))
        XCTAssertFalse(failed.accessibilityDescription.contains("unknown"))
    }

    @MainActor
    func testPhaseMapOperatingPointRenderingKeepsUnderlyingMarkerAndRedRing() {
        let plan = PhaseMapOperatingPointRenderingPlan.standard

        XCTAssertTrue(plan.drawsUnderlyingClassificationMarker)
        XCTAssertTrue(plan.drawsRedRingOverlay)
        XCTAssertTrue(plan.ringDrawsAfterClassificationMarker)
    }

    @MainActor
    func testComparisonComputesDifferencesInDisplayedEngineeringUnits() async throws {
        let reference = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: 900,
            viscosityPascalSeconds: 0.00009
        )
        let compared = try await makeComparisonRecord(
            pressureBar: 120,
            temperatureCelsius: -20,
            density: 1_000,
            viscosityPascalSeconds: 0.00012
        )

        let comparison = CalculationComparison(
            reference: reference,
            compared: compared
        )
        let density = try XCTUnwrap(
            comparison.properties.first { $0.id == .density }
        )
        let viscosity = try XCTUnwrap(
            comparison.properties.first { $0.id == .dynamicViscosity }
        )

        XCTAssertEqual(comparison.pressureDifferenceBar, -30, accuracy: 1e-12)
        XCTAssertEqual(comparison.temperatureDifferenceCelsius, -40, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(density.difference), 100, accuracy: 1e-12)
        XCTAssertEqual(density.displayUnit, "kg/m³")
        XCTAssertEqual(try XCTUnwrap(viscosity.difference), 0.03, accuracy: 1e-12)
        XCTAssertEqual(viscosity.displayUnit, "mPa·s")
    }

    @MainActor
    func testComparisonDoesNotCreateDifferenceForUnavailableValue() async throws {
        let reference = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: 900,
            viscosityPascalSeconds: 0.00009
        )
        let compared = try await makeComparisonRecord(
            pressureBar: 150,
            temperatureCelsius: 20,
            density: nil,
            viscosityPascalSeconds: 0.00009
        )

        let comparison = CalculationComparison(
            reference: reference,
            compared: compared
        )
        let density = try XCTUnwrap(
            comparison.properties.first { $0.id == .density }
        )

        XCTAssertNil(density.difference)
        XCTAssertTrue(comparison.nonComparableProperties.contains(density))
    }

    @MainActor
    private func makeRecord() async throws -> CalculationRecord {
        try await makeRecord(composition: [.init(component: .carbonDioxide, moleFraction: 1)])
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for condition.")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func numericValue(_ text: String) throws -> Double {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: text) {
            return number.doubleValue
        }
        return try XCTUnwrap(Double(text.replacingOccurrences(of: ",", with: ".")))
    }

    @MainActor
    private func makeRecord(
        modelID: String = PhaseXpertTests.testDescriptor.id,
        modelDescriptor: ModelDescriptor = PhaseXpertTests.testDescriptor,
        pressureValue: Double = 150,
        pressureUnit: PressureUnit = .bara,
        pressurePa: Double = 15_000_000,
        temperatureValue: Double = 20,
        temperatureUnit: TemperatureUnit = .celsius,
        temperatureK: Double = 293.15,
        composition: [MixtureComponent]
    ) async throws -> CalculationRecord {
        let request = CalculationRequest(
            modelID: modelID,
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: composition,
            requestedProperties: [.density],
            clientVersion: "test"
        )
        let response = CalculationResponse(
            requestID: request.requestID,
            model: modelDescriptor,
            phase: .dense,
            properties: [
                PropertyValue(
                    property: .density,
                    value: 800,
                    unit: "kg/m³",
                    status: .calculated,
                    message: "Test density."
                )
            ],
            solver: SolverMetadata(
                method: "Test calculation",
                converged: true,
                durationMilliseconds: 1
            ),
            warnings: [],
            isScientificResult: false
        )
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: pressureValue,
                pressureUnit: pressureUnit,
                pressurePa: pressurePa,
                temperatureValue: temperatureValue,
                temperatureUnit: temperatureUnit,
                temperatureK: temperatureK,
                originalComposition: composition.map {
                    .init(
                        component: $0.component,
                        value: $0.moleFraction * 100,
                        unit: .molePercent
                    )
                }
            ),
            response: response,
            application: .init(version: "1.0", build: "1")
        )
    }

    @MainActor
    private func makeComparisonRecord(
        pressureBar: Double,
        temperatureCelsius: Double,
        density: Double?,
        viscosityPascalSeconds: Double
    ) async throws -> CalculationRecord {
        let base = try await makeRecord()
        let request = CalculationRequest(
            modelID: base.response.model.id,
            pressurePa: pressureBar * 100_000,
            temperatureK: temperatureCelsius + 273.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density, .dynamicViscosity],
            clientVersion: "test"
        )
        let response = CalculationResponse(
            requestID: request.requestID,
            model: base.response.model,
            phase: .dense,
            properties: [
                PropertyValue(
                    property: .density,
                    value: density,
                    unit: "kg/m³",
                    status: density == nil ? .unavailable : .calculated
                ),
                PropertyValue(
                    property: .dynamicViscosity,
                    value: viscosityPascalSeconds,
                    unit: "Pa·s",
                    status: .calculated
                )
            ],
            solver: base.response.solver,
            warnings: [],
            isScientificResult: false
        )
        return CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: pressureBar,
                pressureUnit: .bara,
                pressurePa: request.pressurePa,
                temperatureValue: temperatureCelsius,
                temperatureUnit: .celsius,
                temperatureK: request.temperatureK,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 100, unit: .molePercent)
                ]
            ),
            response: response,
            application: base.application
        )
    }

    @MainActor
    private func makeTemporaryDiagramArtifacts(
        in store: PhaseDiagramTemporaryExportStore,
        id: String
    ) throws -> PhaseDiagramExportArtifacts {
        try FileManager.default.createDirectory(
            at: store.directory,
            withIntermediateDirectories: true
        )
        let pdf = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(id).pdf"
        )
        let csv = store.directory.appendingPathComponent(
            "PhaseXpert-Phase-Diagram-\(id).csv"
        )
        try Data("pdf".utf8).write(to: pdf)
        try Data("csv".utf8).write(to: csv)
        return PhaseDiagramExportArtifacts(files: [pdf, csv])
    }

    @MainActor
    func testStreamMixingStartsWithTwoEditableStreams() {
        let viewModel = StreamMixingViewModel()

        XCTAssertEqual(viewModel.streams.count, 2)
        XCTAssertEqual(viewModel.streams[0].name, "Stream 1")
        XCTAssertEqual(viewModel.streams[1].name, "Stream 2")
        XCTAssertTrue(viewModel.canCalculate)
    }

    @MainActor
    func testStreamMixingAddsOnlyUpToSixStreams() {
        let viewModel = StreamMixingViewModel()

        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertNotNil(viewModel.addStream())
        XCTAssertEqual(viewModel.streams.count, 6)
        XCTAssertFalse(viewModel.canAddStream)
        XCTAssertNil(viewModel.addStream())
        XCTAssertEqual(viewModel.streams.count, 6)
    }

    @MainActor
    func testStreamMixingDuplicateUsesNewIdentifierAndCopiesValues() {
        let viewModel = StreamMixingViewModel()
        let source = viewModel.streams[0]

        let duplicateID = viewModel.duplicateStream(id: source.id)

        let duplicate = viewModel.streams.first { $0.id == duplicateID }
        XCTAssertNotNil(duplicateID)
        XCTAssertNotEqual(duplicate?.id, source.id)
        XCTAssertEqual(duplicate?.flowText, source.flowText)
        XCTAssertEqual(duplicate?.flowUnit, source.flowUnit)
        XCTAssertEqual(duplicate?.compositionBasis, source.compositionBasis)
        XCTAssertEqual(duplicate?.composition.map(\.component), source.composition.map(\.component))
        XCTAssertTrue(duplicate?.name.contains("copy") == true)
    }

    @MainActor
    func testStreamMixingRemoveEnforcesTwoStreamMinimum() {
        let viewModel = StreamMixingViewModel()
        _ = viewModel.addStream()
        let removableID = viewModel.streams[2].id

        viewModel.removeStream(id: removableID)
        viewModel.removeStream(id: viewModel.streams[0].id)

        XCTAssertEqual(viewModel.streams.count, 2)
        XCTAssertFalse(viewModel.canRemoveStream)
    }

    @MainActor
    func testStreamMixingReorderPreservesNumericalResult() {
        let viewModel = StreamMixingViewModel()
        viewModel.calculate()
        let first = viewModel.result

        viewModel.moveStreamDown(id: viewModel.streams[0].id)
        XCTAssertTrue(viewModel.isResultStale)
        viewModel.calculate()
        let second = viewModel.result

        XCTAssertEqual(first?.totalMolarFlowMolesPerSecond, second?.totalMolarFlowMolesPerSecond)
        XCTAssertEqual(first?.totalMassFlowKilogramsPerSecond, second?.totalMassFlowKilogramsPerSecond)
        XCTAssertEqual(first?.composition, second?.composition)
        XCTAssertEqual(viewModel.streams[1].name, "Stream 1")
    }

    @MainActor
    func testStreamMixingFlowPressureAndTemperatureUnitsReachCoreRequest() throws {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].flowText = "3600"
        viewModel.streams[0].flowUnit = .kilogramsPerHour
        viewModel.streams[0].pressureText = "12"
        viewModel.streams[0].pressureDisplayUnit = .megapascalAbsolute
        viewModel.streams[0].temperatureText = "68"
        viewModel.streams[0].temperatureDisplayUnit = .fahrenheit
        viewModel.outletPressureText = "1500"
        viewModel.outletPressureDisplayUnit = .psiAbsolute
        viewModel.outletTemperatureText = "298.15"
        viewModel.outletTemperatureDisplayUnit = .kelvin
        viewModel.markInputsChanged()

        let request = try XCTUnwrap(viewModel.request())

        XCTAssertEqual(request.streams[0].flowUnit, .kilogramsPerHour)
        XCTAssertEqual(request.streams[0].flowBasis, .mass)
        XCTAssertEqual(request.streams[0].pressureUnit, .megapascal)
        XCTAssertEqual(request.streams[0].temperatureUnit, .fahrenheit)
        XCTAssertEqual(request.outlet.pressureUnit, .psia)
        XCTAssertEqual(request.outlet.temperatureUnit, .kelvin)
    }

    @MainActor
    func testStreamMixingSuccessfulTwoStreamCalculationDisplaysHandCheckedTotals() {
        let viewModel = StreamMixingViewModel()

        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertEqual(viewModel.result?.totalMolarFlowMolesPerSecond ?? .nan, 15, accuracy: 1e-12)
        let carbonDioxide = viewModel.result?.composition.first {
            $0.component == .carbonDioxide
        }?.moleFraction
        let nitrogen = viewModel.result?.composition.first {
            $0.component == .nitrogen
        }?.moleFraction
        XCTAssertEqual(carbonDioxide ?? .nan, 14.5 / 15, accuracy: 1e-12)
        XCTAssertEqual(nitrogen ?? .nan, 0.5 / 15, accuracy: 1e-12)
    }

    @MainActor
    func testStreamMixingDifferentInletPressuresProduceOneWarning() {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].pressureText = "120"
        viewModel.streams[1].pressureText = "150"
        viewModel.markInputsChanged()

        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.warnings.count, 1)
        XCTAssertEqual(viewModel.result?.warnings.first?.code, .inletPressureDifference)
    }

    @MainActor
    func testStreamMixingValidationAndExplicitNormalization() {
        let viewModel = StreamMixingViewModel()
        viewModel.streams[0].composition = [
            CompositionInput(component: .carbonDioxide, value: "97.05"),
            CompositionInput(component: .nitrogen, value: "3")
        ]
        viewModel.markInputsChanged()

        viewModel.calculate()
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .normalizationRequired
        })

        viewModel.applyExplicitNormalization(for: viewModel.streams[0].id)
        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertEqual(
            viewModel.result?.assumptions.filter {
                $0.code == .explicitCompositionNormalization
            }.count,
            1
        )
    }

    @MainActor
    func testStreamMixingMarksResultStaleAfterInputChange() {
        let viewModel = StreamMixingViewModel()

        viewModel.calculate()
        XCTAssertFalse(viewModel.isResultStale)

        viewModel.updateFlowText(streamID: viewModel.streams[0].id, value: "20")

        XCTAssertTrue(viewModel.isResultStale)
        XCTAssertNotNil(viewModel.result)
    }

    @MainActor
    func testStreamMixingCompositionEditClearsAcceptedNormalizationAndRequiresReviewAgain() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .molePercent,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "97.05"),
                CompositionInput(component: .nitrogen, value: "3")
            ]
        )
        viewModel.calculate()
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(viewModel.canNormalize(streamID: streamID))

        viewModel.applyExplicitNormalization(for: streamID)
        XCTAssertNotNil(viewModel.streams[0].compositionBeforeNormalization)
        XCTAssertNotNil(viewModel.streams[0].normalizedComposition)

        let nitrogenID = viewModel.streams[0].composition.first { $0.component == .nitrogen }?.id
        viewModel.updateCompositionValue(
            streamID: streamID,
            entryID: try XCTUnwrap(nitrogenID),
            value: "3.04"
        )

        XCTAssertNil(viewModel.streams[0].compositionBeforeNormalization)
        XCTAssertNil(viewModel.streams[0].normalizedComposition)
        viewModel.calculate()
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(viewModel.canNormalize(streamID: streamID))
    }

    @MainActor
    func testStreamMixingCompositionMutationsClearAcceptedNormalization() throws {
        func preparedViewModel() -> (StreamMixingViewModel, UUID) {
            let viewModel = StreamMixingViewModel()
            let streamID = viewModel.streams[0].id
            viewModel.replaceComposition(
                streamID: streamID,
                basis: .molePercent,
                composition: [
                    CompositionInput(component: .carbonDioxide, value: "97.05"),
                    CompositionInput(component: .nitrogen, value: "3")
                ]
            )
            viewModel.applyExplicitNormalization(for: streamID)
            XCTAssertNotNil(viewModel.streams[0].normalizedComposition)
            return (viewModel, streamID)
        }

        do {
            let (viewModel, streamID) = preparedViewModel()
            _ = viewModel.addImpurity(to: streamID)
            XCTAssertNil(viewModel.streams[0].normalizedComposition)
        }
        do {
            let (viewModel, streamID) = preparedViewModel()
            let nitrogenID = try XCTUnwrap(viewModel.streams[0].composition.first {
                $0.component == .nitrogen
            }?.id)
            viewModel.updateImpurity(streamID: streamID, entryID: nitrogenID, component: .oxygen)
            XCTAssertNil(viewModel.streams[0].normalizedComposition)
        }
        do {
            let (viewModel, streamID) = preparedViewModel()
            let nitrogenID = try XCTUnwrap(viewModel.streams[0].composition.first {
                $0.component == .nitrogen
            }?.id)
            viewModel.removeImpurity(streamID: streamID, entryID: nitrogenID)
            XCTAssertNil(viewModel.streams[0].normalizedComposition)
        }
        do {
            let (viewModel, streamID) = preparedViewModel()
            viewModel.moveImpurities(streamID: streamID, from: IndexSet(integer: 1), to: 0)
            XCTAssertNil(viewModel.streams[0].normalizedComposition)
        }
        do {
            let (viewModel, streamID) = preparedViewModel()
            viewModel.replaceComposition(
                streamID: streamID,
                basis: .molePercent,
                composition: [
                    CompositionInput(component: .carbonDioxide, value: "96"),
                    CompositionInput(component: .nitrogen, value: "4")
                ]
            )
            XCTAssertNil(viewModel.streams[0].normalizedComposition)
        }
    }

    @MainActor
    func testStreamMixingEditedCompositionIsUsedAfterNormalizationIsCleared() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .molePercent,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "97.05"),
                CompositionInput(component: .nitrogen, value: "3")
            ]
        )
        viewModel.applyExplicitNormalization(for: streamID)

        let carbonDioxideID = viewModel.streams[0].composition.first {
            $0.component == .carbonDioxide
        }?.id
        let nitrogenID = viewModel.streams[0].composition.first { $0.component == .nitrogen }?.id
        viewModel.updateCompositionValue(
            streamID: streamID,
            entryID: try XCTUnwrap(carbonDioxideID),
            value: "96"
        )
        viewModel.updateCompositionValue(
            streamID: streamID,
            entryID: try XCTUnwrap(nitrogenID),
            value: "4"
        )

        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        let nitrogen = viewModel.result?.composition.first {
            $0.component == .nitrogen
        }?.moleFraction
        XCTAssertEqual(nitrogen ?? .nan, 0.4 / 15, accuracy: 1e-12)
        XCTAssertFalse(viewModel.result?.assumptions.contains {
            $0.code == .explicitCompositionNormalization
        } ?? true)
    }

    @MainActor
    func testStreamMixingCompositionBasisChangeClearsNormalizationProvenance() {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .molePercent,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "97.05"),
                CompositionInput(component: .nitrogen, value: "3")
            ]
        )
        viewModel.applyExplicitNormalization(for: streamID)

        viewModel.changeCompositionBasis(streamID: streamID, to: .partsPerMillion)

        XCTAssertNil(viewModel.streams[0].compositionBeforeNormalization)
        XCTAssertNil(viewModel.streams[0].normalizedComposition)
    }

    @MainActor
    func testStreamMixingMassFractionBasisChangePreservesPhysicalComposition() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        let carbonDioxideMolarMass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMolarMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let denominator = 0.25 * carbonDioxideMolarMass + 0.75 * nitrogenMolarMass
        let carbonDioxideMassFraction = 0.25 * carbonDioxideMolarMass / denominator
        let nitrogenMassFraction = 0.75 * nitrogenMolarMass / denominator
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .massFraction,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "\(carbonDioxideMassFraction)"),
                CompositionInput(component: .nitrogen, value: "\(nitrogenMassFraction)")
            ]
        )

        viewModel.changeCompositionBasis(streamID: streamID, to: .molePercent)

        let request = try XCTUnwrap(viewModel.request())
        XCTAssertEqual(
            request.streams[0].composition.first { $0.component == .carbonDioxide }?.moleFraction ?? .nan,
            0.25,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            request.streams[0].composition.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
            0.75,
            accuracy: 1e-12
        )
        XCTAssertEqual(viewModel.streams[0].compositionBasis, .molePercent)
    }

    @MainActor
    func testStreamMixingValidMassFractionChangesToEveryMoleBasis() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        let carbonDioxideMolarMass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMolarMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let denominator = 0.25 * carbonDioxideMolarMass + 0.75 * nitrogenMolarMass
        let carbonDioxideMassFraction = 0.25 * carbonDioxideMolarMass / denominator
        let nitrogenMassFraction = 0.75 * nitrogenMolarMass / denominator

        for basis in [CompositionUnit.moleFraction, .molePercent, .partsPerMillion] {
            viewModel.replaceComposition(
                streamID: streamID,
                basis: .massFraction,
                composition: [
                    CompositionInput(component: .carbonDioxide, value: "\(carbonDioxideMassFraction)"),
                    CompositionInput(component: .nitrogen, value: "\(nitrogenMassFraction)")
                ]
            )
            viewModel.changeCompositionBasis(streamID: streamID, to: basis)

            let request = try XCTUnwrap(viewModel.request())
            XCTAssertEqual(viewModel.streams[0].compositionBasis, basis)
            XCTAssertEqual(
                request.streams[0].composition.first {
                    $0.component == .carbonDioxide
                }?.moleFraction ?? .nan,
                0.25,
                accuracy: 1e-12
            )
            XCTAssertEqual(
                request.streams[0].composition.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
                0.75,
                accuracy: 1e-12
            )
        }
    }

    @MainActor
    func testStreamMixingMoleBasisChangesToMassFractionAndRoundTrips() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .molePercent,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "20"),
                CompositionInput(component: .nitrogen, value: "80")
            ]
        )

        viewModel.changeCompositionBasis(streamID: streamID, to: .massFraction)
        XCTAssertEqual(viewModel.streams[0].compositionBasis, .massFraction)
        viewModel.changeCompositionBasis(streamID: streamID, to: .moleFraction)

        let request = try XCTUnwrap(viewModel.request())
        XCTAssertEqual(
            request.streams[0].composition.first { $0.component == .carbonDioxide }?.moleFraction ?? .nan,
            0.2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            request.streams[0].composition.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
            0.8,
            accuracy: 1e-12
        )
    }

    @MainActor
    func testStreamMixingNearMassFractionBasisChangeRequiresNormalizationAcceptance() {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        let original = [
            CompositionInput(component: .carbonDioxide, value: "0.5002"),
            CompositionInput(component: .nitrogen, value: "0.5002")
        ]
        viewModel.replaceComposition(streamID: streamID, basis: .massFraction, composition: original)

        viewModel.changeCompositionBasis(streamID: streamID, to: .molePercent)

        XCTAssertEqual(viewModel.streams[0].compositionBasis, .massFraction)
        XCTAssertEqual(viewModel.streams[0].composition, original)
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .normalizationRequired && $0.field == .composition
        })
    }

    @MainActor
    func testStreamMixingNearMassFractionConvertsAfterExplicitNormalization() {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .massFraction,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "0.5002"),
                CompositionInput(component: .nitrogen, value: "0.5002")
            ]
        )
        viewModel.calculate()
        XCTAssertNil(viewModel.result)
        XCTAssertTrue(viewModel.canNormalize(streamID: streamID))

        viewModel.applyExplicitNormalization(for: streamID)
        viewModel.changeCompositionBasis(streamID: streamID, to: .molePercent)

        XCTAssertEqual(viewModel.streams[0].compositionBasis, .molePercent)
        XCTAssertNil(viewModel.streams[0].normalizedComposition)
        XCTAssertNil(viewModel.streams[0].compositionBeforeNormalization)
    }

    @MainActor
    func testStreamMixingInvalidMassFractionBasisChangePreservesVisibleInputs() {
        let cases: [[CompositionInput]] = [
            [
                CompositionInput(component: .carbonDioxide, value: "0.6"),
                CompositionInput(component: .nitrogen, value: "0.6")
            ],
            [
                CompositionInput(component: .carbonDioxide, value: "0"),
                CompositionInput(component: .nitrogen, value: "0")
            ],
            [
                CompositionInput(component: .carbonDioxide, value: "0.99"),
                CompositionInput(component: .helium, value: "0.01")
            ]
        ]

        for original in cases {
            let viewModel = StreamMixingViewModel()
            let streamID = viewModel.streams[0].id
            viewModel.replaceComposition(streamID: streamID, basis: .massFraction, composition: original)

            viewModel.changeCompositionBasis(streamID: streamID, to: .molePercent)

            XCTAssertEqual(viewModel.streams[0].compositionBasis, .massFraction)
            XCTAssertEqual(viewModel.streams[0].composition, original)
            XCTAssertFalse(viewModel.validationReport.canCalculate)
        }
    }

    @MainActor
    func testStreamMixingPressureAndTemperatureUnitChangesPreserveCanonicalValues() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.updatePressureText(streamID: streamID, value: "120")
        viewModel.updateTemperatureText(streamID: streamID, value: "25")
        viewModel.updateOutletPressureText("120")
        viewModel.updateOutletTemperatureText("25")

        viewModel.changeStreamPressureUnit(streamID: streamID, to: .psiAbsolute)
        viewModel.changeStreamTemperatureUnit(streamID: streamID, to: .fahrenheit)
        viewModel.changeOutletPressureUnit(to: .megapascalAbsolute)
        viewModel.changeOutletTemperatureUnit(to: .kelvin)

        let request = try XCTUnwrap(viewModel.request())
        XCTAssertEqual(request.streams[0].pressurePa, 12_000_000, accuracy: 0.01)
        XCTAssertEqual(request.streams[0].temperatureK, 298.15, accuracy: 1e-10)
        XCTAssertEqual(request.outlet.pressurePa, 12_000_000, accuracy: 1e-6)
        XCTAssertEqual(request.outlet.temperatureK, 298.15, accuracy: 1e-10)
        XCTAssertEqual(viewModel.streams[0].pressureDisplayUnit, .psiAbsolute)
        XCTAssertEqual(viewModel.streams[0].temperatureDisplayUnit, .fahrenheit)
        XCTAssertEqual(viewModel.outletPressureDisplayUnit, .megapascalAbsolute)
        XCTAssertEqual(viewModel.outletTemperatureDisplayUnit, .kelvin)
    }

    @MainActor
    func testStreamMixingInvalidPressureAndTemperatureUnitChangesDoNotRelabelValues() {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.updatePressureText(streamID: streamID, value: "not a pressure")
        viewModel.changeStreamPressureUnit(streamID: streamID, to: .psiAbsolute)
        XCTAssertEqual(viewModel.streams[0].pressureDisplayUnit, .barAbsolute)
        XCTAssertEqual(viewModel.streams[0].pressureText, "not a pressure")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .invalidPressure && $0.field == .pressure
        })

        viewModel.updateTemperatureText(streamID: streamID, value: "not a temperature")
        viewModel.changeStreamTemperatureUnit(streamID: streamID, to: .fahrenheit)
        XCTAssertEqual(viewModel.streams[0].temperatureDisplayUnit, .celsius)
        XCTAssertEqual(viewModel.streams[0].temperatureText, "not a temperature")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .invalidTemperature && $0.field == .temperature
        })

        viewModel.updateOutletPressureText("not an outlet pressure")
        viewModel.changeOutletPressureUnit(to: .megapascalAbsolute)
        XCTAssertEqual(viewModel.outletPressureDisplayUnit, .barAbsolute)
        XCTAssertEqual(viewModel.outletPressureText, "not an outlet pressure")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .invalidPressure && $0.field == .outletPressure
        })

        viewModel.updateOutletTemperatureText("not an outlet temperature")
        viewModel.changeOutletTemperatureUnit(to: .kelvin)
        XCTAssertEqual(viewModel.outletTemperatureDisplayUnit, .celsius)
        XCTAssertEqual(viewModel.outletTemperatureText, "not an outlet temperature")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .invalidTemperature && $0.field == .outletTemperature
        })
    }

    @MainActor
    func testStreamMixingFlowUnitChangesPreserveCanonicalFlow() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.updateFlowText(streamID: streamID, value: "10")

        viewModel.changeStreamFlowUnit(streamID: streamID, to: .kilomolesPerHour)
        viewModel.calculate()
        var contribution = try XCTUnwrap(viewModel.result?.streamContributions.first {
            $0.streamID == streamID
        })
        XCTAssertEqual(contribution.molarFlowMolesPerSecond, 10, accuracy: 1e-12)
        XCTAssertEqual(Double(viewModel.streams[0].flowText) ?? .nan, 36, accuracy: 1e-12)

        viewModel.changeStreamFlowUnit(streamID: streamID, to: .molesPerSecond)
        viewModel.calculate()
        contribution = try XCTUnwrap(viewModel.result?.streamContributions.first {
            $0.streamID == streamID
        })
        XCTAssertEqual(contribution.molarFlowMolesPerSecond, 10, accuracy: 1e-12)
        XCTAssertEqual(Double(viewModel.streams[0].flowText) ?? .nan, 10, accuracy: 1e-12)
    }

    @MainActor
    func testStreamMixingCrossBasisFlowUnitChangeUsesCompositionMolarMass() throws {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        let carbonDioxideMolarMass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .moleFraction,
            composition: [
                CompositionInput(component: .carbonDioxide, value: "1")
            ]
        )
        viewModel.updateFlowText(streamID: streamID, value: "1")

        viewModel.changeStreamFlowUnit(streamID: streamID, to: .kilogramsPerSecond)
        viewModel.calculate()
        var contribution = try XCTUnwrap(viewModel.result?.streamContributions.first {
            $0.streamID == streamID
        })
        XCTAssertEqual(contribution.massFlowKilogramsPerSecond, carbonDioxideMolarMass, accuracy: 1e-14)
        XCTAssertEqual(Double(viewModel.streams[0].flowText) ?? .nan, carbonDioxideMolarMass, accuracy: 1e-14)

        viewModel.changeStreamFlowUnit(streamID: streamID, to: .molesPerSecond)
        viewModel.calculate()
        contribution = try XCTUnwrap(viewModel.result?.streamContributions.first {
            $0.streamID == streamID
        })
        XCTAssertEqual(contribution.molarFlowMolesPerSecond, 1, accuracy: 1e-12)
        XCTAssertEqual(Double(viewModel.streams[0].flowText) ?? .nan, 1, accuracy: 1e-12)
    }

    @MainActor
    func testStreamMixingFailedCrossBasisFlowConversionDoesNotReinterpretValue() {
        let viewModel = StreamMixingViewModel()
        let streamID = viewModel.streams[0].id
        viewModel.replaceComposition(
            streamID: streamID,
            basis: .moleFraction,
            composition: [
                CompositionInput(component: .helium, value: "1")
            ]
        )
        viewModel.updateFlowText(streamID: streamID, value: "1")

        viewModel.changeStreamFlowUnit(streamID: streamID, to: .kilogramsPerSecond)

        XCTAssertEqual(viewModel.streams[0].flowUnit, .molesPerSecond)
        XCTAssertEqual(viewModel.streams[0].flowText, "1")
        XCTAssertTrue(viewModel.validationReport.issues.contains {
            $0.code == .invalidFlow && $0.field == .flow
        })
    }

    @MainActor
    func testStreamMixingCalculatesWithoutProviderSelectionOrProviderCall() {
        let viewModel = StreamMixingViewModel()
        viewModel.calculate()

        XCTAssertEqual(viewModel.result?.status, .calculated)
        XCTAssertFalse(viewModel.statusMessage.localizedCaseInsensitiveContains("provider"))
        XCTAssertFalse(viewModel.statusMessage.localizedCaseInsensitiveContains("CoolProp"))
    }

    @MainActor
    func testHydrogenTemperatureSuggestionUpdatesGuidanceWithoutChangingPressureInput() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "150"
        viewModel.temperatureText = "0"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            CompositionInput(component: .carbonDioxide, value: "946380"),
            CompositionInput(component: .hydrogen, value: "53620")
        ]
        viewModel.validate()

        let initialGuidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertTrue(initialGuidance.summary.contains {
            $0.title == "Validated pressure" && $0.detail == "5.1–30.4 bar(a)"
        })
        XCTAssertTrue(initialGuidance.currentInputIssues.contains {
            $0.title == "Pressure outside validated range"
        })

        let twentyCelsiusSuggestion = try XCTUnwrap(initialGuidance.suggestions.first {
            $0.label == "20 °C"
        })
        viewModel.applyGuidanceSuggestion(twentyCelsiusSuggestion)

        XCTAssertEqual(viewModel.pressureText, "150")
        XCTAssertEqual(viewModel.temperatureText, "20")
        let updatedGuidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertTrue(updatedGuidance.summary.contains {
            $0.title == "Validated pressure" && $0.detail == "5.0–49.8 bar(a)"
        })
        XCTAssertTrue(updatedGuidance.currentInputIssues.contains {
            $0.title == "Pressure outside validated range"
                && $0.detail.contains("150.0 bar(a)")
        })
    }

    @MainActor
    func testCalculatorResetRestoresCleanDefaultsAndClearsResultState() async {
        let viewModel = CalculatorViewModel()
        viewModel.pressureText = "42"
        viewModel.temperatureText = "80"
        viewModel.composition.append(
            CompositionInput(component: .nitrogen, value: "1000")
        )
        viewModel.validate()

        viewModel.reset()

        XCTAssertEqual(viewModel.pressureText, "50")
        XCTAssertEqual(viewModel.temperatureText, "20")
        XCTAssertEqual(viewModel.pressureDisplayUnit, .barAbsolute)
        XCTAssertEqual(viewModel.temperatureDisplayUnit, .celsius)
        XCTAssertEqual(viewModel.selectedModelID, "coolprop-heos")
        XCTAssertEqual(viewModel.compositionBasis, .partsPerMillion)
        XCTAssertEqual(viewModel.composition.count, 1)
        XCTAssertEqual(viewModel.composition.first?.component, .carbonDioxide)
        XCTAssertEqual(viewModel.composition.first?.value, "1000000")
        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNil(viewModel.calculationError)
        XCTAssertTrue(viewModel.validationReport.canCalculate)
    }

    @MainActor
    func testValidatedCompositionOptionsComeFromProductionCapabilityMetadata() throws {
        let options = AdvancedValidationPresentation.compositionOptions()
        XCTAssertGreaterThan(options.count, 1)

        let oxygen = try XCTUnwrap(options.first { option in
            option.composition.contains {
                $0.component == .oxygen && abs($0.moleFraction - 0.0652) < 1e-12
            }
        })
        XCTAssertEqual(Set(oxygen.composition.map(\.component)), [.carbonDioxide, .oxygen])
        XCTAssertEqual(
            try XCTUnwrap(oxygen.composition.first(where: { $0.component == .carbonDioxide })).moleFraction,
            0.9348,
            accuracy: 1e-12
        )
        XCTAssertTrue(oxygen.properties.contains(.speedOfSound))
    }

    @MainActor
    func testUseValidatedCompositionDoesNotChangePressureOrTemperature() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "300"
        viewModel.temperatureText = "28"
        viewModel.compositionBasis = .molePercent
        let option = try XCTUnwrap(viewModel.validatedCompositionOptions.first { option in
            option.composition.contains {
                $0.component == .oxygen && abs($0.moleFraction - 0.0652) < 1e-12
            }
        })

        viewModel.useValidatedComposition(option)

        XCTAssertEqual(viewModel.pressureText, "300")
        XCTAssertEqual(viewModel.temperatureText, "28")
        XCTAssertEqual(
            viewModel.composition.first(where: { $0.component == .oxygen })?.value,
            "6.52"
        )
        XCTAssertEqual(viewModel.validatedPropertiesAtCurrentState, [.speedOfSound])
    }

    @MainActor
    func testValidationDetailsAreAvailableForOutOfRangeNitrogenState() throws {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "40"
        viewModel.temperatureText = "20"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "98.73"),
            .init(component: .nitrogen, value: "1.27")
        ]
        viewModel.validate()

        let guidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
        XCTAssertFalse(guidance.isEmpty)
        XCTAssertTrue(guidance.summary.contains { $0.title == "N₂ validated composition" })
        XCTAssertTrue(guidance.summary.contains { $0.title == "Validated temperature" })
        XCTAssertTrue(guidance.summary.contains { $0.title == "Validated pressure" })
        XCTAssertTrue(guidance.currentInputIssues.contains {
            $0.title == "Temperature outside validated range"
        })
        XCTAssertTrue(viewModel.validatedPropertiesAtCurrentState.isEmpty)
        XCTAssertFalse(viewModel.scientificShieldIsActive)
    }

    @MainActor
    func testValidatedStateOptionProducesInGateNitrogenState() throws {
        let formulation = TeqpFormulationCatalog.co2NitrogenGernertGasDensity
        let capability = try XCTUnwrap(
            formulation.propertyCapabilities.first { $0.property == .density }
        )
        let limit = try XCTUnwrap(capability.isothermPressureLimits.first)
        let nitrogenLimit = try XCTUnwrap(
            capability.compositionLimits.first { $0.component == ComponentID.nitrogen }
        )
        let composition: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 1 - nitrogenLimit.minimumMoleFraction),
            .init(component: .nitrogen, moleFraction: nitrogenLimit.minimumMoleFraction)
        ]

        XCTAssertTrue((limit.minimumPressurePa...limit.maximumPressurePa).contains(4_000_000))
        XCTAssertEqual(limit.temperatureK, 283.15)
        XCTAssertEqual(nitrogenLimit.minimumMoleFraction, 0.0127, accuracy: 1e-12)
        XCTAssertEqual(
            Set(AdvancedValidationPresentation.validatedProperties(
                composition: composition,
                pressurePa: 4_000_000,
                temperatureK: limit.temperatureK
            )),
            [.density, .molarMass, .specificVolume, .compressibilityFactor]
        )
    }

    @MainActor
    func testHydrogenSulfideValidatedStateMapsDensityDerivedPropertiesOnly() throws {
        let composition: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.9505),
            .init(component: .hydrogenSulfide, moleFraction: 0.0495)
        ]

        let validated = Set(AdvancedValidationPresentation.validatedProperties(
            composition: composition,
            pressurePa: 2_000_000,
            temperatureK: 272.55
        ))

        XCTAssertEqual(validated, [
            .density,
            .molarMass,
            .specificVolume,
            .compressibilityFactor
        ])
        XCTAssertFalse(validated.contains(.vapourFraction))
        XCTAssertFalse(validated.contains(.speedOfSound))
        XCTAssertFalse(validated.contains(.dynamicViscosity))
        XCTAssertFalse(validated.contains(.thermalConductivity))
        XCTAssertFalse(validated.contains(.isobaricHeatCapacity))
        XCTAssertFalse(validated.contains(.isochoricHeatCapacity))

        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "20"
        viewModel.temperatureText = "-0.6"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "95.05"),
            .init(component: .hydrogenSulfide, value: "4.95")
        ]
        viewModel.validate()

        XCTAssertEqual(Set(viewModel.validatedPropertiesAtCurrentState), validated)
        XCTAssertTrue(viewModel.scientificShieldIsActive)
        XCTAssertTrue(viewModel.operatingRangeGuidance?.summary.contains {
            $0.detail.localizedCaseInsensitiveContains("H₂S")
        } == true)
    }

    @MainActor
    func testOxygenAcousticGateDoesNotValidateDensityPresentation() throws {
        let composition: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.9348),
            .init(component: .oxygen, moleFraction: 0.0652)
        ]

        let validated = Set(AdvancedValidationPresentation.validatedProperties(
            composition: composition,
            pressurePa: 30_000_000,
            temperatureK: 301.15
        ))

        XCTAssertEqual(validated, [.speedOfSound])
        XCTAssertFalse(validated.contains(.density))

        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.pressureText = "300"
        viewModel.temperatureText = "28"
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "93.48"),
            .init(component: .oxygen, value: "6.52")
        ]
        viewModel.validate()

        XCTAssertEqual(viewModel.validatedPropertiesAtCurrentState, [.speedOfSound])
        XCTAssertTrue(viewModel.scientificShieldIsActive)
        XCTAssertTrue(viewModel.operatingRangeGuidance?.summary.contains {
            $0.title == "Speed of sound validated"
        } == true)
    }

    @MainActor
    func testMulticomponentValidatedStatesActivateScientificShield() throws {
        let validatedCompositions: [[MixtureComponent]] = [
            [
                .init(component: .carbonDioxide, moleFraction: 0.950),
                .init(component: .methane, moleFraction: 0.033),
                .init(component: .hydrogen, moleFraction: 0.017)
            ],
            [
                .init(component: .carbonDioxide, moleFraction: 0.942),
                .init(component: .nitrogen, moleFraction: 0.023),
                .init(component: .methane, moleFraction: 0.022),
                .init(component: .hydrogen, moleFraction: 0.013)
            ],
            [
                .init(component: .carbonDioxide, moleFraction: 0.920),
                .init(component: .nitrogen, moleFraction: 0.043),
                .init(component: .oxygen, moleFraction: 0.016),
                .init(component: .argon, moleFraction: 0.021)
            ],
            [
                .init(component: .carbonDioxide, moleFraction: 0.952),
                .init(component: .nitrogen, moleFraction: 0.028),
                .init(component: .argon, moleFraction: 0.005),
                .init(component: .methane, moleFraction: 0.010),
                .init(component: .hydrogen, moleFraction: 0.005)
            ]
        ]

        for composition in validatedCompositions {
            let option = try validatedStateOption(matching: composition, property: .density)
            let viewModel = advancedViewModel()
            viewModel.useValidatedState(option)

            XCTAssertEqual(
                Set(viewModel.validatedPropertiesAtCurrentState),
                [.density, .molarMass, .specificVolume, .compressibilityFactor]
            )
            XCTAssertTrue(viewModel.scientificShieldIsActive)
        }
    }

    @MainActor
    func testOxygenValidatedStateOptionsAreCapabilityLabelledAndInGate() throws {
        let viewModel = advancedViewModel()
        viewModel.compositionBasis = .molePercent
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "95"),
            .init(component: .oxygen, value: "5")
        ]
        viewModel.validate()

        XCTAssertTrue(viewModel.validatedCompositionOptions.isEmpty)
        let options = viewModel.validatedStateOptions
        XCTAssertTrue(options.contains { $0.name.localizedCaseInsensitiveContains("density") })
        XCTAssertTrue(options.contains { $0.name.localizedCaseInsensitiveContains("speed of sound") })

        let density = try XCTUnwrap(options.first {
            $0.properties == [.density, .molarMass, .specificVolume, .compressibilityFactor]
        })
        viewModel.useValidatedState(density)
        XCTAssertEqual(
            Set(viewModel.validatedPropertiesAtCurrentState),
            [.density, .molarMass, .specificVolume, .compressibilityFactor]
        )

        let acoustic = try XCTUnwrap(advancedViewModel().validatedStateOptions.first {
            $0.name.localizedCaseInsensitiveContains("speed of sound")
                && $0.composition.contains {
                    $0.component == .oxygen && abs($0.moleFraction - 0.0652) < 1e-12
                }
        })
        let acousticViewModel = advancedViewModel()
        acousticViewModel.useValidatedState(acoustic)
        XCTAssertEqual(acousticViewModel.validatedPropertiesAtCurrentState, [.speedOfSound])
        XCTAssertTrue(acousticViewModel.scientificShieldIsActive)
    }

    @MainActor
    func testValidatedPropertyOrderIsStable() {
        XCTAssertEqual(
            AdvancedValidationPresentation.propertyList([
                .density,
                .molarMass,
                .compressibilityFactor,
                .specificVolume
            ]),
            "Density · M · v · Z"
        )
        XCTAssertEqual(
            AdvancedValidationPresentation.propertyList([.speedOfSound]),
            "Speed of sound"
        )
    }

    @MainActor
    func testCalculationResultClearsWhenProviderOrPhysicalInputsChange() async throws {
        let viewModel = try await calculatedTestViewModel()
        XCTAssertNotNil(viewModel.calculationRecord)

        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        XCTAssertNil(viewModel.calculationRecord)

        let pressureViewModel = try await calculatedTestViewModel()
        pressureViewModel.pressureText = "51"
        XCTAssertNil(pressureViewModel.calculationRecord)

        let temperatureViewModel = try await calculatedTestViewModel()
        temperatureViewModel.temperatureText = "21"
        XCTAssertNil(temperatureViewModel.calculationRecord)

        let compositionViewModel = try await calculatedTestViewModel()
        compositionViewModel.composition = [
            .init(component: .carbonDioxide, value: "999000"),
            .init(component: .nitrogen, value: "1000")
        ]
        XCTAssertNil(compositionViewModel.calculationRecord)
    }

    @MainActor
    func testValidatedActionsAndCaseLoadClearExistingCalculationResult() async throws {
        let validatedStateViewModel = try await calculatedTestViewModel()
        let nitrogenState = try validatedStateOption(
            matching: [
                .init(component: .carbonDioxide, moleFraction: 0.9873),
                .init(component: .nitrogen, moleFraction: 0.0127)
            ],
            property: .density
        )
        validatedStateViewModel.selectedModelID = "teqp-pure-co2-experimental"
        validatedStateViewModel.useValidatedState(nitrogenState)
        XCTAssertNil(validatedStateViewModel.calculationRecord)

        let compositionViewModel = try await calculatedTestViewModel()
        compositionViewModel.selectedModelID = "teqp-pure-co2-experimental"
        compositionViewModel.compositionBasis = .molePercent
        compositionViewModel.composition = [
            .init(component: .carbonDioxide, value: "99"),
            .init(component: .nitrogen, value: "1")
        ]
        let compositionOption = try XCTUnwrap(compositionViewModel.validatedCompositionOptions.first)
        compositionViewModel.useValidatedComposition(compositionOption)
        XCTAssertNil(compositionViewModel.calculationRecord)

        let caseViewModel = try await calculatedTestViewModel()
        let caseRecord = try await makeRecord(
            modelID: "teqp-pure-co2-experimental",
            modelDescriptor: try XCTUnwrap(
                ProviderRegistry().descriptors.first { $0.id == "teqp-pure-co2-experimental" }
            ),
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9873),
                .init(component: .nitrogen, moleFraction: 0.0127)
            ]
        )
        caseViewModel.loadInputs(from: caseRecord)
        XCTAssertNil(caseViewModel.calculationRecord)
    }

    @MainActor
    func testDisplayOnlyUnitChangesPreserveCurrentCalculationResult() async throws {
        let viewModel = try await calculatedTestViewModel()
        let recordID = try XCTUnwrap(viewModel.calculationRecord?.id)

        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)
        viewModel.changeTemperatureDisplayUnit(to: .kelvin)
        viewModel.changeCompositionBasis(to: .molePercent)

        XCTAssertEqual(viewModel.calculationRecord?.id, recordID)
    }

    @MainActor
    func testNorthernLightsProviderSwitchClearsOldGeneralResult() async throws {
        let viewModel = try await calculatedTestViewModel()
        XCTAssertNotNil(viewModel.calculationRecord)

        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.validate()

        XCTAssertNil(viewModel.calculationRecord)
        XCTAssertNotNil(viewModel.operatingRangeGuidance)

        viewModel.selectedModelID = PhaseXpertTests.testDescriptor.id
        XCTAssertNil(viewModel.calculationRecord)
    }

    @MainActor
    func testHydrogenDiscreteIsothermsKeepValidationCardAndShieldConsistent() throws {
        let states = try productionPresentationStates().filter {
            $0.formulationID == TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id
        }
        XCTAssertEqual(states.map(\.temperatureK).sorted(), [273.15, 293.15, 323.15])

        for state in states {
            let viewModel = advancedViewModel(for: state)
            assertPresentation(
                viewModel: viewModel,
                state: state,
                expected: [
                    .density,
                    .molarMass,
                    .specificVolume,
                    .compressibilityFactor
                ]
            )
        }

        let invalid = advancedViewModel(
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.94638),
                .init(component: .hydrogen, moleFraction: 0.05362)
            ],
            pressurePa: 2_000_000,
            temperatureK: 313.15
        )
        XCTAssertFalse(invalid.scientificShieldIsActive)
        XCTAssertTrue(invalid.validatedPropertiesAtCurrentState.isEmpty)
    }

    @MainActor
    func testProductionCapabilityPresentationMatrixMatchesCurrentStateSnapshot() throws {
        let states = try productionPresentationStates()
        XCTAssertEqual(states.count, 27)

        for state in states {
            let viewModel = advancedViewModel(for: state)
            assertPresentation(
                viewModel: viewModel,
                state: state,
                expected: expectedValidatedProperties(for: state)
            )
        }
    }

    @MainActor
    func testRazmjooProductionGatesKeepMatrixGuidanceAndPresentationConsistent() throws {
        let states = try productionPresentationStates().filter {
            $0.formulationID.contains("razmjoo2026")
        }
        XCTAssertEqual(states.count, 7)
        let matrix = AdvancedCCSCapabilityMatrix()

        for state in states {
            let canonical = try CanonicalComposition(state.composition)
            let expected = expectedValidatedProperties(for: state)
            XCTAssertEqual(
                Set(expected),
                [.density, .molarMass, .specificVolume, .compressibilityFactor]
            )
            for property in expected {
                XCTAssertTrue(matrix.decision(
                    for: canonical,
                    property: property,
                    pressurePa: state.pressurePa,
                    temperatureK: state.temperatureK
                ).isSupported)
            }
            XCTAssertFalse(matrix.decision(
                for: canonical,
                property: .speedOfSound,
                pressurePa: state.pressurePa,
                temperatureK: state.temperatureK
            ).isSupported)

            let viewModel = advancedViewModel(for: state)
            assertPresentation(viewModel: viewModel, state: state, expected: expected)
            let guidance = try XCTUnwrap(viewModel.operatingRangeGuidance)
            XCTAssertTrue(guidance.currentInputIssues.isEmpty)
            XCTAssertTrue(guidance.propertyAvailability.contains {
                $0.severity == .unsupported && $0.title == "Cp/Cv/speed"
            })
            XCTAssertTrue(guidance.phaseDiagram.contains {
                $0.severity == .unsupported
            })
        }
    }

    @MainActor
    func testProductionCapabilityOutsidePressureBranchesDoNotValidateThatGate() throws {
        let states = try productionPresentationStates()
        XCTAssertEqual(states.count * 2, 54)

        for state in states {
            let below = advancedViewModel(
                composition: state.composition,
                pressurePa: state.minimumPressurePa - 1,
                temperatureK: state.temperatureK
            )
            XCTAssertFalse(
                below.validatedPropertiesAtCurrentState.contains(state.capabilityProperty),
                state.failureMessage(
                    expected: [],
                    actual: below.validatedPropertiesAtCurrentState,
                    shield: below.scientificShieldIsActive
                )
            )

            let above = advancedViewModel(
                composition: state.composition,
                pressurePa: state.maximumPressurePa + 1,
                temperatureK: state.temperatureK
            )
            XCTAssertFalse(
                above.validatedPropertiesAtCurrentState.contains(state.capabilityProperty),
                state.failureMessage(
                    expected: [],
                    actual: above.validatedPropertiesAtCurrentState,
                    shield: above.scientificShieldIsActive
                )
            )
        }
    }

    @MainActor
    func testValidatedStateOptionsLandInsideClaimedProductionGates() throws {
        let options = AdvancedValidationPresentation.stateOptions(
            currentPressurePa: nil,
            currentTemperatureK: nil
        )
        XCTAssertEqual(options.count, 10)

        for option in options {
            let actual = AdvancedValidationPresentation.validatedProperties(
                composition: option.composition,
                pressurePa: option.pressurePa,
                temperatureK: option.temperatureK
            )
            XCTAssertEqual(
                Set(actual),
                Set(option.properties),
                "Validated-state option \(option.id) \(option.name) \(option.detail) expected \(option.properties.map(\.rawValue)) actual \(actual.map(\.rawValue))"
            )
        }

        let oxygenDensity = try XCTUnwrap(options.first {
            $0.composition.contains {
                $0.component == .oxygen && abs($0.moleFraction - 0.05032089) < 1e-12
            }
        })
        XCTAssertEqual(
            Set(oxygenDensity.properties),
            [.density, .molarMass, .specificVolume, .compressibilityFactor]
        )

        let oxygenAcoustic = try XCTUnwrap(options.first {
            $0.composition.contains {
                $0.component == .oxygen && abs($0.moleFraction - 0.0652) < 1e-12
            }
        })
        XCTAssertEqual(oxygenAcoustic.properties, [.speedOfSound])
    }

    @MainActor
    func testAdvancedValidationMembershipIsInvariantUnderDisplayUnitConversions() throws {
        let hydrogen = try XCTUnwrap(
            productionPresentationStates().first {
                $0.formulationID == TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id
                    && abs($0.temperatureK - 323.15) < 1e-12
            }
        )
        let viewModel = advancedViewModel(for: hydrogen)
        let expected = viewModel.validatedPropertiesAtCurrentState
        XCTAssertFalse(expected.isEmpty)
        XCTAssertTrue(viewModel.scientificShieldIsActive)

        viewModel.changeTemperatureDisplayUnit(to: .kelvin)
        viewModel.changePressureDisplayUnit(to: .megapascalAbsolute)
        viewModel.changeCompositionBasis(to: .partsPerMillion)

        XCTAssertEqual(viewModel.validatedPropertiesAtCurrentState, expected)
        XCTAssertTrue(viewModel.scientificShieldIsActive)
    }

    @MainActor
    func testSavedCaseValidationStatusUsesCurrentCapabilityDecision() async throws {
        let descriptor = try XCTUnwrap(
            ProviderRegistry().descriptors.first { $0.id == "teqp-pure-co2-experimental" }
        )
        let record = try await makeRecord(
            modelID: descriptor.id,
            modelDescriptor: descriptor,
            pressureValue: 300,
            pressureUnit: .bara,
            pressurePa: 30_000_000,
            temperatureValue: 28,
            temperatureUnit: .celsius,
            temperatureK: 301.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9348),
                .init(component: .oxygen, moleFraction: 0.0652)
            ]
        )

        XCTAssertEqual(
            AdvancedValidationPresentation.savedCaseStatus(for: record),
            "Advanced CCS · Validated Speed of sound"
        )
    }

    @MainActor
    private func advancedViewModel() -> CalculatorViewModel {
        let viewModel = CalculatorViewModel()
        viewModel.selectedModelID = "teqp-pure-co2-experimental"
        viewModel.compositionBasis = .molePercent
        return viewModel
    }

    @MainActor
    private func advancedViewModel(for state: ProductionPresentationState) -> CalculatorViewModel {
        advancedViewModel(
            composition: state.composition,
            pressurePa: state.pressurePa,
            temperatureK: state.temperatureK
        )
    }

    @MainActor
    private func advancedViewModel(
        composition: [MixtureComponent],
        pressurePa: Double,
        temperatureK: Double
    ) -> CalculatorViewModel {
        let viewModel = advancedViewModel()
        viewModel.pressureText = String(format: "%.12g", pressurePa / 100_000)
        viewModel.temperatureText = String(format: "%.12g", temperatureK - 273.15)
        viewModel.compositionBasis = .molePercent
        viewModel.composition = composition
            .sorted { lhs, rhs in
                if lhs.component == .carbonDioxide { return true }
                if rhs.component == .carbonDioxide { return false }
                return lhs.component.rawValue < rhs.component.rawValue
            }
            .map {
                .init(
                    component: $0.component,
                    value: String(format: "%.12g", $0.moleFraction * 100)
                )
            }
        viewModel.validate()
        return viewModel
    }

    private struct ProductionPresentationState {
        let formulationID: String
        let capabilityProperty: PropertyID
        let composition: [MixtureComponent]
        let temperatureK: Double
        let pressurePa: Double
        let minimumPressurePa: Double
        let maximumPressurePa: Double

        func failureMessage(
            expected: [PropertyID],
            actual: [PropertyID],
            shield: Bool
        ) -> String {
            let compositionText = composition
                .map { "\($0.component.symbol)=\($0.moleFraction)" }
                .joined(separator: ", ")
            return "\(formulationID)|\(capabilityProperty.rawValue) [\(compositionText)] T \(temperatureK) K P \(pressurePa) Pa expected \(expected.map(\.rawValue)) actual \(actual.map(\.rawValue)) shield \(shield)"
        }
    }

    private func productionPresentationStates() throws -> [ProductionPresentationState] {
        try TeqpFormulationCatalog.productionFormulations
            .filter { $0.components.count > 1 }
            .flatMap { formulation in
                try formulation.propertyCapabilities.flatMap { capability in
                    let composition = try exactComposition(
                        formulation: formulation,
                        capability: capability
                    )
                    return capability.isothermPressureLimits.map { limit in
                        ProductionPresentationState(
                            formulationID: formulation.id,
                            capabilityProperty: capability.property,
                            composition: composition,
                            temperatureK: limit.temperatureK,
                            pressurePa: (limit.minimumPressurePa + limit.maximumPressurePa) / 2,
                            minimumPressurePa: limit.minimumPressurePa,
                            maximumPressurePa: limit.maximumPressurePa
                        )
                    }
                }
            }
    }

    private func exactComposition(
        formulation: TeqpFormulation,
        capability: TeqpPropertyCapability
    ) throws -> [MixtureComponent] {
        var composition = capability.compositionLimits.map {
            MixtureComponent(component: $0.component, moleFraction: $0.minimumMoleFraction)
        }
        if formulation.components.contains(.carbonDioxide),
           !composition.contains(where: { $0.component == .carbonDioxide }) {
            let remainder = 1 - composition.reduce(0) { $0 + $1.moleFraction }
            composition.append(.init(component: .carbonDioxide, moleFraction: remainder))
        }
        _ = try CanonicalComposition(composition)
        return composition
    }

    @MainActor
    private func assertPresentation(
        viewModel: CalculatorViewModel,
        state: ProductionPresentationState,
        expected: [PropertyID]
    ) {
        let actual = viewModel.validatedPropertiesAtCurrentState
        XCTAssertEqual(
            Set(actual),
            Set(expected),
            state.failureMessage(
                expected: expected,
                actual: actual,
                shield: viewModel.scientificShieldIsActive
            )
        )
        XCTAssertFalse(expected.isEmpty)
        XCTAssertTrue(
            viewModel.scientificShieldIsActive,
            state.failureMessage(
                expected: expected,
                actual: actual,
                shield: viewModel.scientificShieldIsActive
            )
        )
        XCTAssertFalse(
            viewModel.operatingRangeGuidance?.currentInputIssues.contains {
                $0.severity == .unsupported
            } ?? true,
            state.failureMessage(
                expected: expected,
                actual: actual,
                shield: viewModel.scientificShieldIsActive
            )
        )
    }

    @MainActor
    private func expectedValidatedProperties(
        for state: ProductionPresentationState
    ) -> [PropertyID] {
        AdvancedValidationPresentation.validatedProperties(
            composition: state.composition,
            pressurePa: state.pressurePa,
            temperatureK: state.temperatureK
        )
    }

    @MainActor
    private func validatedStateOption(
        matching composition: [MixtureComponent],
        property: PropertyID
    ) throws -> ValidatedStateOption {
        try XCTUnwrap(
            AdvancedValidationPresentation.stateOptions(
                currentPressurePa: nil,
                currentTemperatureK: nil
            ).first { option in
                option.properties.contains(property)
                    && sameComposition(option.composition, composition)
            }
        )
    }

    private func sameComposition(
        _ lhs: [MixtureComponent],
        _ rhs: [MixtureComponent]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = lhs.sorted { $0.component.rawValue < $1.component.rawValue }
        let right = rhs.sorted { $0.component.rawValue < $1.component.rawValue }
        return zip(left, right).allSatisfy { leftComponent, rightComponent in
            leftComponent.component == rightComponent.component
                && abs(leftComponent.moleFraction - rightComponent.moleFraction) < 1e-12
        }
    }

    @MainActor
    private func calculatedTestViewModel() async throws -> CalculatorViewModel {
        let provider = TestCalculationProvider()
        let viewModel = CalculatorViewModel(
            registry: ProviderRegistry(providers: [provider])
        )
        viewModel.selectedModelID = provider.descriptor.id
        viewModel.pressureText = "50"
        viewModel.temperatureText = "20"
        viewModel.compositionBasis = .partsPerMillion
        viewModel.composition = [
            .init(component: .carbonDioxide, value: "1000000")
        ]
        viewModel.validate()
        await viewModel.calculate()
        XCTAssertNotNil(viewModel.calculationRecord)
        return viewModel
    }
}

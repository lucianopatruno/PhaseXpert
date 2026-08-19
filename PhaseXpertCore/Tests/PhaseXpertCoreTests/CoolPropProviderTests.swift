import Foundation
import XCTest
@testable import PhaseXpertCore

final class CoolPropProviderTests: XCTestCase {
    private final class EnvelopeCallRecorder: @unchecked Sendable {
        private(set) var callCount = 0

        func recordCall() {
            callCount += 1
        }
    }

    private struct MockEngine: CoolPropEngine {
        let isAvailable = true
        let libraryVersion = "8.0.0-test"
        var envelopeCallRecorder: EnvelopeCallRecorder?
        var result = CoolPropEngineResult(
            densityKilogramsPerCubicMetre: 821.4,
            dynamicViscosityPascalSeconds: 0.000071,
            phaseIdentifier: "supercritical_liquid",
            expandedProperties: CoolPropPureFluidProperties(
                enthalpyJoulesPerKilogram: 300_000,
                entropyJoulesPerKilogramKelvin: 1_500,
                internalEnergyJoulesPerKilogram: 280_000,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 2_200,
                isochoricHeatCapacityJoulesPerKilogramKelvin: 1_000,
                speedOfSoundMetresPerSecond: 300,
                thermalConductivityWattsPerMetreKelvin: 0.08,
                jouleThomsonKelvinPerPascal: -0.000_002
            )
        )
        var binaryResult = CoolPropBinaryEngineResult(
            densityKilogramsPerCubicMetre: 760.2,
            phaseIdentifier: "supercritical_liquid"
        )
        var saturationLimits = CoolPropSaturationLimits(
            triplePointTemperatureK: 216.6,
            criticalPointTemperatureK: 304.1,
            criticalPointPressurePa: 7_377_000
        )
        var saturationPressure: @Sendable (Double) -> Double = { temperature in
            temperature * 20_000
        }
        var mixtureEnvelope = CoolPropMixtureEnvelopeResult(
            points: [
                .init(temperatureK: 230, pressurePa: 1_000_000, branch: .bubble),
                .init(temperatureK: 260, pressurePa: 3_000_000, branch: .bubble),
                .init(temperatureK: 265, pressurePa: 3_100_000, branch: .critical),
                .init(temperatureK: 255, pressurePa: 2_800_000, branch: .dew),
                .init(temperatureK: 225, pressurePa: 900_000, branch: .dew)
            ],
            solverMethod: "Mock CoolProp phase envelope"
        )

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> CoolPropEngineResult {
            result
        }

        func calculateCarbonDioxideNitrogen(
            pressurePa: Double,
            temperatureK: Double,
            carbonDioxideMoleFraction: Double,
            nitrogenMoleFraction: Double
        ) async throws -> CoolPropBinaryEngineResult {
            binaryResult
        }

        func calculateDryCarbonDioxideMixture(
            pressurePa: Double,
            temperatureK: Double,
            composition: [MixtureComponent]
        ) async throws -> CoolPropBinaryEngineResult {
            binaryResult
        }

        func calculateCarbonDioxideWaterHomogeneousGas(
            pressurePa: Double,
            temperatureK: Double,
            carbonDioxideMoleFraction: Double,
            waterMoleFraction: Double
        ) async throws -> CoolPropBinaryEngineResult {
            CoolPropBinaryEngineResult(
                densityKilogramsPerCubicMetre: 31.25,
                densityMolesPerCubicMetre: 712.0,
                reducingDensityMolesPerCubicMetre: 10_100,
                gibbsMolarJoulesPerMole: -2_000,
                phaseIdentifier: "gas"
            )
        }

        func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
            saturationLimits
        }

        func pureCarbonDioxideSaturationPressure(
            temperatureK: Double
        ) async throws -> Double {
            saturationPressure(temperatureK)
        }

        func dryCarbonDioxideMixturePhaseEnvelope(
            composition: [MixtureComponent]
        ) async throws -> CoolPropMixtureEnvelopeResult {
            envelopeCallRecorder?.recordCall()
            return mixtureEnvelope
        }
    }

    private final class PhaseMapPhaseOnlyCallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [(pressurePa: Double, temperatureK: Double)] = []

        func recordCall(pressurePa: Double, temperatureK: Double) {
            lock.withLock {
                calls.append((pressurePa, temperatureK))
            }
        }
    }

    private struct PhaseMapPhaseOnlyEngine: CoolPropEngine {
        let isAvailable = true
        let libraryVersion = "8.0.0-legacy-stability-test"
        var phaseResult: @Sendable (Double, Double) throws -> CoolPropPhaseEngineResult
        var recorder: PhaseMapPhaseOnlyCallRecorder?

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> CoolPropEngineResult {
            throw ProviderError.modelUnavailable("Pure CO2 is not used by this test engine.")
        }

        func calculateCarbonDioxideNitrogen(
            pressurePa: Double,
            temperatureK: Double,
            carbonDioxideMoleFraction: Double,
            nitrogenMoleFraction: Double
        ) async throws -> CoolPropBinaryEngineResult {
            throw ProviderError.modelUnavailable("Unimposed PT flash is not used by this test engine.")
        }

        func calculateDryCarbonDioxideMixture(
            pressurePa: Double,
            temperatureK: Double,
            composition: [MixtureComponent]
        ) async throws -> CoolPropBinaryEngineResult {
            throw ProviderError.modelUnavailable("Density-producing PT flash is not used by Phase Map.")
        }

        func identifyDryCarbonDioxideMixturePhase(
            pressurePa: Double,
            temperatureK: Double,
            composition: [MixtureComponent]
        ) async throws -> CoolPropPhaseEngineResult {
            recorder?.recordCall(pressurePa: pressurePa, temperatureK: temperatureK)
            return try phaseResult(pressurePa, temperatureK)
        }

        func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
            throw ProviderError.modelUnavailable("Pure CO2 saturation is not used by this test engine.")
        }

        func pureCarbonDioxideSaturationPressure(
            temperatureK: Double
        ) async throws -> Double {
            throw ProviderError.modelUnavailable("Pure CO2 saturation is not used by this test engine.")
        }

        func dryCarbonDioxideMixturePhaseEnvelope(
            composition: [MixtureComponent]
        ) async throws -> CoolPropMixtureEnvelopeResult {
            throw ProviderError.modelUnavailable("Phase envelope is not used by this test engine.")
        }
    }

    func testUnavailableEngineDoesNotClaimCapabilities() {
        let provider = CoolPropProvider(engine: UnavailableCoolPropEngine())

        XCTAssertEqual(provider.descriptor.availability, .unavailable)
        XCTAssertTrue(provider.descriptor.supportedComponents.isEmpty)
        XCTAssertTrue(provider.descriptor.supportedProperties.isEmpty)
    }

    func testPureCO2ResultIsPreliminaryAndTraceable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [
                .density,
                .dynamicViscosity,
                .molarMass,
                .compressibilityFactor,
                .specificVolume,
                .enthalpy
            ],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)

        XCTAssertEqual(response.model.modelVersion, "8.0.0-test")
        XCTAssertEqual(response.model.availability, .preliminary)
        XCTAssertEqual(response.phase, .dense)
        XCTAssertTrue(response.isScientificResult)
        XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.status,
            .calculated
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .dynamicViscosity }?.unit,
            "Pa·s"
        )
        let molarMass = try XCTUnwrap(
            response.properties.first { $0.property == .molarMass }?.value
        )
        XCTAssertEqual(molarMass, 44.0095, accuracy: 1e-12)
        XCTAssertEqual(
            response.properties.first { $0.property == .specificVolume }?.status,
            .calculated
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .compressibilityFactor }?.status,
            .calculated
        )
        XCTAssertTrue(response.solver.method.contains("Z=pM/(ρRT)"))
        XCTAssertEqual(
            response.properties.first { $0.property == .enthalpy }?.status,
            .calculated
        )
        XCTAssertTrue(response.warnings.contains { $0.contains("default reference state") })
    }

    func testPureCO2ExpandedPropertiesAreCalculatedWithTraceableUnits() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let requested: Set<PropertyID> = [
            .enthalpy,
            .entropy,
            .internalEnergy,
            .isobaricHeatCapacity,
            .isochoricHeatCapacity,
            .heatCapacityRatio,
            .speedOfSound,
            .thermalConductivity,
            .jouleThomsonCoefficient
        ]
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: requested,
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)
        let byProperty = Dictionary(
            uniqueKeysWithValues: response.properties.map { ($0.property, $0) }
        )

        XCTAssertEqual(Set(byProperty.keys), requested)
        XCTAssertTrue(byProperty.values.allSatisfy { $0.status == .calculated })
        XCTAssertEqual(byProperty[.enthalpy]?.unit, "J/kg")
        XCTAssertEqual(byProperty[.entropy]?.unit, "J/(kg·K)")
        XCTAssertEqual(byProperty[.isobaricHeatCapacity]?.unit, "J/(kg·K)")
        XCTAssertEqual(byProperty[.speedOfSound]?.unit, "m/s")
        XCTAssertEqual(byProperty[.thermalConductivity]?.unit, "W/(m·K)")
        XCTAssertEqual(byProperty[.jouleThomsonCoefficient]?.unit, "°C/bar")
        let jouleThomson = try XCTUnwrap(
            byProperty[.jouleThomsonCoefficient]?.value
        )
        let heatCapacityRatio = try XCTUnwrap(
            byProperty[.heatCapacityRatio]?.value
        )
        XCTAssertEqual(jouleThomson, -0.2, accuracy: 1e-12)
        XCTAssertEqual(heatCapacityRatio, 2.2, accuracy: 1e-12)
        XCTAssertTrue(response.solver.method.contains("single P,T state update"))
    }

    func testCO2NitrogenExpandedPureFluidPropertiesRemainUnavailable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let requested: Set<PropertyID> = [
            .enthalpy,
            .entropy,
            .internalEnergy,
            .isobaricHeatCapacity,
            .isochoricHeatCapacity,
            .heatCapacityRatio,
            .speedOfSound,
            .thermalConductivity,
            .jouleThomsonCoefficient
        ]
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 15_000_000,
                temperatureK: 293.15,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.95),
                    .init(component: .nitrogen, moleFraction: 0.05)
                ],
                requestedProperties: requested,
                clientVersion: "test"
            )
        )

        XCTAssertEqual(Set(response.properties.map(\.property)), requested)
        XCTAssertTrue(response.properties.allSatisfy { $0.status == .unavailable })
        XCTAssertTrue(response.properties.allSatisfy { $0.value == nil })
    }

    func testNonFiniteExpandedPropertyProducesExplicitFailure() async throws {
        let expanded = CoolPropPureFluidProperties(
            enthalpyJoulesPerKilogram: 300_000,
            entropyJoulesPerKilogramKelvin: 1_500,
            internalEnergyJoulesPerKilogram: 280_000,
            isobaricHeatCapacityJoulesPerKilogramKelvin: .nan,
            isochoricHeatCapacityJoulesPerKilogramKelvin: 1_000,
            speedOfSoundMetresPerSecond: 300,
            thermalConductivityWattsPerMetreKelvin: 0.08,
            jouleThomsonKelvinPerPascal: -0.000_002
        )
        let provider = CoolPropProvider(
            engine: MockEngine(
                result: CoolPropEngineResult(
                    densityKilogramsPerCubicMetre: 821.4,
                    dynamicViscosityPascalSeconds: 0.000071,
                    phaseIdentifier: "supercritical_liquid",
                    expandedProperties: expanded
                )
            )
        )
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 15_000_000,
                temperatureK: 293.15,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [.isobaricHeatCapacity, .heatCapacityRatio],
                clientVersion: "test"
            )
        )

        XCTAssertTrue(response.properties.allSatisfy { $0.status == .failed })
        XCTAssertTrue(response.properties.allSatisfy { $0.value == nil })
    }

    func testCO2NitrogenDensityIsPreliminaryAndViscosityRemainsUnavailable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        XCTAssertEqual(
            provider.descriptor.supportedComponents,
            [
                .carbonDioxide,
                .nitrogen,
                .oxygen,
                .argon,
                .methane,
                .hydrogen,
                .carbonMonoxide,
                .hydrogenSulfide,
                .water
            ]
        )
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            requestedProperties: [.density, .dynamicViscosity],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)

        XCTAssertEqual(response.phase, .dense)
        XCTAssertTrue(response.warnings.contains { $0.contains("DRY MIXTURE") })
        XCTAssertTrue(response.solver.method.contains("interaction entries only"))
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.value,
            760.2
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .dynamicViscosity }?.status,
            .unavailable
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CalculationResponse.self, from: encoded)
        XCTAssertEqual(decoded, response)
    }

    func testApplicabilityReportsNitrogenAboveSpikeCap() {
        let provider = CoolPropProvider(engine: MockEngine())

        let accepted = provider.applicabilityIssues(for: [
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .nitrogen, moleFraction: 0.05)
        ])
        let boundary = provider.applicabilityIssues(for: [
            .init(component: .carbonDioxide, moleFraction: 0.90),
            .init(component: .nitrogen, moleFraction: 0.10)
        ])
        let rejected = provider.applicabilityIssues(for: [
            .init(component: .carbonDioxide, moleFraction: 0.899999),
            .init(component: .nitrogen, moleFraction: 0.100001)
        ])

        XCTAssertTrue(accepted.isEmpty)
        XCTAssertTrue(boundary.isEmpty)
        XCTAssertEqual(rejected.count, 1)
        XCTAssertEqual(rejected.first?.code, .componentOutsideModelRange)
        XCTAssertEqual(rejected.first?.severity, .error)
    }

    func testBinaryCompositionIsNotImplicitlyNormalized() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.94995),
            MixtureComponent(component: .nitrogen, moleFraction: 0.05)
        ]
        let issues = provider.applicabilityIssues(for: composition)

        XCTAssertEqual(issues.map(\.code), [.compositionTotal])

        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: composition,
            requestedProperties: [.density],
            clientVersion: "test"
        )
        do {
            _ = try await provider.calculate(request)
            XCTFail("The provider must not silently normalize binary input.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest(
                    "Dry-mixture mole fractions must sum to 100 mol% without implicit normalization."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNitrogenAboveSpikeCapIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.89),
                .init(component: .nitrogen, moleFraction: 0.11)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("The temporary 10 mol% N₂ cap must be enforced.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest(
                    "The dry-mixture scope is temporarily limited to at most 10 mol% total impurity."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSupportedDryMulticomponentMixtureCalculatesDensityAndDerivedValues() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 15_000_000,
                temperatureK: 293.15,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.94),
                    .init(component: .nitrogen, moleFraction: 0.02),
                    .init(component: .oxygen, moleFraction: 0.01),
                    .init(component: .argon, moleFraction: 0.01),
                    .init(component: .methane, moleFraction: 0.01),
                    .init(component: .hydrogen, moleFraction: 0.01)
                ],
                requestedProperties: [
                    .density, .molarMass, .compressibilityFactor,
                    .specificVolume, .dynamicViscosity
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.properties.first { $0.property == .density }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .molarMass }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .compressibilityFactor }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .specificVolume }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .dynamicViscosity }?.status, .unavailable)
        XCTAssertTrue(response.warnings.contains { $0.contains("product guardrail") })
    }

    func testWetCompositionOutsideNarrowPreliminaryGateIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .water, moleFraction: 0.01)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Water outside the narrow preliminary gate must be rejected.")
        } catch let error as ProviderError {
            guard case let .invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest, got \(error).")
            }
            XCTAssertTrue(message.contains("1 to 1000 ppm"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreliminaryWetGasCalculatesDensityAndDerivedPropertiesOnly() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let response = try await provider.calculate(CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 2_000_000,
            temperatureK: 373.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9995),
                .init(component: .water, moleFraction: 0.0005)
            ],
            requestedProperties: [.density, .molarMass, .specificVolume, .compressibilityFactor, .isobaricHeatCapacity],
            clientVersion: "test"
        ))
        XCTAssertEqual(response.phase, .gas)
        XCTAssertEqual(response.properties.first { $0.property == .density }?.value, 31.25)
        XCTAssertEqual(response.properties.first { $0.property == .molarMass }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .specificVolume }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .compressibilityFactor }?.status, .calculated)
        XCTAssertEqual(response.properties.first { $0.property == .isobaricHeatCapacity }?.status, .unavailable)
        XCTAssertTrue(response.warnings.contains { $0.contains("does not itself determine aqueous equilibrium") })
    }

    func testValidatedWaterEquilibriumIsAttachedWithoutReplacingHomogeneousProperties() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let response = try await provider.calculate(CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 4_710_000,
            temperatureK: 373.27,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9995),
                .init(component: .water, moleFraction: 0.0005)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        ))
        XCTAssertEqual(response.properties.first?.value, 31.25)
        let equilibrium = try XCTUnwrap(response.waterEquilibrium)
        XCTAssertEqual(equilibrium.waterStatus, .belowSaturation)
        XCTAssertGreaterThan(equilibrium.waterInCarbonDioxideRichPhasePPM, 20_000)
        XCTAssertEqual(equilibrium.currentWaterPPM, 500)
        XCTAssertNil(equilibrium.waterDropoutPressurePa)
    }

    func testWetGasRejectsStateOutsideTemperaturePressureGate() async {
        let provider = CoolPropProvider(engine: MockEngine())
        do {
            _ = try await provider.calculate(CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 8_000_000,
                temperatureK: 320,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.999),
                    .init(component: .water, moleFraction: 0.001)
                ],
                requestedProperties: [.density],
                clientVersion: "test"
            ))
            XCTFail("Expected the wet state to be rejected.")
        } catch let ProviderError.invalidRequest(message) {
            XCTAssertTrue(message.contains("350–423.15 K"))
        } catch {
            XCTFail("Expected invalidRequest, got \(error).")
        }
    }

    func testWaterGuidanceDistinguishesHomogeneousAndEquilibriumDomains() {
        let provider = CoolPropProvider(engine: MockEngine())
        let guidance = provider.operatingRangeGuidance(for: .init(
            pressurePa: 10_000_000,
            temperatureK: 373.20,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9995),
                .init(component: .water, moleFraction: 0.0005)
            ]
        ))
        XCTAssertTrue(guidance?.currentInputIssues.contains {
            $0.detail.contains("Water-equilibrium results remain available")
        } == true)
    }

    func testNonFinitePureDensityIsRejected() async {
        let invalidEngine = MockEngine(result: .init(
            densityKilogramsPerCubicMetre: .nan,
            dynamicViscosityPascalSeconds: 0.000071,
            phaseIdentifier: "liquid"
        ))
        let provider = CoolPropProvider(engine: invalidEngine)
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Non-finite native output must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive density."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonFiniteBinaryDensityIsRejected() async {
        let invalidEngine = MockEngine(binaryResult: .init(
            densityKilogramsPerCubicMetre: .infinity,
            phaseIdentifier: "gas"
        ))
        let provider = CoolPropProvider(engine: invalidEngine)
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 10_000_000,
            temperatureK: 303.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Non-finite binary output must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive density."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPureCO2SaturationBoundaryIsFiniteOrderedAndIncludesCriticalPoint() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        let response = try await provider.phaseEnvelope(request)

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.boundaryKind, .pureFluidSaturation)
        XCTAssertEqual(response.model?.modelVersion, "8.0.0-test")
        XCTAssertEqual(response.solver?.converged, true)
        XCTAssertEqual(response.points.count, 82)
        XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
        XCTAssertTrue(response.points.allSatisfy {
            $0.temperatureK.isFinite && $0.pressurePa.isFinite && $0.pressurePa > 0
        })
        let saturationPoints = response.points.filter { $0.branch == .bubble }
        XCTAssertEqual(saturationPoints.count, 81)
        XCTAssertTrue(zip(saturationPoints, saturationPoints.dropFirst()).allSatisfy { pair in
            pair.0.temperatureK < pair.1.temperatureK
                && pair.0.pressurePa < pair.1.pressurePa
        })
        let critical = try XCTUnwrap(response.points.last)
        XCTAssertEqual(critical.branch, .critical)
        XCTAssertEqual(critical.temperatureK, 304.1, accuracy: 1e-12)
        XCTAssertEqual(critical.pressurePa, 7_377_000, accuracy: 1e-12)
    }

    func testPhaseDiagramEligibilityAcceptsPureCO2AndZeroImpurityRows() {
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 1)
            ]),
            .pureCarbonDioxide
        )
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 1),
                .init(component: .nitrogen, moleFraction: 0)
            ]),
            .pureCarbonDioxide
        )
    }

    func testPhaseDiagramEligibilityRejectsPositiveImpuritiesAndInvalidInput() {
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 0.999999),
                .init(component: .nitrogen, moleFraction: 0.000001)
            ]),
            .multicomponent
        )
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .nitrogen, moleFraction: 0.01)
            ]),
            .multicomponent
        )
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9)
            ]),
            .invalidComposition
        )
        XCTAssertEqual(
            PhaseDiagramEligibility.evaluate(composition: [
                .init(component: .carbonDioxide, moleFraction: 1),
                .init(component: .carbonDioxide, moleFraction: 0)
            ]),
            .invalidComposition
        )
    }

    func testMixturePhaseEnvelopeIsRejectedBeforeNativeEnvelopeWork() async {
        let recorder = EnvelopeCallRecorder()
        let provider = CoolPropProvider(engine: MockEngine(envelopeCallRecorder: recorder))
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .nitrogen, moleFraction: 0.01)
            ]
        )

        do {
            _ = try await provider.phaseEnvelope(request)
            XCTFail("A multicomponent phase diagram request must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest(
                    PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(recorder.callCount, 0)
    }

    func testWetMixturePhaseEnvelopeIsRejectedBeforeNativeEnvelopeWork() async {
        let recorder = EnvelopeCallRecorder()
        let provider = CoolPropProvider(engine: MockEngine(envelopeCallRecorder: recorder))
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9995),
                .init(component: .water, moleFraction: 0.0005)
            ]
        )

        do {
            _ = try await provider.phaseEnvelope(request)
            XCTFail("A wet-mixture phase diagram request must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest(
                    PhaseDiagramEligibility.pureCarbonDioxideScopeMessage
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(recorder.callCount, 0)
    }

    func testNonFiniteSaturationPressureIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine(
            saturationPressure: { _ in .nan }
        ))
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        do {
            _ = try await provider.phaseEnvelope(request)
            XCTFail("A non-finite boundary point must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive saturation pressure."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledSaturationBoundaryStopsBeforeEngineWork() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let task = Task {
            try await provider.phaseEnvelope(request)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled envelope request must not complete.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPhaseMapUsesLegacyStabilityPhaseEngineAndDoesNotRequestDensity() async throws {
        let recorder = PhaseMapPhaseOnlyCallRecorder()
        let provider = CoolPropProvider(engine: PhaseMapPhaseOnlyEngine(
            phaseResult: { pressure, _ in
                CoolPropPhaseEngineResult(
                    phaseIdentifier: pressure < 15_000_000 ? "gas" : "twophase"
                )
            },
            recorder: recorder
        ))
        let request = fallbackPhaseMapRequest()

        let result = try await provider.phaseMap(request)
        let expectedCount = try PhaseMapGridBuilder.points(for: request).count

        XCTAssertEqual(result.evaluations.count, expectedCount)
        XCTAssertEqual(recorder.calls.count, expectedCount)
        XCTAssertTrue(result.evaluations.contains {
            $0.classification.classification == .gas
        })
        XCTAssertTrue(result.evaluations.contains {
            $0.classification.classification == .multiphase
        })
        XCTAssertEqual(result.failedCount, 0)
    }

    func testPhaseMapPhaseOnlyFailuresAreRecoverableAndSubsequentPointsContinue() async throws {
        let recorder = PhaseMapPhaseOnlyCallRecorder()
        let provider = CoolPropProvider(engine: PhaseMapPhaseOnlyEngine(
            phaseResult: { pressure, _ in
                if pressure == 7_500_000 {
                    throw ProviderError.malformedResponse("mock pinned CoolProp phase failure")
                }
                return CoolPropPhaseEngineResult(phaseIdentifier: "liquid")
            },
            recorder: recorder
        ))
        let request = fallbackPhaseMapRequest()

        let result = try await provider.phaseMap(request)
        let expectedCount = try PhaseMapGridBuilder.points(for: request).count

        XCTAssertEqual(result.evaluations.count, expectedCount)
        XCTAssertEqual(recorder.calls.count, expectedCount)
        XCTAssertEqual(result.failedCount, PhaseMapResolution.five.rawValue)
        let firstFailureIndex = try XCTUnwrap(result.evaluations.firstIndex {
            $0.classification.classification == .failed
        })
        XCTAssertTrue(result.evaluations.dropFirst(firstFailureIndex + 1).contains {
            $0.classification.classification == .liquid
        })
    }

    func testPhaseMapUnknownPointsAreNotFailuresAndSubsequentPointsContinue() async throws {
        let recorder = PhaseMapPhaseOnlyCallRecorder()
        let provider = CoolPropProvider(engine: PhaseMapPhaseOnlyEngine(
            phaseResult: { pressure, _ in
                if pressure == 7_500_000 {
                    return CoolPropPhaseEngineResult(phaseIdentifier: "unknown")
                }
                return CoolPropPhaseEngineResult(phaseIdentifier: "liquid")
            },
            recorder: recorder
        ))
        let request = fallbackPhaseMapRequest()

        let result = try await provider.phaseMap(request)
        let expectedCount = try PhaseMapGridBuilder.points(for: request).count

        XCTAssertEqual(result.evaluations.count, expectedCount)
        XCTAssertEqual(recorder.calls.count, expectedCount)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.unknownCount, PhaseMapResolution.five.rawValue)
        XCTAssertEqual(result.classifiedCount, expectedCount - PhaseMapResolution.five.rawValue)
        let firstUnknownIndex = try XCTUnwrap(result.evaluations.firstIndex {
            $0.classification.classification == .unknown
        })
        XCTAssertTrue(result.evaluations.dropFirst(firstUnknownIndex + 1).contains {
            $0.classification.classification == .liquid
        })
    }

    private func fallbackPhaseMapRequest() -> PhaseMapRequest {
        PhaseMapRequest(
            modelID: "coolprop-heos",
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            range: .automatic(pressurePa: 15_000_000, temperatureK: 293.15),
            resolution: .five,
            clientVersion: "fallback-test"
        )
    }

}

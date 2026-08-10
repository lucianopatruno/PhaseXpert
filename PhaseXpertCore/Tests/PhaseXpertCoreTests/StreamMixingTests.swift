import XCTest
@testable import PhaseXpertCore

final class StreamMixingTests: XCTestCase {
    private let engine = StreamMixingEngine()
    private let outlet = StreamMixingOutletConditionInput(
        pressureValue: 120,
        pressureUnit: .bara,
        temperatureValue: 25,
        temperatureUnit: .celsius
    )

    func testTwoStreamMolarFlowMixing() {
        let result = engine.mix(request([
            stream(
                name: "A",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            ),
            stream(
                name: "B",
                flowValue: 5,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 1]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.totalMolarFlowMolesPerSecond, 15, accuracy: 1e-12)
        XCTAssertEqual(moleFraction(.carbonDioxide, in: result), 14.0 / 15.0, accuracy: 1e-12)
        XCTAssertEqual(moleFraction(.nitrogen, in: result), 1.0 / 15.0, accuracy: 1e-12)
        XCTAssertEqual(componentFlow(.carbonDioxide, in: result), 14, accuracy: 1e-12)
        XCTAssertEqual(componentFlow(.nitrogen, in: result), 1, accuracy: 1e-12)
        XCTAssertTrue(result.conservation.isConserved)
    }

    func testTwoStreamMassFlowMixing() throws {
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let streamAMass = 100 * co2Mass
        let streamBMass = 100 * (0.8 * co2Mass + 0.2 * nitrogenMass)

        let result = engine.mix(request([
            stream(
                name: "A",
                flowValue: streamAMass,
                flowUnit: .kilogramsPerSecond,
                composition: [.carbonDioxide: 1]
            ),
            stream(
                name: "B",
                flowValue: streamBMass,
                flowUnit: .kilogramsPerSecond,
                composition: [.carbonDioxide: 0.8, .nitrogen: 0.2]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.totalMolarFlowMolesPerSecond, 200, accuracy: 1e-10)
        XCTAssertEqual(componentFlow(.carbonDioxide, in: result), 180, accuracy: 1e-10)
        XCTAssertEqual(componentFlow(.nitrogen, in: result), 20, accuracy: 1e-10)
        XCTAssertEqual(
            result.totalMassFlowKilogramsPerSecond,
            streamAMass + streamBMass,
            accuracy: 1e-12
        )
        XCTAssertTrue(result.conservation.isConserved)
    }

    func testMixedMassAndMolarFlowInputs() throws {
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let result = engine.mix(request([
            stream(
                name: "Mass",
                flowValue: 1_000 * co2Mass,
                flowUnit: .kilogramsPerSecond,
                composition: [.carbonDioxide: 1]
            ),
            stream(
                name: "Molar",
                flowValue: 100,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.totalMolarFlowMolesPerSecond, 1_100, accuracy: 1e-10)
        XCTAssertEqual(componentFlow(.carbonDioxide, in: result), 1_090, accuracy: 1e-10)
        XCTAssertEqual(componentFlow(.nitrogen, in: result), 10, accuracy: 1e-10)
    }

    func testIdenticalCompositionsAtDifferentFlowRatesRemainIdentical() {
        let result = engine.mix(request([
            stream(
                name: "Small",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .nitrogen: 0.05]
            ),
            stream(
                name: "Large",
                flowValue: 99,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .nitrogen: 0.05]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(moleFraction(.carbonDioxide, in: result), 0.95, accuracy: 1e-12)
        XCTAssertEqual(moleFraction(.nitrogen, in: result), 0.05, accuracy: 1e-12)
    }

    func testDifferentCompositionsAtEqualFlowRates() {
        let result = engine.mix(request([
            stream(
                name: "A",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.90, .nitrogen: 0.10]
            ),
            stream(
                name: "B",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.98, .oxygen: 0.02]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(moleFraction(.carbonDioxide, in: result), 0.94, accuracy: 1e-12)
        XCTAssertEqual(moleFraction(.nitrogen, in: result), 0.05, accuracy: 1e-12)
        XCTAssertEqual(moleFraction(.oxygen, in: result), 0.01, accuracy: 1e-12)
    }

    func testTraceComponentConservation() {
        let trace = 1e-8
        let result = engine.mix(request([
            stream(
                name: "Trace",
                flowValue: 1_000,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 1 - trace, .hydrogen: trace]
            ),
            stream(
                name: "Pure",
                flowValue: 1_000,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 1]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(componentFlow(.hydrogen, in: result), 1e-5, accuracy: 1e-15)
        XCTAssertEqual(moleFraction(.hydrogen, in: result), 5e-9, accuracy: 1e-16)
    }

    func testThreeToSixStreamsCalculate() {
        for count in 3...6 {
            let streams = (0..<count).map { index in
                stream(
                    id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))")!,
                    name: "S\(index + 1)",
                    flowValue: Double(index + 1),
                    flowUnit: .molesPerSecond,
                    composition: [.carbonDioxide: 0.99, .nitrogen: 0.01]
                )
            }
            let result = engine.mix(request(streams))
            XCTAssertEqual(result.status, .calculated)
            XCTAssertEqual(
                result.totalMolarFlowMolesPerSecond,
                Double((1...count).reduce(0, +)),
                accuracy: 1e-12
            )
        }
    }

    func testStreamOrderIndependence() {
        let streams = [
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "A",
                flowValue: 4,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            ),
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "B",
                flowValue: 6,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .oxygen: 0.05]
            )
        ]

        let first = engine.mix(request(streams))
        let second = engine.mix(request(streams.reversed()))
        XCTAssertEqual(first.composition, second.composition)
        XCTAssertEqual(first.componentMolarFlows, second.componentMolarFlows)
    }

    func testComponentOrderIndependence() {
        let first = engine.mix(request([
            stream(
                name: "A",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            ),
            stream(
                name: "B",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                composition: [.oxygen: 0.01, .carbonDioxide: 0.99]
            )
        ]))
        let second = engine.mix(request([
            stream(
                name: "A",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                orderedComposition: [
                    .init(component: .nitrogen, moleFraction: 0.1),
                    .init(component: .carbonDioxide, moleFraction: 0.9)
                ]
            ),
            stream(
                name: "B",
                flowValue: 10,
                flowUnit: .molesPerSecond,
                orderedComposition: [
                    .init(component: .carbonDioxide, moleFraction: 0.99),
                    .init(component: .oxygen, moleFraction: 0.01)
                ]
            )
        ]))

        XCTAssertEqual(first.composition, second.composition)
        XCTAssertEqual(first.componentMolarFlows, second.componentMolarFlows)
    }

    func testFlowConservationValuesAreRecorded() {
        let result = engine.mix(request([
            stream(
                name: "A",
                flowValue: 7,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            ),
            stream(
                name: "B",
                flowValue: 3,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 1]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.conservation.totalMolarFlowResidual, 0, accuracy: 1e-12)
        XCTAssertEqual(result.conservation.maximumComponentMolarFlowResidual, 0, accuracy: 1e-12)
        XCTAssertEqual(result.conservation.totalMassFlowResidual, 0, accuracy: 1e-12)
    }

    func testMassConservationChecksEnteredMassBasisFlows() throws {
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let mixtureMass = 10 * (0.9 * co2Mass + 0.1 * nitrogenMass)
        let result = engine.mix(request([
            stream(
                name: "Mass basis",
                flowValue: mixtureMass,
                flowUnit: .kilogramsPerSecond,
                composition: [.carbonDioxide: 0.9, .nitrogen: 0.1]
            ),
            stream(
                name: "Molar basis",
                flowValue: 5,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 1]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(
            result.streamContributions.first?.massFlowKilogramsPerSecond ?? .nan,
            mixtureMass,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            result.conservation.maximumMassBasisInletMassFlowResidual,
            0,
            accuracy: 1e-12
        )
        XCTAssertTrue(result.conservation.isConserved)
    }

    func testDeliberatelyInconsistentMassTotalFailsConservationCheck() {
        let result = engine.mix(request([
            stream(name: "A", flowValue: 10, flowUnit: .molesPerSecond),
            stream(name: "B", flowValue: 5, flowUnit: .molesPerSecond)
        ]))

        let inconsistent = engine.conservationCheck(
            componentMolarFlows: result.componentMolarFlows,
            streamContributions: result.streamContributions,
            totalMolarFlow: result.totalMolarFlowMolesPerSecond,
            totalMassFlow: result.totalMassFlowKilogramsPerSecond + 0.001
        )

        XCTAssertFalse(inconsistent.isConserved)
        XCTAssertGreaterThan(inconsistent.totalMassFlowResidual, 0)
    }

    func testOriginalValuesAndUnitsArePreservedInProvenance() {
        let inlet = stream(
            name: "Entered",
            flowValue: 3.6,
            flowUnit: .kilomolesPerHour,
            pressureValue: 12,
            pressureUnit: .megapascal,
            temperatureValue: 77,
            temperatureUnit: .fahrenheit,
            compositionBasis: .molePercent,
            composition: [.carbonDioxide: 0.96, .nitrogen: 0.04]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        let contribution = result.streamContributions.first { $0.streamID == inlet.id }
        XCTAssertEqual(contribution?.input.flowValue, 3.6)
        XCTAssertEqual(contribution?.input.flowUnit, .kilomolesPerHour)
        XCTAssertEqual(contribution?.input.pressureValue, 12)
        XCTAssertEqual(contribution?.input.pressureUnit, .megapascal)
        XCTAssertEqual(contribution?.input.temperatureValue, 77)
        XCTAssertEqual(contribution?.input.temperatureUnit, .fahrenheit)
        XCTAssertEqual(contribution?.input.originalComposition.first?.unit, .molePercent)
        XCTAssertEqual(contribution?.input.convertedComposition, inlet.composition)
        XCTAssertEqual(contribution?.input.canonicalComposition, inlet.composition)
        XCTAssertEqual(contribution?.input.compositionStatus, .valid)
    }

    func testUserEnteredOutletPressureAndTemperatureArePreserved() {
        let result = engine.mix(request([
            stream(name: "A", flowValue: 1, flowUnit: .molesPerSecond),
            stream(name: "B", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.outlet.pressureValue, 120)
        XCTAssertEqual(result.outlet.pressureUnit, .bara)
        XCTAssertEqual(result.outlet.pressurePa, 12_000_000, accuracy: 1e-9)
        XCTAssertEqual(result.outlet.temperatureValue, 25)
        XCTAssertEqual(result.outlet.temperatureUnit, .celsius)
        XCTAssertEqual(result.outlet.temperatureK, 298.15, accuracy: 1e-12)
    }

    func testDifferentInletPressuresProduceOneWarning() {
        let result = engine.mix(request([
            stream(
                name: "A",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                pressureValue: 100,
                pressureUnit: .bara
            ),
            stream(
                name: "B",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                pressureValue: 150,
                pressureUnit: .bara
            ),
            stream(
                name: "C",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                pressureValue: 125,
                pressureUnit: .bara
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.code, .inletPressureDifference)
        XCTAssertTrue(result.warnings.first?.message.contains("does not model pressure equalization") == true)
    }

    func testDifferentInletTemperaturesAreRecordedThroughGeneralAssumption() {
        let result = engine.mix(request([
            stream(
                name: "Cold",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                temperatureValue: 10
            ),
            stream(
                name: "Warm",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                temperatureValue: 40
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(
            result.assumptions.filter { $0.code == .noEnergyBalance }.count,
            1
        )
        XCTAssertTrue(result.assumptions.contains {
            $0.message.contains("not enthalpy-balanced")
        })
    }

    func testExplicitlyAcceptedNearNormalizationIsRecorded() {
        let normalized = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.970_5 / 1.000_5),
            MixtureComponent(component: .nitrogen, moleFraction: 0.03 / 1.000_5)
        ]
        let inlet = InletStreamInput(
            name: "Normalized",
            flowValue: 1,
            flowUnit: .molesPerSecond,
            pressureValue: 120,
            pressureUnit: .bara,
            temperatureValue: 25,
            temperatureUnit: .celsius,
            originalComposition: [
                .init(component: .carbonDioxide, value: 97.05, unit: .molePercent),
                .init(component: .nitrogen, value: 3.0, unit: .molePercent)
            ],
            composition: normalized,
            normalizedComposition: normalized
        )

        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertTrue(result.assumptions.contains {
            $0.code == .explicitCompositionNormalization && $0.streamID == inlet.id
        })
        assertComposition(
            result.streamContributions.first?.input.normalizedComposition ?? [],
            matches: normalized,
            accuracy: 1e-12
        )
        assertComposition(
            result.streamContributions.first?.input.convertedComposition ?? [],
            matches: [
                .init(component: .carbonDioxide, moleFraction: 0.9705),
                .init(component: .nitrogen, moleFraction: 0.03)
            ],
            accuracy: 1e-12
        )
        XCTAssertEqual(result.streamContributions.first?.input.compositionStatus, .normalizationAccepted)
    }

    func testOriginalMoleFractionConversion() {
        let inlet = streamFromOriginal(
            name: "Mole fraction",
            originalComposition: [
                .init(component: .carbonDioxide, value: 0.97, unit: .moleFraction),
                .init(component: .nitrogen, value: 0.03, unit: .moleFraction)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.streamContributions.first?.input.convertedComposition, inlet.composition)
    }

    func testOriginalMolePercentConversion() {
        let inlet = streamFromOriginal(
            name: "Mole percent",
            originalComposition: [
                .init(component: .carbonDioxide, value: 97, unit: .molePercent),
                .init(component: .nitrogen, value: 3, unit: .molePercent)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.97),
                .init(component: .nitrogen, moleFraction: 0.03)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.streamContributions.first?.input.convertedComposition, inlet.composition)
    }

    func testOriginalPPMConversion() {
        let inlet = streamFromOriginal(
            name: "PPM",
            originalComposition: [
                .init(component: .carbonDioxide, value: 950_000, unit: .partsPerMillion),
                .init(component: .nitrogen, value: 50_000, unit: .partsPerMillion)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.streamContributions.first?.input.convertedComposition, inlet.composition)
    }

    func testOriginalMassFractionConvertsToMoleFraction() throws {
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let co2Amount = 0.8 / co2Mass
        let nitrogenAmount = 0.2 / nitrogenMass
        let total = co2Amount + nitrogenAmount
        let expected = [
            MixtureComponent(component: .carbonDioxide, moleFraction: co2Amount / total),
            MixtureComponent(component: .nitrogen, moleFraction: nitrogenAmount / total)
        ]
        let inlet = streamFromOriginal(
            name: "Mass fraction",
            originalComposition: [
                .init(component: .carbonDioxide, value: 0.8, unit: .massFraction),
                .init(component: .nitrogen, value: 0.2, unit: .massFraction)
            ],
            composition: expected
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(
            result.streamContributions.first?.input.convertedComposition.first?.moleFraction ?? .nan,
            expected[0].moleFraction,
            accuracy: 1e-12
        )
    }

    func testMissingMolarMassDuringMassFractionConversionIsRejected() {
        let inlet = streamFromOriginal(
            name: "Mass fraction missing",
            originalComposition: [
                .init(component: .carbonDioxide, value: 0.99, unit: .massFraction),
                .init(component: .helium, value: 0.01, unit: .massFraction)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .helium, moleFraction: 0.01)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .missingMolarMass })
    }

    func testOriginalCanonicalCompositionMismatchIsRejected() {
        let inlet = streamFromOriginal(
            name: "Mismatch",
            originalComposition: [
                .init(component: .carbonDioxide, value: 0.9, unit: .moleFraction),
                .init(component: .nitrogen, value: 0.1, unit: .moleFraction)
            ],
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .compositionProvenanceMismatch
        })
    }

    func testMixedCompositionBasesWithinOneStreamAreRejected() {
        let inlet = streamFromOriginal(
            name: "Mixed basis",
            originalComposition: [
                .init(component: .carbonDioxide, value: 0.9, unit: .moleFraction),
                .init(component: .nitrogen, value: 10, unit: .molePercent)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.9),
                .init(component: .nitrogen, moleFraction: 0.1)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .inconsistentCompositionBasis
        })
    }

    func testUnrelatedNormalizedCompositionIsRejected() {
        let inlet = streamFromOriginal(
            name: "Bad normalization",
            originalComposition: [
                .init(component: .carbonDioxide, value: 97.05, unit: .molePercent),
                .init(component: .nitrogen, value: 3, unit: .molePercent)
            ],
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.5),
                .init(component: .nitrogen, moleFraction: 0.5)
            ],
            normalizedComposition: [
                .init(component: .carbonDioxide, moleFraction: 0.5),
                .init(component: .nitrogen, moleFraction: 0.5)
            ]
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .invalidNormalization })
    }

    func testNormalizationFlagOnAlreadyValidCompositionIsRejected() {
        let valid = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.97),
            MixtureComponent(component: .nitrogen, moleFraction: 0.03)
        ]
        let inlet = streamFromOriginal(
            name: "False normalization",
            originalComposition: [
                .init(component: .carbonDioxide, value: 97, unit: .molePercent),
                .init(component: .nitrogen, value: 3, unit: .molePercent)
            ],
            composition: valid,
            normalizedComposition: valid
        )
        let result = engine.mix(request([
            inlet,
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .invalidNormalization })
    }

    func testInvalidCompositionIsRejectedWithoutSilentNormalization() {
        let result = engine.mix(request([
            stream(
                name: "Bad",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                orderedComposition: [
                    .init(component: .carbonDioxide, moleFraction: 0.9705),
                    .init(component: .nitrogen, moleFraction: 0.03)
                ]
            ),
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .normalizationRequired
        })
        XCTAssertTrue(result.streamContributions.isEmpty)
    }

    func testStreamOrderIndependenceAcrossNumericallyDifficultPermutations() {
        let streams = [
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                name: "Large",
                flowValue: 1e12,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.999_999_999, .nitrogen: 1e-9]
            ),
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                name: "Small",
                flowValue: 1e-6,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.98, .oxygen: 0.02]
            ),
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                name: "Medium",
                flowValue: 1e3,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .argon: 0.05]
            )
        ]
        let reference = engine.mix(request(streams))

        for permutation in permutations(of: streams) {
            let result = engine.mix(request(permutation))
            XCTAssertEqual(result.status, .calculated)
            XCTAssertEqual(result.componentMolarFlows, reference.componentMolarFlows)
            XCTAssertEqual(result.composition, reference.composition)
        }
    }

    func testConservationAtVerySmallAndLargeValidFlowMagnitudes() {
        let result = engine.mix(request([
            stream(
                name: "Tiny",
                flowValue: 1e-9,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.99, .nitrogen: 0.01]
            ),
            stream(
                name: "Huge",
                flowValue: 1e12,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.999, .oxygen: 0.001]
            )
        ]))

        XCTAssertEqual(result.status, .calculated)
        XCTAssertTrue(result.conservation.isConserved)
        XCTAssertEqual(result.totalMolarFlowMolesPerSecond, 1e12 + 1e-9, accuracy: 1e-3)
    }

    func testMissingMolarMassRejectsPositiveFlowComponent() {
        let result = engine.mix(request([
            stream(
                name: "Unsupported mass",
                flowValue: 1,
                flowUnit: .kilogramsPerSecond,
                composition: [.carbonDioxide: 0.99, .helium: 0.01]
            ),
            stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .missingMolarMass && $0.streamName == "Unsupported mass"
        })
    }

    func testZeroNegativeNaNAndInfiniteFlowAreRejected() {
        for flow in [0, -1, Double.nan, Double.infinity] {
            let result = engine.mix(request([
                stream(name: "Bad", flowValue: flow, flowUnit: .molesPerSecond),
                stream(name: "Other", flowValue: 1, flowUnit: .molesPerSecond)
            ]))
            XCTAssertEqual(result.status, .blocked)
            XCTAssertTrue(result.validationIssues.contains { $0.code == .invalidFlow })
        }
    }

    func testFewerThanTwoAndMoreThanSixStreamsAreRejected() {
        XCTAssertTrue(engine.mix(request([
            stream(name: "Only", flowValue: 1, flowUnit: .molesPerSecond)
        ])).validationIssues.contains { $0.code == .tooFewStreams })

        let seven = (0..<7).map {
            stream(
                id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", $0 + 1))")!,
                name: "S\($0)",
                flowValue: 1,
                flowUnit: .molesPerSecond
            )
        }
        XCTAssertTrue(engine.mix(request(seven)).validationIssues.contains {
            $0.code == .tooManyStreams
        })
    }

    func testDuplicateIdentifiersAreRejected() {
        let id = UUID()
        let result = engine.mix(request([
            stream(id: id, name: "A", flowValue: 1, flowUnit: .molesPerSecond),
            stream(id: id, name: "B", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .duplicateStreamIdentifier
        })
    }

    func testInvalidAggregationProtection() {
        let result = StreamMixingEngine(supportedComponents: [.carbonDioxide]).mix(request([
            stream(
                name: "A",
                flowValue: 1,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.99, .nitrogen: 0.01]
            ),
            stream(name: "B", flowValue: 1, flowUnit: .molesPerSecond)
        ]))

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.validationIssues.contains {
            $0.code == .invalidComposition || $0.code == .mixedCompositionUnsupported
        })
    }

    func testCodableRoundTripsForNewDomainTypes() throws {
        let request = request([
            stream(name: "A", flowValue: 1, flowUnit: .molesPerSecond),
            stream(
                name: "B",
                flowValue: 2,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .nitrogen: 0.05]
            )
        ])
        let result = engine.mix(request)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        encoder.dateEncodingStrategy = .secondsSince1970

        XCTAssertEqual(
            try decoder.decode(StreamMixingRequest.self, from: encoder.encode(request)),
            request
        )
        let decoded = try decoder.decode(
            MixedCompositionResult.self,
            from: encoder.encode(result)
        )
        XCTAssertEqual(decoded.requestID, result.requestID)
        XCTAssertEqual(decoded.status, result.status)
        XCTAssertEqual(decoded.outlet, result.outlet)
        XCTAssertEqual(decoded.composition, result.composition)
        XCTAssertEqual(decoded.totalMassFlowKilogramsPerSecond, result.totalMassFlowKilogramsPerSecond)
        XCTAssertEqual(decoded.totalMolarFlowMolesPerSecond, result.totalMolarFlowMolesPerSecond)
        XCTAssertEqual(decoded.componentMolarFlows, result.componentMolarFlows)
        XCTAssertEqual(decoded.streamContributions, result.streamContributions)
        XCTAssertEqual(decoded.conservation, result.conservation)
        XCTAssertEqual(decoded.conservation.molarFlowAbsoluteTolerance, 1e-12)
        XCTAssertEqual(decoded.streamContributions.first?.input.compositionStatus, .valid)
        XCTAssertEqual(decoded.warnings, result.warnings)
        XCTAssertEqual(decoded.assumptions, result.assumptions)
        XCTAssertEqual(decoded.validationIssues, result.validationIssues)
        XCTAssertEqual(decoded.calculatedAt.timeIntervalSince1970, result.calculatedAt.timeIntervalSince1970, accuracy: 1e-6)
    }

    func testDeterministicRepeatedCalculations() {
        let mixRequest = request([
            stream(name: "A", flowValue: 1, flowUnit: .molesPerSecond),
            stream(
                name: "B",
                flowValue: 2,
                flowUnit: .molesPerSecond,
                composition: [.carbonDioxide: 0.95, .nitrogen: 0.05]
            )
        ])
        let first = engine.mix(mixRequest)
        let second = engine.mix(mixRequest)

        XCTAssertEqual(first.status, second.status)
        XCTAssertEqual(first.composition, second.composition)
        XCTAssertEqual(first.totalMassFlowKilogramsPerSecond, second.totalMassFlowKilogramsPerSecond)
        XCTAssertEqual(first.totalMolarFlowMolesPerSecond, second.totalMolarFlowMolesPerSecond)
        XCTAssertEqual(first.componentMolarFlows, second.componentMolarFlows)
        XCTAssertEqual(first.streamContributions, second.streamContributions)
        XCTAssertEqual(first.warnings, second.warnings)
        XCTAssertEqual(first.assumptions, second.assumptions)
    }

    private func request(
        _ streams: [InletStreamInput]
    ) -> StreamMixingRequest {
        StreamMixingRequest(
            streams: streams,
            outlet: outlet,
            clientVersion: "test"
        )
    }

    private func stream(
        id: UUID = UUID(),
        name: String,
        flowValue: Double,
        flowUnit: StreamFlowUnit,
        pressureValue: Double = 120,
        pressureUnit: PressureUnit = .bara,
        temperatureValue: Double = 25,
        temperatureUnit: TemperatureUnit = .celsius,
        compositionBasis: CompositionUnit = .moleFraction,
        composition: [ComponentID: Double] = [.carbonDioxide: 1]
    ) -> InletStreamInput {
        stream(
            id: id,
            name: name,
            flowValue: flowValue,
            flowUnit: flowUnit,
            pressureValue: pressureValue,
            pressureUnit: pressureUnit,
            temperatureValue: temperatureValue,
            temperatureUnit: temperatureUnit,
            compositionBasis: compositionBasis,
            orderedComposition: composition
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { MixtureComponent(component: $0.key, moleFraction: $0.value) }
        )
    }

    private func stream(
        id: UUID = UUID(),
        name: String,
        flowValue: Double,
        flowUnit: StreamFlowUnit,
        pressureValue: Double = 120,
        pressureUnit: PressureUnit = .bara,
        temperatureValue: Double = 25,
        temperatureUnit: TemperatureUnit = .celsius,
        compositionBasis: CompositionUnit = .moleFraction,
        orderedComposition: [MixtureComponent]
    ) -> InletStreamInput {
        InletStreamInput(
            id: id,
            name: name,
            flowValue: flowValue,
            flowUnit: flowUnit,
            pressureValue: pressureValue,
            pressureUnit: pressureUnit,
            temperatureValue: temperatureValue,
            temperatureUnit: temperatureUnit,
            originalComposition: orderedComposition.map {
                CompositionInputSnapshot(
                    component: $0.component,
                    value: displayValue(for: $0.moleFraction, basis: compositionBasis),
                    unit: compositionBasis
                )
            },
            composition: orderedComposition
        )
    }

    private func streamFromOriginal(
        id: UUID = UUID(),
        name: String,
        flowValue: Double = 1,
        flowUnit: StreamFlowUnit = .molesPerSecond,
        originalComposition: [CompositionInputSnapshot],
        composition: [MixtureComponent],
        normalizedComposition: [MixtureComponent]? = nil
    ) -> InletStreamInput {
        InletStreamInput(
            id: id,
            name: name,
            flowValue: flowValue,
            flowUnit: flowUnit,
            pressureValue: 120,
            pressureUnit: .bara,
            temperatureValue: 25,
            temperatureUnit: .celsius,
            originalComposition: originalComposition,
            composition: composition,
            normalizedComposition: normalizedComposition
        )
    }

    private func displayValue(
        for moleFraction: Double,
        basis: CompositionUnit
    ) -> Double {
        switch basis {
        case .moleFraction:
            moleFraction
        case .molePercent:
            moleFraction * 100
        case .partsPerMillion:
            moleFraction * 1_000_000
        case .massFraction:
            moleFraction
        }
    }

    private func moleFraction(
        _ component: ComponentID,
        in result: MixedCompositionResult
    ) -> Double {
        result.composition.first { $0.component == component }?.moleFraction ?? 0
    }

    private func componentFlow(
        _ component: ComponentID,
        in result: MixedCompositionResult
    ) -> Double {
        result.componentMolarFlows.first {
            $0.component == component
        }?.molarFlowMolesPerSecond ?? 0
    }

    private func assertComposition(
        _ actual: [MixtureComponent],
        matches expected: [MixtureComponent],
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual.map(\.component)), Set(expected.map(\.component)), file: file, line: line)
        for item in expected {
            let actualValue = actual.first { $0.component == item.component }?.moleFraction
            XCTAssertEqual(actualValue ?? .nan, item.moleFraction, accuracy: accuracy, file: file, line: line)
        }
    }

    private func permutations<T>(of values: [T]) -> [[T]] {
        guard let first = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { permutation in
            (0...permutation.count).map { index in
                var copy = permutation
                copy.insert(first, at: index)
                return copy
            }
        }
    }
}

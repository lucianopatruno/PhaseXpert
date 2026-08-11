import XCTest
@testable import PhaseXpertCore

final class UnitConversionTests: XCTestCase {
    func testPressureConversions() {
        XCTAssertEqual(PressureUnit.megapascal.toPascal(15), 15_000_000, accuracy: 1e-9)
        XCTAssertEqual(PressureUnit.bar.toPascal(1), 100_000, accuracy: 1e-9)
        XCTAssertEqual(PressureUnit.psi.toPascal(1), 6_894.757_293_168, accuracy: 1e-9)
        XCTAssertEqual(PressureUnit.psia.fromPascal(6_894.757_293_168), 1, accuracy: 1e-12)
    }

    func testGaugePressureUsesExplicitAtmosphericReference() {
        XCTAssertEqual(
            PressureUnit.barg.toPascal(10, atmosphericReferencePa: 101_325),
            1_101_325,
            accuracy: 1e-9
        )
    }

    func testTemperatureConversions() {
        XCTAssertEqual(TemperatureUnit.celsius.toKelvin(0), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toKelvin(0), 255.3722222222222, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toKelvin(32), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toKelvin(212), 373.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.kelvin.fromKelvin(300), 300, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.fahrenheit.fromKelvin(373.15), 212, accuracy: 1e-12)
    }

    func testDynamicViscosityConversions() {
        XCTAssertEqual(
            DynamicViscosityUnit.millipascalSecond.fromPascalSeconds(0.000_071),
            0.071,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            DynamicViscosityUnit.millipascalSecond.toPascalSeconds(0.071),
            0.000_071,
            accuracy: 1e-12
        )
    }

    func testStreamMassFlowConversions() throws {
        XCTAssertEqual(
            try XCTUnwrap(StreamFlowUnit.kilogramsPerSecond.kilogramsPerSecond(from: 2)),
            2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(StreamFlowUnit.kilogramsPerHour.kilogramsPerSecond(from: 7_200)),
            2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(StreamFlowUnit.tonnesPerHour.kilogramsPerSecond(from: 7.2)),
            2,
            accuracy: 1e-12
        )
        XCTAssertNil(StreamFlowUnit.molesPerSecond.kilogramsPerSecond(from: 2))
    }

    func testStreamMolarFlowConversions() throws {
        XCTAssertEqual(
            try XCTUnwrap(StreamFlowUnit.molesPerSecond.molesPerSecond(from: 2)),
            2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(StreamFlowUnit.kilomolesPerHour.molesPerSecond(from: 7.2)),
            2,
            accuracy: 1e-12
        )
        XCTAssertNil(StreamFlowUnit.kilogramsPerSecond.molesPerSecond(from: 2))
    }

    func testStreamFlowRoundTrips() throws {
        let mass = 0.123_456_789
        for unit in [
            StreamFlowUnit.kilogramsPerSecond,
            .kilogramsPerHour,
            .tonnesPerHour
        ] {
            let displayed = try XCTUnwrap(unit.displayMassFlow(fromKilogramsPerSecond: mass))
            let roundTrip = try XCTUnwrap(unit.kilogramsPerSecond(from: displayed))
            XCTAssertEqual(roundTrip, mass, accuracy: 1e-12)
        }

        let molar = 987.654_321
        for unit in [StreamFlowUnit.molesPerSecond, .kilomolesPerHour] {
            let displayed = try XCTUnwrap(unit.displayMolarFlow(fromMolesPerSecond: molar))
            let roundTrip = try XCTUnwrap(unit.molesPerSecond(from: displayed))
            XCTAssertEqual(roundTrip, molar, accuracy: 1e-9)
        }
    }

    func testStreamCompositionConverterPreservesPhysicalCompositionAcrossBases() throws {
        let converter = StreamCompositionConverter()
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let moleFractions = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.5),
            MixtureComponent(component: .nitrogen, moleFraction: 0.5)
        ]
        let mixtureMass = 0.5 * co2Mass + 0.5 * nitrogenMass
        let expectedCO2MassFraction = 0.5 * co2Mass / mixtureMass
        let expectedNitrogenMassFraction = 0.5 * nitrogenMass / mixtureMass

        let massSnapshots = try converter.compositionSnapshots(
            from: moleFractions,
            basis: .massFraction
        )
        XCTAssertEqual(
            massSnapshots.first { $0.component == .carbonDioxide }?.value ?? .nan,
            expectedCO2MassFraction,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            massSnapshots.first { $0.component == .nitrogen }?.value ?? .nan,
            expectedNitrogenMassFraction,
            accuracy: 1e-12
        )

        let roundTrip = try converter.moleFractions(from: massSnapshots)
        XCTAssertEqual(
            roundTrip.first { $0.component == .carbonDioxide }?.moleFraction ?? .nan,
            0.5,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            roundTrip.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
            0.5,
            accuracy: 1e-12
        )
    }

    func testStreamCompositionConversionCandidateAcceptsValidMassFractionOnlyAsEntered() throws {
        let converter = StreamCompositionConverter()
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let nitrogenMass = try XCTUnwrap(ComponentID.nitrogen.molarMassKilogramsPerMole)
        let mixtureMass = 0.2 * co2Mass + 0.8 * nitrogenMass
        let original = [
            CompositionInputSnapshot(
                component: .carbonDioxide,
                value: 0.2 * co2Mass / mixtureMass,
                unit: .massFraction
            ),
            CompositionInputSnapshot(
                component: .nitrogen,
                value: 0.8 * nitrogenMass / mixtureMass,
                unit: .massFraction
            )
        ]

        let candidate = try converter.conversionCandidate(from: original)

        XCTAssertEqual(candidate.requirement, .validAsEntered)
        XCTAssertNil(candidate.normalizedComposition)
        XCTAssertEqual(
            candidate.convertedComposition.first { $0.component == .carbonDioxide }?.moleFraction ?? .nan,
            0.2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            candidate.convertedComposition.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
            0.8,
            accuracy: 1e-12
        )
    }

    func testStreamCompositionConversionCandidateRequiresExplicitNormalizationForNearMassFraction() throws {
        let converter = StreamCompositionConverter()
        let candidate = try converter.conversionCandidate(from: [
            .init(component: .carbonDioxide, value: 0.5002, unit: .massFraction),
            .init(component: .nitrogen, value: 0.5002, unit: .massFraction)
        ])

        XCTAssertEqual(candidate.requirement, .explicitNormalizationRequired)
        XCTAssertNotNil(candidate.normalizedComposition)
    }

    func testStreamCompositionConversionCandidateRejectsFarAndZeroMassFractionTotals() {
        let converter = StreamCompositionConverter()
        XCTAssertThrowsError(try converter.conversionCandidate(from: [
            .init(component: .carbonDioxide, value: 0.6, unit: .massFraction),
            .init(component: .nitrogen, value: 0.6, unit: .massFraction)
        ])) { error in
            XCTAssertEqual(error as? StreamMixingConversionError, .invalidCompositionTotal)
        }
        XCTAssertThrowsError(try converter.conversionCandidate(from: [
            .init(component: .carbonDioxide, value: 0, unit: .massFraction),
            .init(component: .nitrogen, value: 0, unit: .massFraction)
        ])) { error in
            XCTAssertEqual(error as? StreamMixingConversionError, .invalidCompositionTotal)
        }
    }

    func testStreamCompositionConversionCandidateRejectsMissingMassFractionMolarMass() {
        let converter = StreamCompositionConverter()
        XCTAssertThrowsError(try converter.conversionCandidate(from: [
            .init(component: .carbonDioxide, value: 0.99, unit: .massFraction),
            .init(component: .helium, value: 0.01, unit: .massFraction)
        ])) { error in
            XCTAssertEqual(error as? StreamMixingConversionError, .missingMolarMass(.helium))
        }
    }

    func testStreamCompositionConverterRoundTripsEveryMoleBasis() throws {
        let converter = StreamCompositionConverter()
        let moleFractions = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.97),
            MixtureComponent(component: .nitrogen, moleFraction: 0.03)
        ]

        for basis in [CompositionUnit.moleFraction, .molePercent, .partsPerMillion] {
            let displayed = try converter.compositionSnapshots(
                from: moleFractions,
                basis: basis
            )
            let roundTrip = try converter.moleFractions(from: displayed)
            XCTAssertEqual(
                roundTrip.first { $0.component == .carbonDioxide }?.moleFraction ?? .nan,
                0.97,
                accuracy: 1e-12
            )
            XCTAssertEqual(
                roundTrip.first { $0.component == .nitrogen }?.moleFraction ?? .nan,
                0.03,
                accuracy: 1e-12
            )
        }
    }

    func testStreamCompositionConverterRejectsMissingMolarMassForMassFraction() {
        let converter = StreamCompositionConverter()
        XCTAssertThrowsError(try converter.moleFractions(from: [
            .init(component: .carbonDioxide, value: 0.99, unit: .massFraction),
            .init(component: .helium, value: 0.01, unit: .massFraction)
        ])) { error in
            XCTAssertEqual(error as? StreamMixingConversionError, .missingMolarMass(.helium))
        }
    }

    func testStreamFlowConverterPreservesPhysicalFlowAcrossBases() throws {
        let converter = StreamFlowConverter()
        let co2Mass = try XCTUnwrap(ComponentID.carbonDioxide.molarMassKilogramsPerMole)
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 1)
        ]

        let molar = try converter.convertedFlowValue(
            co2Mass,
            from: .kilogramsPerSecond,
            to: .molesPerSecond,
            composition: composition
        )
        XCTAssertEqual(molar, 1, accuracy: 1e-12)

        let mass = try converter.convertedFlowValue(
            1,
            from: .molesPerSecond,
            to: .kilogramsPerSecond,
            composition: composition
        )
        XCTAssertEqual(mass, co2Mass, accuracy: 1e-12)
    }

    func testStreamFlowConverterRejectsMissingMolarMassCrossBasisConversion() {
        let converter = StreamFlowConverter()
        XCTAssertThrowsError(try converter.convertedFlowValue(
            1,
            from: .kilogramsPerSecond,
            to: .molesPerSecond,
            composition: [
                .init(component: .helium, moleFraction: 1)
            ]
        )) { error in
            XCTAssertEqual(error as? StreamMixingConversionError, .missingMolarMass(.helium))
        }
    }
}

import XCTest
@testable import PhaseXpertCore

final class BuiltInCaseCatalogTests: XCTestCase {
    func testCatalogContainsStableIdentifiers() {
        XCTAssertEqual(BuiltInCaseCatalog.cases.map(\.id), [
            "northern-lights-cargo-specification-example",
            "brevik-ccs-conditioned-export-example",
            "hafslund-celsio-oslo-ccs-project-information",
            "ravenna-ccs-phase-1-project-information",
            "porthos-pipeline-specification-example",
            "aramis-ship-specification-example"
        ])
    }

    func testCatalogNamesDefaultsSourcesAndLabels() throws {
        let northernLights = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("northern-lights-cargo-specification-example"))
        XCTAssertEqual(northernLights.name, "Northern Lights cargo specification example")
        XCTAssertEqual(try XCTUnwrap(northernLights.defaultPressurePa), 1_600_000)
        XCTAssertEqual(try XCTUnwrap(northernLights.defaultTemperatureK), 247.15, accuracy: 1e-12)
        XCTAssertEqual(northernLights.label, "Representative source-based case")
        XCTAssertTrue(northernLights.projectFacts.contains { $0.contains("Four ships") })
        XCTAssertTrue(northernLights.projectFacts.contains { $0.contains("110 km") })
        XCTAssertEqual(northernLights.sources.map { $0.url.absoluteString }, [
            "https://norlights.com/wp-content/uploads/2021/03/Northern-Lights-Project-Concept-report.pdf",
            "https://ccsnorway.com/full-scale-capture-transport-and-storage/"
        ])
        XCTAssertTrue(northernLights.modelingBasis.contains("specification-limit example"))
        XCTAssertTrue(northernLights.assumptions.contains {
            $0.contains("do not define a continuously fixed project stream")
        })
        XCTAssertTrue(northernLights.limitations.contains {
            $0.contains("just below the saturation boundary")
        })

        let brevik = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("brevik-ccs-conditioned-export-example"))
        XCTAssertEqual(brevik.name, "Heidelberg Materials – Brevik CCS conditioned export example")
        XCTAssertEqual(try XCTUnwrap(brevik.defaultPressurePa), 1_600_000)
        XCTAssertEqual(try XCTUnwrap(brevik.defaultTemperatureK), 247.15, accuracy: 1e-12)
        XCTAssertTrue(brevik.projectFacts.contains { $0.contains("400,000 tonnes") })
        XCTAssertEqual(brevik.sources.map { $0.url.absoluteString }, [
            "https://www.heidelbergmaterials.com/sites/default/files/2022-09/HeidelbergCement_SustainabilityLinkedFinancingFramework_V2_20220916.pdf",
            "https://ccsnorway.com/full-scale-capture-transport-and-storage/"
        ])
        XCTAssertTrue(brevik.assumptions.contains {
            $0.contains("N2 closure is an explicit PhaseXpert modeling assumption")
        })

        let celsio = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("hafslund-celsio-oslo-ccs-project-information"))
        XCTAssertEqual(celsio.name, "Hafslund Celsio – Oslo CCS")
        XCTAssertEqual(celsio.label, "Project information")
        XCTAssertFalse(celsio.hasCalculationPreset)
        XCTAssertNil(celsio.defaultPressurePa)
        XCTAssertNil(celsio.defaultTemperatureK)
        XCTAssertNil(celsio.composition)
        XCTAssertTrue(celsio.modelingBasis.contains("No public authoritative exact CO₂ composition"))
        XCTAssertTrue(celsio.projectFacts.contains { $0.contains("350,000 tonnes") })
        XCTAssertTrue(celsio.projectFacts.contains { $0.contains("four days") })

        let ravenna = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("ravenna-ccs-phase-1-project-information"))
        XCTAssertEqual(ravenna.name, "Ravenna CCS – Phase 1")
        XCTAssertEqual(ravenna.label, "Project information")
        XCTAssertFalse(ravenna.hasCalculationPreset)
        XCTAssertNil(ravenna.defaultPressurePa)
        XCTAssertNil(ravenna.defaultTemperatureK)
        XCTAssertNil(ravenna.composition)
        XCTAssertTrue(ravenna.projectFacts.contains { $0.contains("25,000 tonnes") })
        XCTAssertTrue(ravenna.projectFacts.contains { $0.contains("3,000 m") })
        XCTAssertTrue(ravenna.modelingBasis.contains("do not publish an exact conditioned CO₂ composition"))

        let porthos = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("porthos-pipeline-specification-example"))
        XCTAssertEqual(porthos.name, "Porthos pipeline specification example")
        XCTAssertEqual(try XCTUnwrap(porthos.defaultPressurePa), 3_100_000)
        XCTAssertEqual(try XCTUnwrap(porthos.defaultTemperatureK), 293.15, accuracy: 1e-12)
        XCTAssertEqual(porthos.sources.map { $0.url.absoluteString }, [
            "https://www.porthosco2.nl/wp-content/uploads/2021/09/CO2-specifications.pdf",
            "https://www.porthosco2.nl/wp-content/uploads/2022/03/Porthos-standard-CO2-Transport-and-Storage-Conditions.pdf"
        ])
        XCTAssertTrue(porthos.assumptions.contains {
            $0.contains("31 bar(a) and 20 °C are PhaseXpert defaults")
        })

        let aramis = try XCTUnwrap(BuiltInCaseCatalog.caseWithID("aramis-ship-specification-example"))
        XCTAssertEqual(aramis.name, "Aramis ship specification example")
        XCTAssertEqual(try XCTUnwrap(aramis.defaultPressurePa), 1_600_000)
        XCTAssertEqual(try XCTUnwrap(aramis.defaultTemperatureK), 248.15, accuracy: 1e-12)
        XCTAssertEqual(aramis.sources.map { $0.url.absoluteString }, [
            "https://www.aramis-ccs.com/news/co2-specifications-for-aramis-transport-infrastructure/"
        ])
        XCTAssertTrue(aramis.assumptions.contains {
            $0.contains("16 bar(a) and -25 °C are PhaseXpert shipping defaults")
        })
    }

    func testCatalogCompositionsAreExactAndTotalOneHundredMolPercent() throws {
        try assertComposition(
            "northern-lights-cargo-specification-example",
            [
                .carbonDioxide: 99.9831,
                .carbonMonoxide: 0.0100,
                .hydrogen: 0.0050,
                .oxygen: 0.0010,
                .hydrogenSulfide: 0.0009
            ]
        )
        try assertComposition(
            "brevik-ccs-conditioned-export-example",
            [
                .carbonDioxide: 99.0000,
                .nitrogen: 0.9831,
                .carbonMonoxide: 0.0100,
                .hydrogen: 0.0050,
                .oxygen: 0.0010,
                .hydrogenSulfide: 0.0009
            ]
        )
        try assertComposition(
            "porthos-pipeline-specification-example",
            [
                .carbonDioxide: 96.0000,
                .nitrogen: 2.4000,
                .methane: 1.0000,
                .argon: 0.4000,
                .hydrogen: 0.2000
            ]
        )
        try assertComposition(
            "aramis-ship-specification-example",
            [
                .carbonDioxide: 99.8000,
                .carbonMonoxide: 0.1200,
                .hydrogen: 0.0500,
                .nitrogen: 0.0290,
                .oxygen: 0.0010
            ]
        )
    }

    private func assertComposition(
        _ id: String,
        _ expectedMolPercent: [ComponentID: Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let builtInCase = try XCTUnwrap(BuiltInCaseCatalog.caseWithID(id), file: file, line: line)
        let composition = try XCTUnwrap(builtInCase.composition, file: file, line: line)
        XCTAssertEqual(Set(composition.map(\.component)), Set(expectedMolPercent.keys), file: file, line: line)
        let total = composition.reduce(0) { $0 + $1.moleFraction }
        XCTAssertEqual(total, 1, accuracy: 1e-12, file: file, line: line)
        for component in composition {
            XCTAssertEqual(
                component.moleFraction * 100,
                try XCTUnwrap(expectedMolPercent[component.component], file: file, line: line),
                accuracy: 1e-12,
                file: file,
                line: line
            )
        }
    }
}

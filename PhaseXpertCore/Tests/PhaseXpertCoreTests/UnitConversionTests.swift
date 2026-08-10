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
}

import PhaseXpertCore
import XCTest

final class PhaseXpertTests: XCTestCase {
    func testDefaultRegistryContainsBothFutureProductionProviders() {
        let identifiers = Set(ProviderRegistry().descriptors.map(\.id))
        XCTAssertTrue(identifiers.contains("coolprop-heos"))
        XCTAssertTrue(identifiers.contains("ife-model"))
    }
}


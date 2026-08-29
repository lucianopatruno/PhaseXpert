import Foundation

public struct ProviderRegistry: Sendable {
    public let providers: [any ThermodynamicModelProvider]
    private let extraDescriptors: [ModelDescriptor]

    public init(
        providers: [any ThermodynamicModelProvider] = ProviderRegistry.defaults,
        extraDescriptors: [ModelDescriptor] = [ProviderRegistry.ifeModelDescriptor]
    ) {
        self.providers = providers
        self.extraDescriptors = extraDescriptors
    }

    public var descriptors: [ModelDescriptor] {
        providers.map(\.descriptor) + extraDescriptors
    }

    /// Models intentionally exposed as choices in normal product workflows.
    public var userFacingDescriptors: [ModelDescriptor] {
        descriptors.filter { $0.id == "coolprop-heos" || $0.id == "ife-model" }
    }

    public func provider(id: String) -> (any ThermodynamicModelProvider)? {
        providers.first { $0.descriptor.id == id }
    }

    public static var defaults: [any ThermodynamicModelProvider] {
        [
            defaultCoolPropProvider,
            defaultTeqpProvider
        ]
    }

    private static var defaultCoolPropProvider: any ThermodynamicModelProvider {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        CoolPropProvider(engine: NativeCoolPropEngine())
        #else
        CoolPropProvider(engine: UnavailableCoolPropEngine())
        #endif
    }

    private static var defaultTeqpProvider: any ThermodynamicModelProvider {
        TeqpProvider(engine: NativeTeqpEngine())
    }

    public static let ifeModelDescriptor = ModelDescriptor(
        id: "ife-model",
        name: "IFE Model",
        modelVersion: "Under development",
        providerVersion: "Under development",
        availability: .unavailable,
        calculationMode: .hybrid,
        supportedComponents: [],
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: "IFE Flow Technology is developing a proprietary thermodynamic model for CO₂ and CO₂-rich systems, supported by experimental validation including measurements in the FALCON CO₂ facility.",
        equationOrMethod: "Under development",
        limitations: ["Under development"],
        references: []
    )
}

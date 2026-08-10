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

    public func provider(id: String) -> (any ThermodynamicModelProvider)? {
        providers.first { $0.descriptor.id == id }
    }

    public static var defaults: [any ThermodynamicModelProvider] {
        [
            defaultCoolPropProvider
        ]
    }

    private static var defaultCoolPropProvider: any ThermodynamicModelProvider {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        CoolPropProvider(engine: NativeCoolPropEngine())
        #else
        CoolPropProvider(engine: UnavailableCoolPropEngine())
        #endif
    }

    public static let ifeModelDescriptor = ModelDescriptor(
        id: "ife-model",
        name: "IFE Model",
        modelVersion: "Unavailable",
        providerVersion: "Unavailable",
        availability: .unavailable,
        calculationMode: .hybrid,
        supportedComponents: [],
        supportedProperties: [],
        domain: .initialCO2Transport,
        scientificBasis: "Provider interface reserved for a validated IFE implementation.",
        equationOrMethod: "This model is not available in this version.",
        limitations: ["This model is not available in this version."],
        references: []
    )
}

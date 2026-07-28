import SwiftUI

extension Color {
    static let ifePrimary = Color("IFEPrimary")
    static let ifeText = Color("IFEText")
    static let ifeBackground = Color("IFEBackground")
    static let ifeSignal = Color("IFESignal")
    static let ifeLavender = Color("IFELavender")
    static let ifeBlue = Color("IFEBlue")
}

enum IFESpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
}

struct IFECard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(IFESpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.ifeLavender.opacity(0.8), lineWidth: 1)
            }
    }
}

struct ScientificStatusBanner: View {
    let title: String
    let message: String
    var isError = false

    var body: some View {
        HStack(alignment: .top, spacing: IFESpacing.small) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? .red : Color.ifePrimary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
            }
        }
        .padding(IFESpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? Color.red : Color.ifeBlue).opacity(isError ? 0.10 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FeaturePlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .navigationTitle(title)
            .background(Color.ifeBackground.ignoresSafeArea())
    }
}

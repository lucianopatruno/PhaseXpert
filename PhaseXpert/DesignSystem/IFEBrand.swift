import SwiftUI
import UIKit

extension Color {
    static let ifePrimary = Color("IFEPrimary")
    static let ifeText = Color("IFEText")
    static let ifeBackground = Color("IFEBackground")
    static let ifeSignal = Color("IFESignal")
    static let ifeLavender = Color("IFELavender")
    static let ifeBlue = Color("IFEBlue")

    static let pxSurface = Color(.secondarySystemGroupedBackground)
    static let pxGroupedSurface = Color(.systemGroupedBackground)
    static let pxSeparator = Color(.separator)
    static let pxSuccess = Color(.systemGreen)
    static let pxWarning = Color(.systemOrange)
    static let pxUnavailable = Color(.systemGray)
    static let pxError = Color(.systemRed)
    static let pxChartBoundary = Color.ifePrimary
    static let pxChartCritical = Color.ifeSignal
    static let pxChartOperatingPoint = Color.ifeText
}

enum IFESpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let regular: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
}

enum IFECornerRadius {
    static let field: CGFloat = 8
    static let card: CGFloat = 8
    static let section: CGFloat = 12
}

enum IFELine {
    static let hairline: CGFloat = 1
    static let focus: CGFloat = 1.5
}

enum IFETypography {
    static let sectionTitle = Font.subheadline.weight(.semibold)
    static let cardTitle = Font.headline
    static let label = Font.subheadline.weight(.medium)
    static let value = Font.body.monospacedDigit()
    static let metadata = Font.caption
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
            .background(Color.pxSurface)
            .clipShape(RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
                    .stroke(Color.pxSeparator.opacity(0.55), lineWidth: IFELine.hairline)
            }
    }
}

struct IFEBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorContrast

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWave(in: &context, size: size, originY: size.height * 0.78, amplitude: 38, phase: 0)
                drawWave(in: &context, size: size, originY: size.height * 0.16, amplitude: 22, phase: .pi)
            }
        }
        .background(Color.ifeBackground)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    private func drawWave(
        in context: inout GraphicsContext,
        size: CGSize,
        originY: CGFloat,
        amplitude: CGFloat,
        phase: CGFloat
    ) {
        let color = colorScheme == .dark ? Color.ifeLavender : Color.ifeBlue
        let opacity = colorContrast == .increased ? 0.16 : (colorScheme == .dark ? 0.10 : 0.075)
        let spacing: CGFloat = 18
        let rows = 5
        for row in 0..<rows {
            var x: CGFloat = -spacing
            while x <= size.width + spacing {
                let normalized = x / max(size.width, 1)
                let y = originY
                    + CGFloat(row) * spacing
                    + sin(normalized * .pi * 2 + phase + CGFloat(row) * 0.3) * amplitude
                let radius: CGFloat = row.isMultiple(of: 2) ? 1.8 : 1.35
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(opacity))
                )
                x += spacing
            }
        }
    }
}

extension View {
    func ifeDottedBackground() -> some View {
        background { IFEBackground() }
    }
}

struct IFEStatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, IFESpacing.small)
            .padding(.vertical, IFESpacing.xSmall)
            .background(color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.35), lineWidth: IFELine.hairline)
            }
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}

struct IFESectionHeader: View {
    let step: Int?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: IFESpacing.small) {
                if let step {
                    Text("\(step)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.ifePrimary, in: Circle())
                        .accessibilityLabel("Step \(step)")
                }
                Text(title)
                    .font(IFETypography.sectionTitle)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

struct IFEValueRow: View {
    let title: String
    let value: String
    var unit: String?
    var status: String?
    var statusColor: Color = .secondary
    var copyValue: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IFESpacing.regular) {
            VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
                Text(title)
                    .font(IFETypography.label)
                if let status {
                    Text(status)
                        .font(IFETypography.metadata)
                        .foregroundStyle(statusColor)
                }
            }
            Spacer(minLength: IFESpacing.medium)
            VStack(alignment: .trailing, spacing: IFESpacing.xSmall) {
                Text([value, unit].compactMap { $0 }.joined(separator: " "))
                    .font(IFETypography.value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .accessibilityLabel(accessibilityValueText)
                if let copyValue {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = copyValue
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy \(title) value")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var accessibilityValueText: String {
        [value, unit].compactMap { $0 }.joined(separator: " ")
    }
}

/// App-owned disclosure row whose label matches the body typography used by
/// neighboring Form buttons and navigation links.
struct IFEExpandableRow<Content: View>: View {
    let title: String
    private let content: Content
    @State private var isExpanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
            }
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
        .clipShape(RoundedRectangle(cornerRadius: IFECornerRadius.section, style: .continuous))
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

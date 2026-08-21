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
                drawWaveBand(
                    in: &context,
                    size: size,
                    origin: CGPoint(x: size.width * 0.35, y: size.height * 0.67),
                    width: size.width * 0.88,
                    amplitude: size.height * 0.09,
                    rows: 9,
                    spacing: 14,
                    phase: 0.15,
                    weight: 1
                )
                drawWaveBand(
                    in: &context,
                    size: size,
                    origin: CGPoint(x: -size.width * 0.18, y: size.height * 0.08),
                    width: size.width * 0.58,
                    amplitude: size.height * 0.045,
                    rows: 5,
                    spacing: 16,
                    phase: .pi * 0.8,
                    weight: 0.58
                )
            }
        }
        .background(Color.ifeBackground)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    private func drawWaveBand(
        in context: inout GraphicsContext,
        size: CGSize,
        origin: CGPoint,
        width: CGFloat,
        amplitude: CGFloat,
        rows: Int,
        spacing: CGFloat,
        phase: CGFloat,
        weight: Double
    ) {
        let baseOpacity = colorContrast == .increased
            ? 0.22
            : (colorScheme == .dark ? 0.15 : 0.17)

        for row in 0..<rows {
            var x = origin.x
            let rowOffset = CGFloat(row) * spacing
            let rowFade = 1 - Double(row) / Double(max(rows + 2, 1))

            while x <= size.width + spacing {
                let progress = (x - origin.x) / max(width, 1)
                let y = origin.y
                    + rowOffset
                    + sin(progress * .pi * 2.25 + phase + CGFloat(row) * 0.28) * amplitude
                    + progress * size.height * 0.16

                let edgeFade = min(max(Double(progress), 0), 1)
                let opacity = baseOpacity * weight * (0.45 + 0.55 * rowFade) * (0.35 + 0.65 * edgeFade)
                let radius = 1.7 + CGFloat((row % 3)) * 0.32
                let color = dotColor(for: row)

                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(opacity))
                )
                x += spacing * 0.86
            }
        }
    }

    private func dotColor(for row: Int) -> Color {
        if colorScheme == .dark {
            return row.isMultiple(of: 3) ? .ifeBlue : .ifeLavender
        }
        return row.isMultiple(of: 3) ? .ifeBlue : .ifePrimary
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

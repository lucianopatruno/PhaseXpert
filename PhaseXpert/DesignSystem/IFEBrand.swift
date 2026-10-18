import SwiftUI
import UIKit

// MARK: - Colour

extension Color {
    // IFE master palette (see "IFE master presentation"). Every colour here is
    // an asset with a light and a dark variant.
    static let ifePrimary = Color("IFEPrimary")
    static let ifeOnPrimary = Color("IFEOnPrimary")
    static let ifeText = Color("IFEText")
    static let ifeBackground = Color("IFEBackground")
    static let ifeCard = Color("IFECard")
    static let ifeSignal = Color("IFESignal")
    static let ifeLavender = Color("IFELavender")
    static let ifeBlue = Color("IFEBlue")
    static let ifePeach = Color("IFEPeach")
    static let ifeCream = Color("IFECream")
    static let ifeMist = Color("IFEMist")
    static let ifeViolet = Color("IFEViolet")
    static let ifeCoral = Color("IFECoral")
    static let ifeGreen = Color("IFEGreen")

    static let pxSurface = Color.ifeCard
    static let pxGroupedSurface = Color(.systemGroupedBackground)
    static let pxSeparator = Color(.separator)
    static let pxSuccess = Color.ifeGreen
    static let pxWarning = Color(.systemOrange)
    static let pxUnavailable = Color(.systemGray)
    static let pxError = Color.ifeSignal
    static let pxChartBoundary = Color.ifePrimary
    static let pxChartCritical = Color.ifeSignal
    static let pxChartOperatingPoint = Color.ifeText
}

// MARK: - Tokens

enum IFESpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let regular: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
}

enum IFECornerRadius {
    static let field: CGFloat = 12
    static let card: CGFloat = 16
    static let section: CGFloat = 20
}

enum IFELine {
    static let hairline: CGFloat = 1
    static let focus: CGFloat = 1.5
}

enum IFETypography {
    /// Large, confident screen and hero titles.
    static let screenTitle = Font.largeTitle.weight(.bold)
    /// Large result value on hero cards.
    static let hero = Font.system(.largeTitle, design: .default).weight(.semibold).monospacedDigit()
    static let sectionTitle = Font.headline
    static let cardTitle = Font.title3.weight(.semibold)
    static let eyebrow = Font.caption.weight(.semibold)
    static let label = Font.subheadline.weight(.medium)
    static let value = Font.body.monospacedDigit()
    static let metadata = Font.caption
}

// MARK: - Surfaces

/// A raised, rounded surface on the IFE background.
struct IFECard<Content: View>: View {
    private let tint: Color?
    private let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(IFESpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint ?? Color.ifeCard)
            .clipShape(RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
                    .stroke(Color.pxSeparator.opacity(0.35), lineWidth: IFELine.hairline)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

/// Decorative IFE halftone accent. It renders only when an `IFEBrandAccent`
/// image asset is present, so the app looks right with or without it.
struct IFEBrandAccent: View {
    var opacity: Double = 0.10

    var body: some View {
        if UIImage(named: "IFEBrandAccent") != nil {
            Image("IFEBrandAccent")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.ifeViolet)
                .opacity(opacity)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

/// Full-width tinted card for a screen's main message, such as a result.
struct IFEHeroCard<Content: View>: View {
    private let tint: Color
    private let content: Content

    init(tint: Color = .ifeLavender, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(IFESpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topTrailing) {
                    tint
                    IFEBrandAccent(opacity: 0.16)
                        .frame(width: 220)
                        .offset(x: 70, y: -40)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IFECornerRadius.section, style: .continuous))
    }
}

struct IFEBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.ifeBackground
            IFEBrandAccent(opacity: 0.07)
                .frame(width: 320)
                .offset(x: 110, y: -70)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

extension View {
    func ifeDottedBackground() -> some View {
        background { IFEBackground() }
    }

    /// Card-coloured rows for `Form` and `List` sections.
    func ifeCardRow() -> some View {
        listRowBackground(Color.ifeCard)
    }
}

// MARK: - Buttons

/// Primary, full-width call to action.
struct IFEFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, IFESpacing.medium)
            .foregroundStyle(Color.ifeOnPrimary)
            .background(
                isEnabled ? Color.ifePrimary : Color.pxUnavailable.opacity(0.45),
                in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous))
    }
}

/// Secondary, tinted action.
struct IFETonalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, IFESpacing.medium)
            .foregroundStyle(isEnabled ? Color.ifeText : Color.pxUnavailable)
            .background(
                Color.ifeLavender.opacity(isEnabled ? 1 : 0.5),
                in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous))
    }
}

extension ButtonStyle where Self == IFEFilledButtonStyle {
    static var ifeFilled: IFEFilledButtonStyle { IFEFilledButtonStyle() }
}

extension ButtonStyle where Self == IFETonalButtonStyle {
    static var ifeTonal: IFETonalButtonStyle { IFETonalButtonStyle() }
}

// MARK: - Components

struct IFEStatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, IFESpacing.regular)
            .padding(.vertical, IFESpacing.xSmall + 1)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}

struct IFESectionHeader: View {
    let step: Int?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: IFESpacing.small) {
                if let step {
                    Text("\(step)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.ifeOnPrimary)
                        .frame(width: 24, height: 24)
                        .background(Color.ifePrimary, in: Circle())
                        .accessibilityLabel("Step \(step)")
                }
                Text(title)
                    .font(IFETypography.sectionTitle)
                    .foregroundStyle(Color.ifeText)
                    .textCase(nil)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

/// Small stat for result summaries: a label above a prominent value.
struct IFEMetricTile: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String?
    var tint: Color = .ifeLavender

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.xSmall) {
            Text(title)
                .font(IFETypography.eyebrow)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.ifeText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(IFETypography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(IFESpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous))
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(isError ? Color.pxError : Color.ifePrimary)
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
        .background(
            isError ? Color.pxError.opacity(0.10) : Color.ifeBlue.opacity(0.55),
            in: RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
        )
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

// MARK: - Labels

/// Icon in a tinted rounded square, followed by the title. For list rows.
struct IFEIconLabelStyle: LabelStyle {
    var tint: Color = .ifeViolet

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: IFESpacing.regular) {
            configuration.icon
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            configuration.title
        }
    }
}

// MARK: - Pages

extension View {
    /// Raised IFE card surface: fill, hairline border and soft shadow.
    func ifeCardSurface(tint: Color? = nil) -> some View {
        background(
            tint ?? Color.ifeCard,
            in: RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
                .stroke(Color.pxSeparator.opacity(0.35), lineWidth: IFELine.hairline)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

/// A scrolling page of cards on the IFE background. Content is width-limited
/// so it stays readable on iPad.
struct IFEPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IFESpacing.large) {
                content
            }
            .padding(.horizontal, IFESpacing.medium)
            .padding(.vertical, IFESpacing.medium)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ifeDottedBackground()
    }
}

/// Small heading above a group of cards.
struct IFESectionTitle: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, IFESpacing.xSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled card holding related content.
struct IFEGroup<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IFESpacing.small) {
            if let title {
                IFESectionTitle(title)
            }
            VStack(alignment: .leading, spacing: IFESpacing.regular) {
                content
            }
            .padding(IFESpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ifeCardSurface()
        }
    }
}

/// Tinted introduction at the top of a page: an icon and a short message.
struct IFEPageHeader: View {
    let systemImage: String
    let message: LocalizedStringKey
    var tint: Color = .ifeLavender

    var body: some View {
        IFEHeroCard(tint: tint) {
            HStack(spacing: IFESpacing.medium) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ifePrimary)
                    .frame(width: 52, height: 52)
                    .background(
                        Color.ifeCard.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Text(message)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.ifeText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Card-style navigation row: icon tile, title, one-line description, chevron.
/// The accessibility label is exactly the title, with the description as a hint.
struct IFENavigationRow<Destination: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String
    private let tint: Color
    private let destination: Destination

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tint: Color = .ifeViolet,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: IFESpacing.regular) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.ifeText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: IFESpacing.small)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(IFESpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ifeCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? LocalizedStringKey(""))
    }
}

/// A label with its value on one line, for use inside an `IFEGroup`.
struct IFEInfoRow: View {
    private let title: LocalizedStringKey
    private let value: Text

    init(_ title: LocalizedStringKey, value: Text) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IFESpacing.regular) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: IFESpacing.regular)
            value
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.ifeText)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - List rows

/// Icon tile that leads a card row.
struct IFERowIcon: View {
    let systemImage: String
    var tint: Color = .ifeViolet

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(
                tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: IFECornerRadius.field, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

extension View {
    /// Soft capsule behind a short value, such as a pressure and temperature pair.
    func ifePill() -> some View {
        padding(.horizontal, IFESpacing.regular)
            .padding(.vertical, IFESpacing.xSmall)
            .background(Color.ifeMist.opacity(0.7), in: Capsule())
    }

    /// Presents a `List` row as a free-standing card.
    func ifeCardListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: IFESpacing.small,
                    leading: IFESpacing.large,
                    bottom: IFESpacing.small,
                    trailing: IFESpacing.large
                )
            )
            .listRowBackground(
                RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
                    .fill(Color.ifeCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: IFECornerRadius.card, style: .continuous)
                            .stroke(Color.pxSeparator.opacity(0.35), lineWidth: IFELine.hairline)
                    }
                    .padding(.vertical, IFESpacing.xSmall)
                    .padding(.horizontal, IFESpacing.medium)
            )
    }
}

extension View {
    /// Lets a button sit in a `Form` or `List` row without the row chrome.
    func ifeActionRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

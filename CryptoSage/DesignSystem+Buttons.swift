import SwiftUI

// MARK: - Premium Button Tokens
enum PremiumButtonTokens {
    static let primaryHeight: CGFloat = 36
    static let compactHeight: CGFloat = 30
    static let primaryCornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 12
    static let primaryHorizontalPadding: CGFloat = 16
    static let compactHorizontalPadding: CGFloat = 11
    static let primaryPressedScale: CGFloat = 0.98
    static let compactPressedScale: CGFloat = 0.985

    static func contentGradient(isDark: Bool) -> LinearGradient {
        isDark
            ? LinearGradient(
                colors: [BrandColors.goldLight, BrandColors.goldBase],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [BrandColors.goldBase, BrandColors.goldDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    static func radialGlassFill(isDark: Bool) -> RadialGradient {
        RadialGradient(
            colors: isDark
                ? [BrandColors.goldBase.opacity(0.14), BrandColors.goldBase.opacity(0.04), .clear]
                : [BrandColors.goldDark.opacity(0.08), BrandColors.goldDark.opacity(0.02), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 80
        )
    }

    static func topShine(isDark: Bool) -> LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(isDark ? 0.10 : 0.30), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.45)
        )
    }

    static func rimStroke(isDark: Bool) -> LinearGradient {
        LinearGradient(
            colors: isDark
                ? [BrandColors.goldBase.opacity(0.65), BrandColors.goldDark.opacity(0.30)]
                : [BrandColors.goldDark.opacity(0.40), BrandColors.goldBase.opacity(0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func secondaryFill(isDark: Bool) -> Color {
        isDark ? DS.Adaptive.chipBackground : Color(uiColor: .systemGray6)
    }

    static func secondaryStroke(isDark: Bool) -> Color {
        isDark ? DS.Adaptive.strokeStrong : Color.black.opacity(0.14)
    }
    
    static func accentFill(accent: Color, isDark: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(isDark ? 0.95 : 0.9),
                accent.opacity(isDark ? 0.72 : 0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static func accentRim(accent: Color, isDark: Bool) -> Color {
        isDark ? accent.opacity(0.7) : accent.opacity(0.5)
    }
}

// MARK: - Premium CTA Styles
struct PremiumPrimaryCTAStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat = PremiumButtonTokens.primaryHeight
    var horizontalPadding: CGFloat = PremiumButtonTokens.primaryHorizontalPadding
    var cornerRadius: CGFloat = PremiumButtonTokens.primaryCornerRadius
    var pressedScale: CGFloat = PremiumButtonTokens.primaryPressedScale
    var font: Font = .system(size: 14, weight: .semibold)

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .font(font)
            .foregroundStyle(PremiumButtonTokens.contentGradient(isDark: isDark))
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                ZStack {
                    shape.fill(PremiumButtonTokens.radialGlassFill(isDark: isDark))
                    shape.fill(PremiumButtonTokens.topShine(isDark: isDark)).padding(1)
                }
            )
            .overlay(
                shape.stroke(PremiumButtonTokens.rimStroke(isDark: isDark), lineWidth: isDark ? 1 : 1.2)
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.88), value: configuration.isPressed)
    }
}

struct PremiumCompactCTAStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat = PremiumButtonTokens.compactHeight
    var horizontalPadding: CGFloat = PremiumButtonTokens.compactHorizontalPadding
    var cornerRadius: CGFloat = PremiumButtonTokens.compactCornerRadius
    var pressedScale: CGFloat = PremiumButtonTokens.compactPressedScale
    var font: Font = .system(size: 12, weight: .semibold, design: .rounded)

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .font(font)
            .foregroundStyle(PremiumButtonTokens.contentGradient(isDark: isDark))
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                ZStack {
                    shape.fill(PremiumButtonTokens.radialGlassFill(isDark: isDark))
                    shape.fill(PremiumButtonTokens.topShine(isDark: isDark)).padding(1)
                }
            )
            .overlay(
                shape.stroke(PremiumButtonTokens.rimStroke(isDark: isDark), lineWidth: isDark ? 0.9 : 1.1)
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PremiumSecondaryCTAStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat = 34
    var horizontalPadding: CGFloat = 14
    var cornerRadius: CGFloat = 12
    var pressedScale: CGFloat = 0.985
    var font: Font = .system(size: 13, weight: .semibold)

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .font(font)
            .foregroundStyle(DS.Adaptive.textPrimary)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(shape.fill(PremiumButtonTokens.secondaryFill(isDark: isDark)))
            .overlay(shape.stroke(PremiumButtonTokens.secondaryStroke(isDark: isDark), lineWidth: 0.9))
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PremiumAccentCTAStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    var accent: Color
    var foregroundColor: Color = .white
    var height: CGFloat = PremiumButtonTokens.primaryHeight
    var horizontalPadding: CGFloat = PremiumButtonTokens.primaryHorizontalPadding
    var cornerRadius: CGFloat = PremiumButtonTokens.primaryCornerRadius
    var pressedScale: CGFloat = PremiumButtonTokens.primaryPressedScale
    var font: Font = .system(size: 14, weight: .semibold)
    
    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        configuration.label
            .font(font)
            .foregroundStyle(foregroundColor)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                ZStack {
                    shape.fill(PremiumButtonTokens.accentFill(accent: accent, isDark: isDark))
                    shape.fill(PremiumButtonTokens.topShine(isDark: isDark)).padding(1)
                }
            )
            .overlay(
                shape.stroke(PremiumButtonTokens.accentRim(accent: accent, isDark: isDark), lineWidth: isDark ? 1 : 1.1)
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.88), value: configuration.isPressed)
    }
}

// MARK: - Shared Button Styles
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var isSell: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            // Softer, tighter glow - reduced in light mode
            // Gentle grounding shadow - minimal in light mode
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}

struct CSGoldCapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = PremiumButtonTokens.primaryHeight
    var horizontalPadding: CGFloat = PremiumButtonTokens.primaryHorizontalPadding

    func makeBody(configuration: Configuration) -> some View {
        PremiumPrimaryCTAStyle(
            height: height,
            horizontalPadding: horizontalPadding,
            cornerRadius: height / 2,
            pressedScale: PremiumButtonTokens.primaryPressedScale,
            font: .system(size: 14, weight: .semibold)
        ).makeBody(configuration: configuration)
    }
}

// MARK: - Section CTA Button Style
/// A button style for "See All" / "View All" section navigation buttons
/// Features gold accent icon and chevron while maintaining subtle dark background
struct SectionCTAButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        
        configuration.label
            .scaleEffect(pressed ? 0.98 : 1.0)
            .opacity(pressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

// MARK: - Section CTA Button View
/// Reusable "See All" / "View All" button for home page sections
/// Clean, minimal design that matches the overall card aesthetic
struct SectionCTAButton: View {
    let title: String
    let icon: String
    var badge: String? = nil  // Optional badge (e.g., "9 events")
    var showGoldBar: Bool = true  // Toggle gold bar on left edge
    var accentColor: Color? = nil  // Optional semantic accent override (defaults to brand gold)
    var compact: Bool = false  // Reduced vertical padding for tight layouts
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Accent gradient for icon and chevron
    private var accentGradient: LinearGradient {
        if let accentColor {
            return LinearGradient(
                colors: [accentColor.opacity(isDark ? 0.95 : 0.9), accentColor.opacity(isDark ? 0.72 : 0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return isDark
            ? LinearGradient(
                colors: [BrandColors.goldLight, BrandColors.goldBase],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [BrandColors.goldBase, BrandColors.goldDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
    
    // Accent bar gradient
    private var accentBarGradient: LinearGradient {
        if let accentColor {
            return LinearGradient(
                colors: [accentColor.opacity(isDark ? 0.78 : 0.7), accentColor.opacity(isDark ? 0.56 : 0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return isDark
            ? LinearGradient(
                colors: [BrandColors.goldLight.opacity(0.75), BrandColors.goldBase.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
              )
            : LinearGradient(
                colors: [BrandColors.goldBase.opacity(0.70), BrandColors.goldDark.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
              )
    }
    
    // Glow accent — semantic override or gold fallback
    private var glowAccent: Color {
        if let accentColor {
            return accentColor
        }
        return isDark ? BrandColors.goldBase : BrandColors.goldDark
    }
    
    private var borderGradient: LinearGradient {
        if let accentColor {
            return LinearGradient(
                colors: isDark
                    ? [accentColor.opacity(0.35), DS.Adaptive.stroke.opacity(0.3)]
                    : [accentColor.opacity(0.28), accentColor.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: isDark
                ? [BrandColors.goldBase.opacity(0.30), DS.Adaptive.stroke.opacity(0.3)]
                : [BrandColors.goldDark.opacity(0.25), BrandColors.goldBase.opacity(0.10)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 8) {
                // Gold icon with luminous treatment
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentGradient)
                
                // Primary text
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Optional badge (e.g., "9 events")
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                        )
                }
                
                // Gold chevron with glow
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentGradient.opacity(0.8))
            }
            .padding(.leading, showGoldBar ? 16 : 14)
            .padding(.trailing, 14)
            .padding(.vertical, compact ? 8 : 12)
            .background(
                ZStack {
                    // Radial glass fill — warm gold-tinted depth
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowAccent.opacity(isDark ? 0.08 : 0.05),
                                    glowAccent.opacity(isDark ? 0.02 : 0.01),
                                    Color.clear
                                ],
                                center: .leading,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                    
                    // Top-highlight glass shine
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.06 : 0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.4)
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        borderGradient,
                        lineWidth: isDark ? 1 : 1.2
                    )
            )
            // Gold bar accent on left edge (optional)
            .overlay(alignment: .leading) {
                if showGoldBar {
                    Capsule()
                        .fill(accentBarGradient)
                        .frame(width: 3)
                        .padding(.vertical, compact ? 5 : 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SectionCTAButtonStyle())
        // Subtle outer glow for premium feel
    }
}

// MARK: - Convenience Initializer with Default Icon
extension SectionCTAButton {
    /// Creates a section CTA button with a default chevron-only style (no leading icon bar)
    /// Use the standard initializer for the full gold-accented style
    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = "arrow.right"
        self.action = action
    }
}

// MARK: - Chart Source Segmented Toggle (Shared)
/// Reusable segmented toggle for chart source selection (e.g., CryptoSage AI / TradingView)
/// Professional segmented control style with gold gradient for selected segment
/// Used by both CoinDetailView and TradeView for consistency
struct ChartSourceSegmentedToggle<T: Hashable>: View {
    @Binding var selected: T
    let options: [(value: T, label: String)]
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
        .padding(1)
        .background(DS.Adaptive.chipBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .frame(height: 28)
    }
    
    private func segment(_ type: T, label: String) -> some View {
        let isSelected = selected == type
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.12)) { selected = type }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity) // Expand segments evenly when toggle is wider
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                // Dark mode: dark text on gold chip; Light mode: white text on black chip
                .foregroundColor(isSelected
                    ? (isDark ? BrandColors.ctaTextColor(isDark: true) : .white)
                    : .primary.opacity(0.6))
                .background(
                    ZStack {
                        if isSelected {
                            // Selected chip: gold in dark, black in light (matches market page)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AdaptiveGradients.chipGold(isDark: isDark))
                            // Top highlight — glass shine
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(isDark ? 0.18 : 0.12), .clear], startPoint: .top, endPoint: .center))
                            // Rim stroke
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChartSourceSegmentedToggle Convenience for ChartType enum
extension ChartSourceSegmentedToggle where T == ChartType {
    /// Convenience initializer for ChartType enum used in CoinDetailView
    init(selected: Binding<ChartType>) {
        self._selected = selected
        self.options = [
            (.cryptoSageAI, "CryptoSage AI"),
            (.tradingView, "TradingView")
        ]
    }
}

// MARK: - ChartSourceSegmentedToggle Convenience for ChartSource enum
extension ChartSourceSegmentedToggle where T == ChartSource {
    /// Convenience initializer for ChartSource enum used in TradeView
    init(selected: Binding<ChartSource>) {
        self._selected = selected
        self.options = [
            (.sage, "CryptoSage AI"),
            (.trading, "TradingView")
        ]
    }
}

// MARK: - ChartSourceSegmentedToggle Convenience for StockChartType enum
extension ChartSourceSegmentedToggle where T == StockChartType {
    /// Convenience initializer for StockChartType enum used in StockDetailView
    init(selected: Binding<StockChartType>) {
        self._selected = selected
        self.options = [
            (.native, "CryptoSage AI"),
            (.tradingView, "TradingView")
        ]
    }
}

// MARK: - Legacy Chart Source Toggle Button (Deprecated)
/// Old individual toggle button - kept for backward compatibility
/// Prefer ChartSourceSegmentedToggle for new implementations
@available(*, deprecated, message: "Use ChartSourceSegmentedToggle instead for a unified segmented control style")
struct ChartSourceToggle: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? DS.Colors.gold : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.Colors.gold.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeframe Dropdown Button (Shared)
/// Reusable dropdown button for timeframe selection with chevron indicator
/// Uses capsule chip style with gold stroke for consistency with TradeView
/// Set `isActive` to true when the dropdown popover is open for visual feedback
struct TimeframeDropdownButton: View {
    let interval: String
    var isActive: Bool = false
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 4) {
                Text(interval)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: isActive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            // Active: accent color; Inactive: primary text
            .foregroundColor(isActive ? (isDark ? DS.Colors.gold : .black) : .primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    // Active: subtle tint; Inactive: neutral background
                    .fill(isActive 
                          ? (isDark ? DS.Colors.gold.opacity(0.15) : Color.black.opacity(0.08))
                          : (isDark ? DS.Neutral.bg(0.06) : Color(uiColor: .systemGray5)))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    // Active: stronger accent border; Inactive: subtle adaptive stroke
                    .stroke(
                        isActive 
                            ? LinearGradient(colors: [isDark ? DS.Colors.gold : Color.black], startPoint: .leading, endPoint: .trailing)
                            : AdaptiveGradients.ctaRimStroke(isDark: isDark),
                        lineWidth: isActive ? 1.2 : 0.8
                    )
                    .opacity(isDark ? 1 : 0.8)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Indicators Button (Shared)
/// Reusable indicators button with badge count overlay
/// Uses capsule chip style with badge as overlay for consistency with TradeView
struct IndicatorsButton: View {
    let count: Int
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private var isActive: Bool { count > 0 }
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    Text("Indicators")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundColor(.primary)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(isDark ? DS.Neutral.bg(0.06) : Color(uiColor: .systemGray5))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                        .opacity(isDark ? 1 : 0.8)
                )
                
                // Badge overlay
                if isActive {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDark ? .black : .white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(isDark ? DS.Colors.gold : Color.black)
                                .overlay(Circle().stroke(isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 0.6))
                        )
                        .offset(x: 6, y: -4)
                        .accessibilityHidden(true)
                }
            }
            // FIX: Ensure the entire button area is tappable, not just the visible content
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Indicators")
        .accessibilityValue(isActive ? "\(count) active" : "None")
    }
}

// MARK: - Underline Tab Picker (Shared)
/// Generic underline-style tab picker for Overview/News/Ideas tabs
/// Uses gold underline when selected, plain text when not selected
struct UnderlineTabPicker<Tab: RawRepresentable & CaseIterable & Hashable>: View where Tab.RawValue == String {
    @Binding var selected: Tab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                let isSelected = selected == tab
                
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
                        
                        Rectangle()
                            .fill(isSelected ? DS.Colors.gold : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

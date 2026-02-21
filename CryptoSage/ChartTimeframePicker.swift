import SwiftUI

/// A reusable, brand-styled timeframe picker that can be presented as a popover or a sheet.
/// - Use with: ChartTimeframePicker(isPresented: $flag, selection: $interval)
/// - Optionally pass a custom set of supported intervals.
struct ChartTimeframePicker: View {
    @Binding var isPresented: Bool
    @Binding var selection: ChartInterval
    var supported: [ChartInterval]
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    init(isPresented: Binding<Bool>, selection: Binding<ChartInterval>, supported: [ChartInterval]? = nil) {
        self._isPresented = isPresented
        self._selection = selection
        // Default list uses all supported intervals for comprehensive timeframe selection
        self.supported = supported ?? [.live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour, .oneDay, .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all]
    }
    
    // Adaptive colors for light/dark mode
    private var headerTextColor: Color { isDark ? .white.opacity(0.7) : .black.opacity(0.6) }
    private var closeButtonColor: Color { isDark ? .white.opacity(0.75) : .black.opacity(0.5) }
    private var dividerColor: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    private var glossTopColor: Color { isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.6) }
    private var strokeColor: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    private var shadowColor: Color { isDark ? Color.black.opacity(0.30) : Color.black.opacity(0.12) }
    private var panelFillColor: Color { isDark ? Color.clear : Color.white.opacity(0.85) }

    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack {
                Text("Timeframe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(headerTextColor)
                Spacer(minLength: 6)
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(closeButtonColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 6)

            // Grid of timeframe chips (adaptive columns; tight like Coinbase)
            let minChipWidth: CGFloat = 56
            let spacing: CGFloat = 5
            let horizontalPadding: CGFloat = 6
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minChipWidth), spacing: spacing)],
                alignment: .center,
                spacing: spacing
            ) {
                ForEach(supported, id: \.self) { interval in
                    timeframeChip(for: interval)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelFillColor)
        )
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [glossTopColor, .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: isDark ? 0.75 : 0.5)
                .allowsHitTesting(false)
        )
        .tint(DS.Colors.gold)
        .frame(minWidth: 236, maxWidth: 320)
    }

    @ViewBuilder
    private func timeframeChip(for interval: ChartInterval) -> some View {
        let selected = (interval == selection)
        
        // Adaptive chip colors
        let unselectedTextColor: Color = isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.75)
        let unselectedBgColor: Color = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let unselectedGlossColor: Color = isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.5)
        let unselectedStrokeColor: Color = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = interval
            }
            isPresented = false
        } label: {
            Text(interval.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(selected ? (isDark ? Color.black : Color.white) : unselectedTextColor)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    ZStack {
                        Capsule()
                            .fill(selected
                                  ? AnyShapeStyle(isDark ? chipGoldGradient : lightModeSelectedGradient)
                                  : AnyShapeStyle(unselectedBgColor))
                        // top gloss
                        Capsule()
                            .fill(LinearGradient(colors: [selected ? Color.white.opacity(isDark ? 0.18 : 0.10) : unselectedGlossColor, .clear], startPoint: .top, endPoint: .center))
                        // rim
                        Capsule()
                            .stroke(selected
                                    ? AnyShapeStyle(isDark ? ctaRimStrokeGradient : lightModeSelectedStroke)
                                    : AnyShapeStyle(unselectedStrokeColor),
                                    lineWidth: isDark ? 0.8 : 0.5)
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(interval.rawValue))
        .accessibilityAddTraits(selection == interval ? .isSelected : [])
    }
}

// MARK: - Light mode selected chip gradient (charcoal/dark instead of gold)
private var lightModeSelectedGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.22, green: 0.22, blue: 0.24), location: 0.0),
            .init(color: Color(red: 0.14, green: 0.14, blue: 0.16), location: 0.55),
            .init(color: Color(red: 0.10, green: 0.10, blue: 0.12), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private var lightModeSelectedStroke: LinearGradient {
    LinearGradient(colors: [Color.black.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
}

#Preview {
    @Previewable @State var showing = true
    @Previewable @State var interval: ChartInterval = .oneHour
    return ZStack {
        Color.black.ignoresSafeArea()
        ChartTimeframePicker(isPresented: $showing, selection: $interval)
            .padding()
    }
}

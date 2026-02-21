import SwiftUI

// MARK: - Improved Palette Chips (Adaptive for Light/Dark Mode)
private struct PaletteChoiceChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let palette: ColorPalette
    let selected: Bool
    let action: () -> Void
    
    private var isDark: Bool { colorScheme == .dark }

    /// Generates a gradient that samples actual palette colors via HeatMapSharedLib
    private func swatch(for p: ColorPalette) -> LinearGradient {
        // Sample the actual color function at key points to match real heat map appearance
        let bound: Double = 10.0  // Use a standard bound for preview
        let stops: [Gradient.Stop] = [
            .init(color: HeatMapSharedLib.color(for: -bound, bound: bound, palette: p), location: 0.0),       // Max red
            .init(color: HeatMapSharedLib.color(for: -bound * 0.5, bound: bound, palette: p), location: 0.25), // Mid red
            .init(color: HeatMapSharedLib.color(for: 0, bound: bound, palette: p), location: 0.5),            // Neutral
            .init(color: HeatMapSharedLib.color(for: bound * 0.5, bound: bound, palette: p), location: 0.75),  // Mid green
            .init(color: HeatMapSharedLib.color(for: bound, bound: bound, palette: p), location: 1.0)         // Max green
        ]
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? BrandColors.ctaTextColor(isDark: isDark) : DS.Adaptive.textPrimary.opacity(0.9))
                    Text(palette.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? BrandColors.ctaTextColor(isDark: isDark) : DS.Adaptive.textPrimary.opacity(0.92))
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(swatch(for: palette))
                    .frame(height: 8)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.Adaptive.stroke, lineWidth: 0.6))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if selected {
                        Capsule().fill(AdaptiveGradients.chipGold(isDark: isDark))
                            .overlay(
                                LinearGradient(colors: [Color.white.opacity(isDark ? 0.16 : 0.25), .clear], startPoint: .top, endPoint: .center)
                                    .clipShape(Capsule())
                            )
                            .overlay(Capsule().stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.9))
                    } else {
                        Capsule().fill(DS.Adaptive.chipBackground)
                            .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
                    }
                }
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(palette.displayName))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Premium Toggle Style (Adaptive Gold/Silver)
private struct HeatMapToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat = 52
    var height: CGFloat = 28
    
    private var isDark: Bool { colorScheme == .dark }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textPrimary)
            Spacer()
            Button {
                Haptics.light.impactOccurred()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { configuration.isOn.toggle() }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(configuration.isOn 
                              ? (isDark ? BrandColors.goldBase : BrandColors.silverBase)
                              : DS.Adaptive.chipBackground)
                        .frame(width: width, height: height)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(configuration.isOn 
                                        ? (isDark ? BrandColors.goldLight.opacity(0.6) : BrandColors.silverLight.opacity(0.6))
                                        : DS.Adaptive.stroke,
                                        lineWidth: 0.8)
                        )
                    Circle()
                        .fill(Color.white)
                        .frame(width: height - 4, height: height - 4)
                        .padding(2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(configuration.isOn ? "On" : "Off")
        }
    }
}

// MARK: - Small Choice Chip (Adaptive)
private struct SmallChoiceChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let selected: Bool
    let action: () -> Void
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(selected ? BrandColors.ctaTextColor(isDark: isDark) : DS.Adaptive.textPrimary.opacity(0.9))
                .background(
                    Group {
                        if selected {
                            Capsule()
                                .fill(AdaptiveGradients.chipGold(isDark: isDark))
                                .overlay(
                                    LinearGradient(colors: [Color.white.opacity(isDark ? 0.16 : 0.25), .clear], startPoint: .top, endPoint: .center)
                                        .clipShape(Capsule())
                                )
                                .overlay(Capsule().stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8))
                        } else {
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                                .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
                        }
                    }
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Section Card Wrapper
private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder let content: () -> Content
    
    init(_ title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.gold)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Main Settings Panel
struct EnhancedHeatMapSettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    @Binding var filterStables: Bool
    @Binding var includeOthers: Bool
    @Binding var weightByVolume: Bool
    @Binding var normalizeByBTC: Bool
    @Binding var showValues: Bool
    @Binding var pinBTC: Bool
    @Binding var autoHideInfoBar: Bool
    @Binding var whiteLabelsOnly: Bool
    @Binding var followLiveUpdates: Bool
    @Binding var autoRefreshEnabled: Bool
    @Binding var strongBorders: Bool
    @Binding var grayNeutral: Bool
    @Binding var proGreen: Bool
    @Binding var saturation: Double
    @Binding var boostSmallChanges: Bool
    @Binding var topN: Int
    @Binding var minUpdateSeconds: Int

    @Binding var weightingCurve: WeightingCurve
    @Binding var labelDensity: LabelDensity
    
    // PALETTE FIX: Read/write directly from AppStorage instead of binding
    // This ensures changes propagate correctly even across sheet boundaries
    @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
    private var palette: ColorPalette {
        get { ColorPalette(rawValue: paletteRaw) ?? .cool }
        nonmutating set { paletteRaw = newValue.rawValue }
    }

    @Binding var scaleModeRaw: String
    @Binding var globalBound: Double

    // Optional preview values for sheet presentation
    var boundPreview: Double? = nil
    var legendNoteText: String? = nil

    // Action
    var onRestoreDefaults: (() -> Void)? = nil
    
    private var isDark: Bool { colorScheme == .dark }

    enum ScaleMode: String, CaseIterable, Identifiable { case perTf = "pertf", global = "global"; var id: String { rawValue } }
    private var scaleMode: Binding<ScaleMode> {
        Binding<ScaleMode>(
            get: { ScaleMode(rawValue: scaleModeRaw) ?? .perTf },
            set: { newVal in scaleModeRaw = newVal.rawValue }
        )
    }
    enum RefreshEvery: Int, CaseIterable, Identifiable { case s30 = 30, s60 = 60, s120 = 120; var id: Int { rawValue }; var label: String { switch self { case .s30: return "30s"; case .s60: return "60s"; case .s120: return "2m" } } }
    private var refreshEvery: Binding<RefreshEvery> {
        Binding<RefreshEvery>(
            get: {
                let v = minUpdateSeconds
                if v <= 30 { return .s30 }
                if v <= 60 { return .s60 }
                return .s120
            },
            set: { newVal in
                minUpdateSeconds = newVal.rawValue
                // Ensure the safety-net timer is enabled when user selects an interval
                autoRefreshEnabled = true
            }
        )
    }

    private var previewBound: Double { boundPreview ?? globalBound }
    
    // Adaptive accent color for sliders and steppers
    private var accentColor: Color {
        isDark ? BrandColors.goldBase : BrandColors.silverBase
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Legend Preview Card
                VStack(alignment: .leading, spacing: 6) {
                    LegendView(bound: previewBound, note: legendNoteText, palette: palette)
                        // PALETTE FIX: Force re-render when palette changes
                        .id("legend-preview-\(palette.rawValue)")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )

                // MARK: - Color Scale Section
                SettingsSectionCard("Color Scale", icon: "paintpalette") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Scale mode picker
                        Picker("Color scale mode", selection: scaleMode) {
                            Label("Per timeframe", systemImage: "sparkles").tag(ScaleMode.perTf)
                            Label("Global", systemImage: "globe").tag(ScaleMode.global)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        // Scale mode description
                        switch scaleMode.wrappedValue {
                        case .perTf:
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto range (by timeframe)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Text("Each timeframe uses its own best-fit range (90th percentile).")
                                        .font(.caption)
                                        .foregroundStyle(DS.Adaptive.textSecondary)
                                }
                                Spacer()
                                if let b = boundPreview {
                                    Text("±\(Int(b))%")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(DS.Adaptive.gold)
                                }
                            }
                        case .global:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Global range")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Spacer()
                                    Text("±\(Int(globalBound))%")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(DS.Adaptive.gold)
                                }
                                Text("One range shared by all timeframes.")
                                    .font(.caption)
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                Slider(value: $globalBound, in: 2...100, step: 1)
                                    .tint(accentColor)
                                .onChange(of: globalBound) { _, _ in
                                    // Defer to avoid "Modifying state during view update"
                                    DispatchQueue.main.async {
                                        Haptics.light.impactOccurred()
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)
                        
                        // Palette selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Palette")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            // All three palettes in one row
                            HStack(spacing: 6) {
                                ForEach([ColorPalette.cool, .classic, .warm], id: \.self) { p in
                                    PaletteChoiceChip(palette: p, selected: palette == p) {
                                        Haptics.light.impactOccurred()
                                        palette = p
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)
                        
                        // Saturation control
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Saturation")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Spacer()
                                Text(String(format: "%.2f×", saturation))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Adaptive.gold)
                            }
                            Slider(value: $saturation, in: 0.6...1.4, step: 0.01)
                                .tint(accentColor)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.chipBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 0.6)
                                )
                                .onChange(of: saturation) { _, _ in
                                    // Defer to avoid "Modifying state during view update"
                                    DispatchQueue.main.async {
                                        Haptics.light.impactOccurred()
                                    }
                                }
                        }
                        
                        // Coins shown stepper
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text("Coins shown")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Spacer()
                                Text("\(topN)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Adaptive.gold)
                                Stepper("", value: $topN, in: 4...24, step: 1)
                                    .labelsHidden()
                                    .tint(accentColor)
                                    .onChange(of: topN) { _, _ in
                                        // Defer to avoid "Modifying state during view update"
                                        DispatchQueue.main.async {
                                            Haptics.light.impactOccurred()
                                        }
                                    }
                            }
                            if topN >= 20 {
                                Text("Higher counts may affect layout. Small coins auto-group into Others.")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                            }
                        }
                        
                        Toggle("Boost small changes", isOn: $boostSmallChanges)
                        Toggle("White labels", isOn: $whiteLabelsOnly)
                        Toggle("Bold borders", isOn: $strongBorders)
                    }
                }

                // MARK: - Data Section
                SettingsSectionCard("Data", icon: "chart.bar.doc.horizontal") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Hide stablecoins", isOn: $filterStables)
                        Toggle("Group into 'Others'", isOn: $includeOthers)
                        Toggle("Weight tiles by volume", isOn: $weightByVolume)
                        Toggle("Normalize to BTC", isOn: $normalizeByBTC)
                        Toggle("Show values", isOn: $showValues)
                    }
                }

                // MARK: - Layout Section
                SettingsSectionCard("Layout", icon: "square.grid.2x2") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Labels density
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Labels")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            HStack(spacing: 8) {
                                ForEach(LabelDensity.allCases) { d in
                                    SmallChoiceChip(title: d.rawValue.capitalized, selected: labelDensity == d) {
                                        Haptics.light.impactOccurred()
                                        labelDensity = d
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)

                        // Sizing curve
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sizing")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            HStack(spacing: 8) {
                                ForEach(WeightingCurve.allCases) { c in
                                    SmallChoiceChip(title: c.rawValue.capitalized, selected: weightingCurve == c) {
                                        Haptics.light.impactOccurred()
                                        weightingCurve = c
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)

                        Toggle("Always include BTC", isOn: $pinBTC)
                    }
                }

                // MARK: - Behavior Section
                SettingsSectionCard("Behavior", icon: "gear") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Live updates", isOn: $followLiveUpdates)
                        
                        if followLiveUpdates {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Refresh interval")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Picker("Refresh every", selection: refreshEvery) {
                                    ForEach(RefreshEvery.allCases) { opt in
                                        Text(opt.label).tag(opt)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                        }
                        
                        Toggle("Auto-hide legend", isOn: $autoHideInfoBar)
                    }
                }
                
                // Bottom padding for scrolling
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(DS.Adaptive.background)
        .toggleStyle(HeatMapToggleStyle())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Haptics.light.impactOccurred()
                    onRestoreDefaults?()
                } label: {
                    Text("Reset")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Adaptive.gold)
                }
            }
        }
    }
}

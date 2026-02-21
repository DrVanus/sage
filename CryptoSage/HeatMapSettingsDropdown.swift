import SwiftUI

// MARK: - Dropdown Toggle Style (Adaptive Gold/Silver)
private struct DropdownToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat = 48
    var height: CGFloat = 26
    
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

// MARK: - Section Header
private struct DropdownSectionHeader: View {
    let title: String
    let icon: String?
    
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.gold)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(DS.Adaptive.textSecondary)
        }
        .padding(.top, 4)
    }
}

struct HeatMapSettingsDropdown: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    @Binding var filterStables: Bool
    @Binding var includeOthers: Bool
    @Binding var weightByVolume: Bool
    @Binding var normalizeByBTC: Bool
    @Binding var showValues: Bool
    @Binding var pinBTC: Bool
    @Binding var autoHideInfoBar: Bool
    @Binding var autoColorScale: Bool
    @Binding var colorblindMode: Bool
    @Binding var whiteLabelsOnly: Bool
    @Binding var lockColorScale: Bool
    @Binding var followLiveUpdates: Bool
    @Binding var autoRefreshEnabled: Bool
    @Binding var strongBorders: Bool

    @Binding var grayNeutral: Bool
    @Binding var saturation: Double

    @Binding var topN: Int
    @Binding var manualBound: Double
    @Binding var minUpdateSeconds: Int

    @Binding var weightingCurve: WeightingCurve
    @Binding var labelDensity: LabelDensity

    var onRefresh: () -> Void
    var onResetScale: () -> Void
    var onRestoreDefaults: () -> Void

    private var isDark: Bool { colorScheme == .dark }
    
    // Adaptive accent color for controls
    private var accentColor: Color {
        isDark ? BrandColors.goldBase : BrandColors.silverBase
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Heat Map Settings")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Spacer()
                Button {
                    Haptics.light.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary.opacity(0.8))
                        .padding(8)
                        .background(
                            ZStack {
                                Circle().fill(DS.Adaptive.chipBackground)
                                Circle().fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.08 : 0.35), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                            }
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.12), DS.Adaptive.stroke.opacity(0.6)]
                                        : [Color.black.opacity(0.06), DS.Adaptive.stroke.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                        )
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Divider().background(DS.Adaptive.divider)

            // Content
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    // Quick Actions
                    Group {
                        DropdownSectionHeader("Quick Actions", icon: "bolt.fill")
                        Button {
                            Haptics.light.impactOccurred()
                            onRefresh()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { isPresented = false }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Refresh Now")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(BrandColors.ctaTextColor(isDark: isDark))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AdaptiveGradients.goldButton(isDark: isDark))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }

                    // Data Options
                    Group {
                        DropdownSectionHeader("Data", icon: "chart.bar.doc.horizontal")
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Filter stablecoins", isOn: $filterStables)
                            Toggle("Include Others", isOn: $includeOthers)
                            Toggle("Weight by Volume", isOn: $weightByVolume)
                            Toggle("Normalize by BTC", isOn: $normalizeByBTC)
                            Toggle("Show Values", isOn: $showValues)
                            Toggle("Always include BTC", isOn: $pinBTC)
                        }
                    }

                    // Display Options
                    Group {
                        DropdownSectionHeader("Display", icon: "paintpalette")
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Auto-hide Info Bar", isOn: $autoHideInfoBar)
                            Toggle("Auto Color Scale", isOn: $autoColorScale)
                            Toggle("Colorblind Palette", isOn: $colorblindMode)
                            Toggle("White Labels", isOn: $whiteLabelsOnly)
                            Toggle("Lock Color Scale", isOn: $lockColorScale)
                            Toggle("Strong Borders", isOn: $strongBorders)
                        }
                    }

                    // Labels
                    Group {
                        DropdownSectionHeader("Labels", icon: "textformat")
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Label Density", selection: $labelDensity) {
                                Text("Compact").tag(LabelDensity.compact)
                                Text("Normal").tag(LabelDensity.normal)
                                Text("Detailed").tag(LabelDensity.detailed)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    // Color Tuning
                    Group {
                        DropdownSectionHeader("Color Tuning", icon: "slider.horizontal.3")
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Gray Midpoint", isOn: $grayNeutral)
                            
                            HStack {
                                Text("Saturation")
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Spacer()
                                Text("\(Int(round(saturation * 100)))%")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Adaptive.gold)
                                Stepper("", value: $saturation, in: 0.6...1.4, step: 0.05)
                                    .labelsHidden()
                                    .tint(accentColor)
                                    .onChange(of: saturation) { _, _ in
                                        // Defer to avoid "Modifying state during view update"
                                        DispatchQueue.main.async {
                                            Haptics.light.impactOccurred()
                                        }
                                    }
                            }
                        }
                    }

                    // Sizing
                    Group {
                        DropdownSectionHeader("Sizing", icon: "square.grid.2x2")
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Sizing Curve", selection: $weightingCurve) {
                                Text("Linear").tag(WeightingCurve.linear)
                                Text("Balanced").tag(WeightingCurve.balanced)
                                Text("Compact").tag(WeightingCurve.compact)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            HStack {
                                Text("Coins shown")
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Spacer()
                                Text("\(topN)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Adaptive.gold)
                                Stepper("", value: $topN, in: 4...24)
                                    .labelsHidden()
                                    .tint(accentColor)
                                    .onChange(of: topN) { _, _ in
                                        // Defer to avoid "Modifying state during view update"
                                        DispatchQueue.main.async {
                                            Haptics.light.impactOccurred()
                                        }
                                    }
                            }
                            
                            HStack {
                                Text("Scale range")
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                Spacer()
                                Text("±\(Int(manualBound))%")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Adaptive.gold)
                                Stepper("", value: $manualBound, in: 2...100)
                                    .labelsHidden()
                                    .tint(accentColor)
                                    .onChange(of: manualBound) { _, _ in
                                        // Defer to avoid "Modifying state during view update"
                                        DispatchQueue.main.async {
                                            Haptics.light.impactOccurred()
                                        }
                                    }
                            }
                        }
                    }

                    // Updates
                    Group {
                        DropdownSectionHeader("Updates", icon: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Follow Live Updates", isOn: $followLiveUpdates)
                            Toggle("Auto Refresh", isOn: $autoRefreshEnabled)
                            
                            if autoRefreshEnabled {
                                HStack {
                                    Text("Min interval")
                                        .font(.subheadline)
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Spacer()
                                    Text("\(minUpdateSeconds)s")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(DS.Adaptive.gold)
                                    Stepper("", value: $minUpdateSeconds, in: 15...300, step: 15)
                                        .labelsHidden()
                                        .tint(accentColor)
                                        .onChange(of: minUpdateSeconds) { _, _ in
                                            // Defer to avoid "Modifying state during view update"
                                            DispatchQueue.main.async {
                                                Haptics.light.impactOccurred()
                                            }
                                        }
                                }
                            }
                        }
                    }

                    // Reset
                    Group {
                        DropdownSectionHeader("Reset", icon: "arrow.counterclockwise")
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                Haptics.light.impactOccurred()
                                onResetScale()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Reset Color Scale")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .tintedRoundedChip(isSelected: false, isDark: isDark, cornerRadius: 10)
                            }
                            .buttonStyle(PressableStyle())

                            Button(role: .destructive) {
                                Haptics.medium.impactOccurred()
                                onRestoreDefaults()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Restore Defaults")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.red.opacity(isDark ? 0.95 : 1.0))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.red.opacity(isDark ? 0.12 : 0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.red.opacity(isDark ? 0.30 : 0.20), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 480)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.strokeStrong, lineWidth: 1)
        )
        .toggleStyle(DropdownToggleStyle())
    }
}

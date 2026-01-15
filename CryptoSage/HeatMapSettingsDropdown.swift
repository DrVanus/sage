import SwiftUI

struct HeatMapSettingsDropdown: View {
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

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Heat Map Settings")
                    .font(.headline)
                Spacer()
                Button {
                    Haptics.light.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 6)

            Divider().background(Color.white.opacity(0.08))

            // Content
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // Quick Actions
                    Group {
                        Text("Quick Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            onRefresh()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { isPresented = false }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Now")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }

                    // Options
                    Group {
                        Text("Options")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Filter stablecoins", isOn: $filterStables)
                            Toggle("Include Others", isOn: $includeOthers)
                            Toggle("Weight by Volume", isOn: $weightByVolume)
                            Toggle("Normalize by BTC", isOn: $normalizeByBTC)
                            Toggle("Show Values", isOn: $showValues)
                            Toggle("Always include BTC", isOn: $pinBTC)
                            Toggle("Auto-hide Info Bar", isOn: $autoHideInfoBar)
                            Toggle("Auto Color Scale", isOn: $autoColorScale)
                            Toggle("Colorblind Palette", isOn: $colorblindMode)
                            Toggle("White Labels (No Black)", isOn: $whiteLabelsOnly)
                            Toggle("Lock Color Scale", isOn: $lockColorScale)
                            Toggle("Follow Live Updates", isOn: $followLiveUpdates)
                            Toggle("Auto Refresh (60s)", isOn: $autoRefreshEnabled)
                        }
                    }

                    // Labels
                    Group {
                        Text("Labels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Label Density", selection: $labelDensity) {
                                Text("Compact").tag(LabelDensity.compact)
                                Text("Normal").tag(LabelDensity.normal)
                                Text("Detailed").tag(LabelDensity.detailed)
                            }
                            .pickerStyle(.segmented)
                            Toggle("Strong Borders", isOn: $strongBorders)
                        }
                    }

                    // Color Tuning
                    Group {
                        Text("Color Tuning")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Gray Midpoint", isOn: $grayNeutral)
                            Stepper("Saturation \(Int(round(saturation * 100)))%", value: $saturation, in: 0.6...1.4, step: 0.05)
                        }
                    }

                    // Sizing
                    Group {
                        Text("Sizing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Sizing Curve", selection: $weightingCurve) {
                                Text("Linear").tag(WeightingCurve.linear)
                                Text("Balanced").tag(WeightingCurve.balanced)
                                Text("Compact").tag(WeightingCurve.compact)
                            }
                            .pickerStyle(.segmented)
                            Stepper("Top \(topN)", value: $topN, in: 4...30)
                            Stepper("Scale ±\(Int(manualBound))%", value: $manualBound, in: 2...100)
                        }
                    }

                    // Updates
                    Group {
                        Text("Updates")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper("Min Update \(minUpdateSeconds)s", value: $minUpdateSeconds, in: 15...300, step: 15)
                        }
                    }

                    // Reset
                    Group {
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                onResetScale()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset Color Scale")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())

                            Button(role: .destructive) {
                                onRestoreDefaults()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Restore Defaults")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.red.opacity(0.95))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 420)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

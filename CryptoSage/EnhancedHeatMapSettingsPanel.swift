import SwiftUI

struct EnhancedHeatMapSettingsPanel: View {
    @Binding var isPresented: Bool

    @Binding var filterStables: Bool
    @Binding var includeOthers: Bool
    @Binding var weightByVolume: Bool
    @Binding var normalizeByBTC: Bool
    @Binding var showValues: Bool
    @Binding var pinBTC: Bool
    @Binding var autoHideInfoBar: Bool
    @Binding var autoColorScale: Bool
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
    @Binding var palette: ColorPalette

    // Optional preview values for sheet presentation
    var boundPreview: Double? = nil
    var legendNoteText: String? = nil

    // Actions
    var onRefresh: (() -> Void)? = nil
    var onResetScale: (() -> Void)? = nil
    var onRestoreDefaults: (() -> Void)? = nil

    private var previewBound: Double { boundPreview ?? manualBound }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quick actions
            HStack(spacing: 8) {
                Button {
                    onRefresh?()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button {
                    onResetScale?()
                } label: {
                    Label("Reset Scale", systemImage: "dial.low")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button(role: .destructive) {
                    onRestoreDefaults?()
                } label: {
                    Label("Restore", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)
            }

            // Legend preview
            VStack(alignment: .leading, spacing: 6) {
                LegendView(bound: previewBound, note: legendNoteText, palette: palette)
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))

            // Scale controls
            Group {
                Toggle("Auto color scale", isOn: $autoColorScale)
                    .onChange(of: autoColorScale) { newVal in
                        if newVal { lockColorScale = false }
                    }
                Toggle("Lock color scale", isOn: $lockColorScale)
                    .onChange(of: lockColorScale) { newVal in
                        if newVal { autoColorScale = false }
                    }
                HStack {
                    Text("Manual bound")
                    Spacer()
                    Text("±\(Int(manualBound))%")
                        .monospacedDigit()
                }
                Slider(value: $manualBound, in: 2...100, step: 1)
                    .disabled(!lockColorScale)
            }

            // Appearance
            Group {
                Picker("Palette", selection: $palette) {
                    ForEach(ColorPalette.allCases) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Gray midpoint (Warm only)", isOn: $grayNeutral)

                HStack {
                    Text("Saturation")
                    Spacer()
                    Text(String(format: "%.2f×", saturation)).monospacedDigit()
                }
                Slider(value: $saturation, in: 0.6...1.4, step: 0.01)

                Toggle("White labels only", isOn: $whiteLabelsOnly)
                Toggle("Strong borders", isOn: $strongBorders)
            }

            // Data & layout
            Group {
                Toggle("Filter stables", isOn: $filterStables)
                Toggle("Include 'Others'", isOn: $includeOthers)
                Toggle("Weight by volume", isOn: $weightByVolume)
                Toggle("Normalize vs BTC", isOn: $normalizeByBTC)
                Toggle("Show values", isOn: $showValues)
                Toggle("Pin BTC in Top N", isOn: $pinBTC)

                Picker("Label density", selection: $labelDensity) {
                    ForEach(LabelDensity.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Weighting curve", selection: $weightingCurve) {
                    ForEach(WeightingCurve.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Top N: \(topN)", value: $topN, in: 4...30, step: 1)

                Toggle("Follow live updates", isOn: $followLiveUpdates)
                Toggle("Auto refresh", isOn: $autoRefreshEnabled)
                Stepper("Min update interval: \(minUpdateSeconds)s", value: $minUpdateSeconds, in: 15...600, step: 15)

                Toggle("Auto-hide info bar", isOn: $autoHideInfoBar)
            }
        }
        .padding(10)
    }
}

//  ChartIndicatorMenu.swift
//  Custom indicator picker using app styling

import SwiftUI

struct ChartIndicatorMenu: View {
    @Binding var isPresented: Bool

    // Persisted settings used by CryptoChartView
    @AppStorage("Chart.ShowVolume") private var showVolume: Bool = true
    @AppStorage("Chart.Indicators.SMA.Enabled") private var smaEnabled: Bool = false
    @AppStorage("Chart.Indicators.SMA.Period") private var smaPeriod: Int = 20
    @AppStorage("Chart.Indicators.EMA.Enabled") private var emaEnabled: Bool = false
    @AppStorage("Chart.Indicators.EMA.Period") private var emaPeriod: Int = 50
    @AppStorage("Chart.Indicators.ShowLegend") private var showLegend: Bool = true

    private let smaPresets: [Int] = [7, 20, 50, 200]
    private let emaPresets: [Int] = [9, 12, 26, 50]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Indicators")
                    .font(DS.Fonts.axis)
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") { isPresented = false }
                    .font(.callout.weight(.semibold))
            }

            // Volume
            Toggle(isOn: $showVolume) {
                Label("Volume", systemImage: "chart.bar.fill")
                    .labelStyle(.titleOnly)
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)

            Divider().overlay(DS.Colors.badgeStroke.opacity(0.4))

            // SMA
            Toggle(isOn: $smaEnabled) {
                HStack {
                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                    Text("SMA")
                        .foregroundStyle(.white)
                }
            }
            .toggleStyle(.switch)
            if smaEnabled {
                HStack(spacing: 8) {
                    ForEach(smaPresets, id: \.self) { p in
                        Button(action: { smaPeriod = p }) {
                            Text("\(p)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(smaPeriod == p ? DS.Colors.gold.opacity(0.9) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.5)
                                )
                                .foregroundStyle(smaPeriod == p ? Color.black : Color.white.opacity(0.9))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            // EMA
            Toggle(isOn: $emaEnabled) {
                HStack {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("EMA")
                        .foregroundStyle(.white)
                }
            }
            .toggleStyle(.switch)
            if emaEnabled {
                HStack(spacing: 8) {
                    ForEach(emaPresets, id: \.self) { p in
                        Button(action: { emaPeriod = p }) {
                            Text("\(p)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(emaPeriod == p ? DS.Colors.gold.opacity(0.9) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.5)
                                )
                                .foregroundStyle(emaPeriod == p ? Color.black : Color.white.opacity(0.9))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Toggle("Show legend chips", isOn: $showLegend)
                .toggleStyle(.switch)
                .foregroundStyle(.white)

            HStack {
                Button(role: .destructive) {
                    // Reset to defaults
                    showVolume = true
                    smaEnabled = false
                    smaPeriod = 20
                    emaEnabled = false
                    emaPeriod = 50
                    showLegend = true
                } label: {
                    Text("Reset")
                }
                Spacer()
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.gold)
                    .foregroundStyle(Color.black)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
    }
}


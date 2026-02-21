//  ChartIndicatorMenu.swift
//  Custom indicator picker using app styling

import SwiftUI

// MARK: - PreferenceKey for capturing preset button frame
private struct PresetButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    private static var lastUpdateAt: CFTimeInterval = 0
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        
        // Throttle to ~15Hz to prevent multiple updates per frame
        let now = CACurrentMediaTime()
        guard now - lastUpdateAt >= (1.0 / 15.0) else { return }
        
        // Ignore jitter (changes < 2px)
        let dx = abs(next.origin.x - value.origin.x)
        let dy = abs(next.origin.y - value.origin.y)
        if dx < 2 && dy < 2 && abs(next.width - value.width) < 2 { return }
        
        value = next
        lastUpdateAt = now
    }
}

private struct GoldHairlineDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isDark 
                        ? [Color.white.opacity(0.18), Color.white.opacity(0.06)]
                        : [Color.black.opacity(0.12), Color.black.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 1)
    }
}

/// Badge indicating an indicator only works on TradingView chart
private struct TVOnlyBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Text("TV")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(isDark ? Color.white.opacity(0.5) : Color.white.opacity(0.9)))
            .overlay(Capsule().stroke(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.15), lineWidth: 0.5))
    }
}

private struct ParamChip: View {
    let text: String
    let trigger: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isDark ? .white.opacity(0.85) : .black.opacity(0.75))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Capsule().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
            .overlay(Capsule().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.5))
            .scaleEffect(pulse ? 1.0 : 0.96)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: pulse)
            .onChange(of: trigger) { _, _ in
                pulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pulse = false }
            }
    }
}

private struct GoldToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat = 52
    var height: CGFloat = 28
    
    private var isDark: Bool { colorScheme == .dark }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                Haptics.light.impactOccurred()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(configuration.isOn ? DS.Colors.gold : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                        .frame(width: width, height: height)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 0.8)
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

struct ChartIndicatorMenu: View {
    @Binding var isPresented: Bool
    
    /// True when using CryptoSage AI native chart (TV-only indicators won't work)
    var isUsingNativeChart: Bool = true
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // Adaptive text colors for light/dark mode
    private var sectionHeaderColor: Color { isDark ? .white.opacity(0.6) : .black.opacity(0.55) }
    private var labelPrimaryColor: Color { isDark ? .white : .black }
    private var labelSecondaryColor: Color { isDark ? .white.opacity(0.7) : .black.opacity(0.6) }
    private var labelTertiaryColor: Color { isDark ? .white.opacity(0.75) : .black.opacity(0.65) }
    private var valueColor: Color { isDark ? .white.opacity(0.9) : .black.opacity(0.8) }

    // Persisted settings used by CryptoChartView
    @AppStorage("Chart.ShowVolume") private var showVolume: Bool = true
    @AppStorage("Chart.VolumeIntegrated") private var volumeIntegrated: Bool = true  // true = overlay, false = separate pane
    @AppStorage("Chart.Indicators.SMA.Enabled") private var smaEnabled: Bool = false
    @AppStorage("Chart.Indicators.SMA.Period") private var smaPeriod: Int = 20
    @AppStorage("Chart.Indicators.EMA.Enabled") private var emaEnabled: Bool = false
    @AppStorage("Chart.Indicators.EMA.Period") private var emaPeriod: Int = 50
    @AppStorage("Chart.Indicators.ShowLegend") private var showLegend: Bool = true
    @AppStorage("TV.Indicators.Selected") private var tvIndicatorsRaw: String = ""

    // Additional indicators (enable flags)
    @AppStorage("Chart.Indicators.BB.Enabled") private var bbEnabled: Bool = false
    @AppStorage("Chart.Indicators.RSI.Enabled") private var rsiEnabled: Bool = false
    @AppStorage("Chart.Indicators.MACD.Enabled") private var macdEnabled: Bool = false
    @AppStorage("Chart.Indicators.Stoch.Enabled") private var stochEnabled: Bool = false
    @AppStorage("Chart.Indicators.VWAP.Enabled") private var vwapEnabled: Bool = false
    @AppStorage("Chart.Indicators.Ichimoku.Enabled") private var ichimokuEnabled: Bool = false
    @AppStorage("Chart.Indicators.ATR.Enabled") private var atrEnabled: Bool = false
    @AppStorage("Chart.Indicators.OBV.Enabled") private var obvEnabled: Bool = false
    @AppStorage("Chart.Indicators.MFI.Enabled") private var mfiEnabled: Bool = false

    // Common parameters (persist now; UI can expand later)
    @AppStorage("Chart.Indicators.RSI.Period") private var rsiPeriod: Int = 14
    @AppStorage("Chart.Indicators.MACD.Fast") private var macdFast: Int = 12
    @AppStorage("Chart.Indicators.MACD.Slow") private var macdSlow: Int = 26
    @AppStorage("Chart.Indicators.MACD.Signal") private var macdSignal: Int = 9
    @AppStorage("Chart.Indicators.Stoch.K") private var stochK: Int = 14
    @AppStorage("Chart.Indicators.Stoch.D") private var stochD: Int = 3
    @AppStorage("Chart.Indicators.Stoch.Smooth") private var stochSmooth: Int = 3
    @AppStorage("Chart.Indicators.BB.Period") private var bbPeriod: Int = 20
    @AppStorage("Chart.Indicators.BB.Dev") private var bbDev: Double = 2.0
    @AppStorage("Chart.Indicators.ATR.Period") private var atrPeriod: Int = 14
    @AppStorage("Chart.Indicators.MFI.Period") private var mfiPeriod: Int = 14
    @AppStorage("Chart.Indicators.VWAP.Session") private var vwapSession: Bool = true

    @State private var showAppliedToast: Bool = false
    @State private var baselineSignature: String = ""
    @State private var showPresetMenu: Bool = false
    @State private var presetButtonFrame: CGRect = .zero

    private let smaPresets: [Int] = [7, 20, 50, 200]
    private let emaPresets: [Int] = [9, 12, 26, 50]
    private let rsiPresets: [Int] = [7, 14, 21]

    private func keyForIndicator(_ ind: IndicatorType) -> String {
        switch ind {
        case .volume: return "volume"
        case .sma: return "sma"
        case .ema: return "ema"
        case .bb: return "bb"
        case .rsi: return "rsi"
        case .macd: return "macd"
        case .stoch: return "stoch"
        case .vwap: return "vwap"
        case .ichimoku: return "ichimoku"
        case .atr: return "atr"
        case .obv: return "obv"
        case .mfi: return "mfi"
        }
    }

    private func parseIndicatorSet(from raw: String) -> Set<IndicatorType> {
        let keys = raw.split(separator: ",").map { String($0) }
        var out = Set<IndicatorType>()
        for k in keys {
            switch k {
            case "volume": out.insert(.volume)
            case "sma": out.insert(.sma)
            case "ema": out.insert(.ema)
            case "bb": out.insert(.bb)
            case "rsi": out.insert(.rsi)
            case "macd": out.insert(.macd)
            case "stoch": out.insert(.stoch)
            case "vwap": out.insert(.vwap)
            case "ichimoku": out.insert(.ichimoku)
            case "atr": out.insert(.atr)
            case "obv": out.insert(.obv)
            case "mfi": out.insert(.mfi)
            default: break
            }
        }
        return out
    }

    private func serializeIndicatorSet(_ set: Set<IndicatorType>) -> String {
        let order: [IndicatorType] = [.volume, .sma, .ema, .bb, .rsi, .macd, .stoch, .vwap, .ichimoku, .atr, .obv, .mfi]
        let keys: [String] = order.compactMap { set.contains($0) ? keyForIndicator($0) : nil }
        return keys.joined(separator: ",")
    }

    private func bumpTVVersion() {
        // Re-serialize current set (drop any prior version tokens) and append a version nonce
        let base = serializeIndicatorSet(parseIndicatorSet(from: tvIndicatorsRaw))
        let ver = Int(Date().timeIntervalSince1970)
        tvIndicatorsRaw = base.isEmpty ? "v\(ver)" : base + ",v\(ver)"
    }

    private func set(_ indicator: IndicatorType, enabled: Bool) {
        var set = parseIndicatorSet(from: tvIndicatorsRaw)
        if enabled { set.insert(indicator) } else { set.remove(indicator) }
        tvIndicatorsRaw = serializeIndicatorSet(set)
    }

    private func recomputeTVIndicatorsRawFromToggles() {
        var set: Set<IndicatorType> = []
        if showVolume { set.insert(.volume) }
        if smaEnabled { set.insert(.sma) }
        if emaEnabled { set.insert(.ema) }
        if bbEnabled { set.insert(.bb) }
        if rsiEnabled { set.insert(.rsi) }
        if macdEnabled { set.insert(.macd) }
        if stochEnabled { set.insert(.stoch) }
        if vwapEnabled { set.insert(.vwap) }
        if ichimokuEnabled { set.insert(.ichimoku) }
        if atrEnabled { set.insert(.atr) }
        if obvEnabled { set.insert(.obv) }
        if mfiEnabled { set.insert(.mfi) }
        tvIndicatorsRaw = serializeIndicatorSet(set)
    }

    // Active indicator count (from serialized set for consistency)
    private var activeCount: Int {
        parseIndicatorSet(from: tvIndicatorsRaw).count
    }

    private func currentSignature() -> String {
        // A stable signature of currently mapped studies; if this changes, we show an "Applied" toast.
        TVStudiesMapper.buildCurrentStudies().joined(separator: "|")
    }

    private enum IndicatorPreset: String { case dayTrader, swing, investor }

    private func clearAllIndicators() {
        showVolume = false
        smaEnabled = false
        emaEnabled = false
        bbEnabled = false
        rsiEnabled = false
        macdEnabled = false
        stochEnabled = false
        vwapEnabled = false
        ichimokuEnabled = false
        atrEnabled = false
        obvEnabled = false
        mfiEnabled = false
        recomputeTVIndicatorsRawFromToggles()
        bumpTVVersion()
    }

    private func applyPreset(_ p: IndicatorPreset) {
        // Baseline
        showVolume = true
        showLegend = true
        // Defaults to keep sensible params
        smaPeriod = 20
        emaPeriod = 50
        rsiPeriod = 14
        macdFast = 12; macdSlow = 26; macdSignal = 9
        stochK = 14; stochD = 3; stochSmooth = 3
        bbPeriod = 20; bbDev = 2.0
        atrPeriod = 14
        mfiPeriod = 14
        vwapSession = true

        switch p {
        case .dayTrader:
            smaEnabled = false
            emaEnabled = true;  emaPeriod = 12
            bbEnabled = true
            rsiEnabled = true;  rsiPeriod = 7
            macdEnabled = true
            stochEnabled = true
            vwapEnabled = true
            ichimokuEnabled = false
            atrEnabled = true
            obvEnabled = false
            mfiEnabled = false
        case .swing:
            smaEnabled = true;  smaPeriod = 20
            emaEnabled = true;  emaPeriod = 50
            bbEnabled = true
            rsiEnabled = true;  rsiPeriod = 14
            macdEnabled = true
            stochEnabled = false
            vwapEnabled = false
            ichimokuEnabled = false
            atrEnabled = true
            obvEnabled = true
            mfiEnabled = false
        case .investor:
            smaEnabled = true;  smaPeriod = 200
            emaEnabled = true;  emaPeriod = 50
            bbEnabled = false
            rsiEnabled = true;  rsiPeriod = 14
            macdEnabled = true
            stochEnabled = false
            vwapEnabled = false
            ichimokuEnabled = false  // Ichimoku removed - too complex
            atrEnabled = false
            obvEnabled = true
            mfiEnabled = true
        }
        recomputeTVIndicatorsRawFromToggles()
        bumpTVVersion()
    }

    // MARK: - Helper UI builders to reduce type-checking complexity
    @ViewBuilder
    private func presetButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.light.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? DS.Colors.gold.opacity(0.9) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.5)
                )
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private func smaPresetRow() -> some View {
        HStack(spacing: 8) {
            ForEach(smaPresets, id: \.self) { (p: Int) in
                presetButton(label: String(p), selected: smaPeriod == p) { smaPeriod = p }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func emaPresetRow() -> some View {
        HStack(spacing: 8) {
            ForEach(emaPresets, id: \.self) { (p: Int) in
                presetButton(label: String(p), selected: emaPeriod == p) { emaPeriod = p }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func rsiPresetRow() -> some View {
        HStack(spacing: 8) {
            ForEach(rsiPresets, id: \.self) { (p: Int) in
                presetButton(label: String(p), selected: rsiPeriod == p) { rsiPeriod = p }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Body Section Helpers (split to help compiler type-check)
    
    @ViewBuilder
    private func headerSection() -> some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.callout.weight(.semibold))
                .foregroundStyle(labelTertiaryColor)
            Text("Chart indicators")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(valueColor)
            Text(isUsingNativeChart ? "Native" : "TV")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(sectionHeaderColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
            Spacer()
            Text("\(activeCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Capsule().fill(DS.Colors.gold))
                .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.6))
            Button {
                Haptics.light.impactOccurred()
                showPresetMenu = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(isDark ? .white.opacity(0.85) : .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PresetButtonFrameKey.self, value: proxy.frame(in: .global))
                }
            )
            .onPreferenceChange(PresetButtonFrameKey.self) { frame in
                DispatchQueue.main.async {
                    presetButtonFrame = frame
                }
            }
            Button("Done") {
                isPresented = false
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(DS.Colors.gold)
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }
    
    @ViewBuilder
    private func tradingViewNoticeSection() -> some View {
        if !isUsingNativeChart {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.gold)
                Text("TradingView mode: Volume toggle causes brief reload. Other indicators are experimental.")
                    .font(.caption2)
                    .foregroundStyle(isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Colors.gold.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DS.Colors.gold.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
    }
    
    @ViewBuilder
    private func volumeSection() -> some View {
        Text("Volume")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sectionHeaderColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        
        Toggle(isOn: $showVolume) {
            Label("Volume", systemImage: "chart.bar.fill")
                .labelStyle(.titleOnly)
                .foregroundStyle(labelPrimaryColor)
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: showVolume) { _, v in
            set(.volume, enabled: v)
            Haptics.light.impactOccurred()
        }
        
        if showVolume {
            HStack {
                Text("Display")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(labelSecondaryColor)
                Spacer()
                Picker("", selection: $volumeIntegrated) {
                    Text("Overlay").tag(true)
                    Text("Pane").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .scaleEffect(0.85)
            }
            .padding(.leading, 12)
            .padding(.vertical, 2)
        }
        
        GoldHairlineDivider()
        
        Toggle(isOn: $obvEnabled) {
            HStack {
                Circle().fill(Color.cyan).frame(width: 6, height: 6)
                Text("OBV")
                    .foregroundStyle(labelPrimaryColor)
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: obvEnabled) { _, v in
            set(.obv, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
    }
    
    @ViewBuilder
    private func trendSection() -> some View {
        Text("Trend")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sectionHeaderColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        
        // SMA
        Toggle(isOn: $smaEnabled) {
            HStack {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("SMA")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if smaEnabled {
                    ParamChip(text: "\(smaPeriod)", trigger: "\(smaPeriod)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: smaEnabled) { _, v in
            set(.sma, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if smaEnabled {
            smaPresetRow()
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.18), value: smaEnabled)
                .onChange(of: smaPeriod) { _, _ in bumpTVVersion() }
        }
        
        // EMA
        Toggle(isOn: $emaEnabled) {
            HStack {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("EMA")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if emaEnabled {
                    ParamChip(text: "\(emaPeriod)", trigger: "\(emaPeriod)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: emaEnabled) { _, v in
            set(.ema, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if emaEnabled {
            emaPresetRow()
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.18), value: emaEnabled)
                .onChange(of: emaPeriod) { _, _ in bumpTVVersion() }
        }
        
        GoldHairlineDivider()
    }
    
    @ViewBuilder
    private func bollingerBandsToggle() -> some View {
        Toggle(isOn: $bbEnabled) {
            HStack {
                Circle().fill(Color.purple).frame(width: 6, height: 6)
                Text("Bollinger Bands")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if bbEnabled {
                    ParamChip(text: "\(bbPeriod) / \(String(format: "%.1f", bbDev))", trigger: "\(bbPeriod)-\(String(format: "%.1f", bbDev))")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: bbEnabled) { _, v in
            set(.bb, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if bbEnabled {
            VStack(spacing: 6) {
                HStack {
                    Text("Period")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(bbPeriod)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $bbPeriod, in: 5...100)
                        .labelsHidden()
                }
                GoldHairlineDivider().opacity(0.8)
                HStack {
                    Text("Std Dev")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text(String(format: "%.1f", bbDev))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                    Stepper("", value: $bbDev, in: 1.0...4.0, step: 0.5)
                        .labelsHidden()
                }
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: bbEnabled)
            .onChange(of: bbPeriod) { _, _ in bumpTVVersion() }
            .onChange(of: bbDev) { _, _ in bumpTVVersion() }
        }
    }
    
    @ViewBuilder
    private func rsiToggle() -> some View {
        Toggle(isOn: $rsiEnabled) {
            HStack {
                Circle().fill(Color.mint).frame(width: 6, height: 6)
                Text("RSI")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if rsiEnabled {
                    ParamChip(text: "\(rsiPeriod)", trigger: "\(rsiPeriod)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: rsiEnabled) { _, v in
            set(.rsi, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if rsiEnabled {
            rsiPresetRow()
            VStack(spacing: 6) {
                HStack {
                    Text("Period")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(rsiPeriod)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $rsiPeriod, in: 2...50)
                        .labelsHidden()
                }
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: rsiEnabled)
            .onChange(of: rsiPeriod) { _, _ in bumpTVVersion() }
        }
    }
    
    @ViewBuilder
    private func macdToggle() -> some View {
        Toggle(isOn: $macdEnabled) {
            HStack {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("MACD")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if macdEnabled {
                    ParamChip(text: "\(macdFast)/\(macdSlow)/\(macdSignal)", trigger: "\(macdFast)-\(macdSlow)-\(macdSignal)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: macdEnabled) { _, v in
            set(.macd, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if macdEnabled {
            VStack(spacing: 6) {
                HStack {
                    Text("Fast")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(macdFast)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $macdFast, in: 2...30)
                        .labelsHidden()
                }
                GoldHairlineDivider().opacity(0.8)
                HStack {
                    Text("Slow")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(macdSlow)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $macdSlow, in: 10...100)
                        .labelsHidden()
                }
                GoldHairlineDivider().opacity(0.8)
                HStack {
                    Text("Signal")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(macdSignal)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $macdSignal, in: 1...20)
                        .labelsHidden()
                }
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: macdEnabled)
            .onChange(of: macdFast) { _, _ in bumpTVVersion() }
            .onChange(of: macdSlow) { _, _ in bumpTVVersion() }
            .onChange(of: macdSignal) { _, _ in bumpTVVersion() }
        }
    }
    
    @ViewBuilder
    private func stochasticToggle() -> some View {
        Toggle(isOn: $stochEnabled) {
            HStack {
                Circle().fill(Color.teal).frame(width: 6, height: 6)
                Text("Stochastic")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if stochEnabled {
                    ParamChip(text: "\(stochK)/\(stochD)/\(stochSmooth)", trigger: "\(stochK)-\(stochD)-\(stochSmooth)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: stochEnabled) { _, v in
            set(.stoch, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if stochEnabled {
            VStack(spacing: 6) {
                HStack {
                    Text("%K")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(stochK)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $stochK, in: 5...50)
                        .labelsHidden()
                }
                GoldHairlineDivider().opacity(0.8)
                HStack {
                    Text("%D")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(stochD)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $stochD, in: 1...20)
                        .labelsHidden()
                }
                GoldHairlineDivider().opacity(0.8)
                HStack {
                    Text("Smooth")
                        .font(.caption)
                        .foregroundStyle(labelTertiaryColor)
                    Spacer()
                    Text("\(stochSmooth)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valueColor)
                        .monospacedDigit()
                    Stepper("", value: $stochSmooth, in: 1...20)
                        .labelsHidden()
                }
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: stochEnabled)
            .onChange(of: stochK) { _, _ in bumpTVVersion() }
            .onChange(of: stochD) { _, _ in bumpTVVersion() }
            .onChange(of: stochSmooth) { _, _ in bumpTVVersion() }
        }
    }
    
    @ViewBuilder
    private func momentumSection() -> some View {
        Text("Momentum")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sectionHeaderColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        
        bollingerBandsToggle()
        rsiToggle()
        macdToggle()
        stochasticToggle()
    }
    
    @ViewBuilder
    private func advancedSection() -> some View {
        GoldHairlineDivider()
            .padding(.top, 8)
        
        VStack(alignment: .leading, spacing: 2) {
            Text("Advanced")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(sectionHeaderColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        
        // VWAP
        Toggle(isOn: $vwapEnabled) {
            HStack {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("VWAP")
                    .foregroundStyle(labelPrimaryColor)
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: vwapEnabled) { _, v in
            set(.vwap, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        
        // ATR
        Toggle(isOn: $atrEnabled) {
            HStack {
                Circle().fill(Color.yellow).frame(width: 6, height: 6)
                Text("ATR")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if atrEnabled {
                    ParamChip(text: "\(atrPeriod)", trigger: "\(atrPeriod)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: atrEnabled) { _, v in
            set(.atr, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if atrEnabled {
            HStack {
                Text("Period")
                    .font(.caption)
                    .foregroundStyle(labelTertiaryColor)
                Spacer()
                Text("\(atrPeriod)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                Stepper("", value: $atrPeriod, in: 2...50)
                    .labelsHidden()
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: atrEnabled)
            .onChange(of: atrPeriod) { _, _ in bumpTVVersion() }
        }
        
        // MFI
        Toggle(isOn: $mfiEnabled) {
            HStack {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("MFI")
                    .foregroundStyle(labelPrimaryColor)
                Spacer()
                if mfiEnabled {
                    ParamChip(text: "\(mfiPeriod)", trigger: "\(mfiPeriod)")
                }
            }
        }
        .toggleStyle(GoldToggleStyle())
        .onChange(of: mfiEnabled) { _, v in
            set(.mfi, enabled: v)
            bumpTVVersion()
            Haptics.light.impactOccurred()
        }
        if mfiEnabled {
            HStack {
                Text("Period")
                    .font(.caption)
                    .foregroundStyle(labelTertiaryColor)
                Spacer()
                Text("\(mfiPeriod)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                Stepper("", value: $mfiPeriod, in: 2...50)
                    .labelsHidden()
            }
            .padding(.leading, 18)
            .tint(DS.Colors.gold)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.18), value: mfiEnabled)
            .onChange(of: mfiPeriod) { _, _ in bumpTVVersion() }
        }
    }
    
    @ViewBuilder
    private func legendSection() -> some View {
        if isUsingNativeChart {
            GoldHairlineDivider()
                .padding(.top, 8)
            
            Toggle("Show legend chips", isOn: $showLegend)
                .toggleStyle(GoldToggleStyle())
                .foregroundStyle(labelPrimaryColor)
                .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private func footerSection() -> some View {
        GoldHairlineDivider()
            .padding(.top, 12)
        
        HStack(spacing: 12) {
            Button(role: .destructive) {
                Haptics.light.impactOccurred()
                resetAllIndicators()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Reset")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(Color.red.opacity(0.9))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.08))
                        .overlay(Capsule().stroke(Color.red.opacity(0.35), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            
            Spacer(minLength: 0)
            
            Text("\(activeCount) indicator\(activeCount == 1 ? "" : "s") active")
                .font(.caption)
                .foregroundStyle(isDark ? .white.opacity(0.5) : .black.opacity(0.45))
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    
    private func resetAllIndicators() {
        showVolume = true
        smaEnabled = false
        smaPeriod = 20
        emaEnabled = false
        emaPeriod = 50
        
        bbEnabled = false
        rsiEnabled = false
        macdEnabled = false
        stochEnabled = false
        vwapEnabled = false
        ichimokuEnabled = false
        atrEnabled = false
        obvEnabled = false
        mfiEnabled = false
        
        rsiPeriod = 14
        macdFast = 12
        macdSlow = 26
        macdSignal = 9
        stochK = 14
        stochD = 3
        stochSmooth = 3
        bbPeriod = 20
        bbDev = 2.0
        atrPeriod = 14
        mfiPeriod = 14
        vwapSession = true
        
        showLegend = true
        
        recomputeTVIndicatorsRawFromToggles()
        bumpTVVersion()
    }

    var body: some View {
        mainContent
    }
    
    // MARK: - Body Sub-Components (split to help compiler type-check)
    
    private var mainContent: some View {
        VStack(spacing: 10) {
            headerSection()
            tradingViewNoticeSection()
            scrollableContent
            footerSection()
        }
        .modifier(MenuContainerModifier(
            isDark: isDark,
            showAppliedToast: showAppliedToast,
            showPresetMenu: $showPresetMenu,
            presetButtonFrame: presetButtonFrame,
            onClearAll: { clearAllIndicators() },
            onDayTrader: { applyPreset(.dayTrader) },
            onSwing: { applyPreset(.swing) },
            onInvestor: { applyPreset(.investor) },
            onAppear: {
                // ALWAYS sync tvIndicatorsRaw from toggle states on appear
                // This ensures badge count matches actual toggle states (fixes sync issues)
                recomputeTVIndicatorsRawFromToggles()
                baselineSignature = currentSignature()
            }
        ))
    }
    
    private var scrollableContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 10) {
                Group {
                    volumeSection()
                }
                Group {
                    trendSection()
                }
                Group {
                    momentumSection()
                }
                Group {
                    advancedSection()
                }
                Group {
                    legendSection()
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 16)
        }
        .tint(DS.Colors.gold)
    }
}

// MARK: - Menu Container Modifier (extracted to reduce body complexity)
private struct MenuContainerModifier: ViewModifier {
    let isDark: Bool
    let showAppliedToast: Bool
    @Binding var showPresetMenu: Bool
    let presetButtonFrame: CGRect
    let onClearAll: () -> Void
    let onDayTrader: () -> Void
    let onSwing: () -> Void
    let onInvestor: () -> Void
    let onAppear: () -> Void
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                appliedToastOverlay
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .background(backgroundLayer)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(gradientOverlay)
            .overlay(borderOverlay)
            .tint(DS.Colors.gold)
            .overlay {
                presetMenuOverlay
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showPresetMenu)
            .onAppear(perform: onAppear)
    }
    
    @ViewBuilder
    private var appliedToastOverlay: some View {
        if showAppliedToast {
            Text("Applied")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Colors.gold)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.25), lineWidth: 0.6))
                )
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
    
    private var backgroundLayer: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isDark ? Color.clear : Color.white.opacity(0.88))
    }
    
    private var gradientOverlay: some View {
        LinearGradient(colors: [isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
    }
    
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isDark ? DS.Colors.badgeStroke.opacity(0.6) : Color.black.opacity(0.08), lineWidth: isDark ? 0.75 : 0.5)
            .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var presetMenuOverlay: some View {
        if showPresetMenu {
            IndicatorPresetMenu(
                isPresented: $showPresetMenu,
                anchorRect: presetButtonFrame,
                onClearAll: onClearAll,
                onDayTrader: onDayTrader,
                onSwing: onSwing,
                onInvestor: onInvestor
            )
        }
    }
}

// MARK: - Indicator Preset Menu (Custom anchored popup)
private struct IndicatorPresetMenu: View {
    @Binding var isPresented: Bool
    let anchorRect: CGRect
    let onClearAll: () -> Void
    let onDayTrader: () -> Void
    let onSwing: () -> Void
    let onInvestor: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Backdrop
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }
                
                // Menu panel
                presetPanel
                    .position(menuPosition(in: geo))
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }
    
    private var presetPanel: some View {
        VStack(spacing: 0) {
            // Clear all (destructive)
            menuRow(
                title: "Clear all",
                icon: "trash",
                isDestructive: true,
                action: onClearAll
            )
            
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.8)
                .padding(.horizontal, 8)
            
            // Presets
            menuRow(
                title: "Preset · Day trader",
                icon: "bolt.fill",
                isDestructive: false,
                action: onDayTrader
            )
            
            menuRow(
                title: "Preset · Swing",
                icon: "chart.line.uptrend.xyaxis",
                isDestructive: false,
                action: onSwing
            )
            
            menuRow(
                title: "Preset · Investor",
                icon: "clock.arrow.circlepath",
                isDestructive: false,
                action: onInvestor
            )
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
        )
    }
    
    private func menuRow(title: String, icon: String, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light.impactOccurred()
            action()
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDestructive ? .red : DS.Colors.gold)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDestructive ? .red : .white)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func menuPosition(in geo: GeometryProxy) -> CGPoint {
        let containerGlobal = geo.frame(in: .global)
        let menuWidth: CGFloat = 200
        let menuHeight: CGFloat = 180 // Approximate height
        
        // Position below and to the left of the anchor button
        var x = anchorRect.midX - menuWidth / 2
        var y = anchorRect.maxY + 8 + menuHeight / 2
        
        // Clamp to container bounds
        let padding: CGFloat = 12
        x = max(containerGlobal.minX + padding + menuWidth / 2, min(containerGlobal.maxX - padding - menuWidth / 2, x))
        
        // If not enough space below, position above
        if y + menuHeight / 2 > containerGlobal.maxY - padding {
            y = anchorRect.minY - 8 - menuHeight / 2
        }
        
        // Convert to local coordinates
        let localX = x - containerGlobal.minX
        let localY = y - containerGlobal.minY
        
        return CGPoint(x: localX, y: localY)
    }
}


import SwiftUI

public struct GridHeatMapView: View {
    public let tiles: [HeatMapTile]
    public let timeframe: HeatMapTimeframe
    public var selectedID: String? = nil
    public var onTileTap: ((HeatMapTile) -> Void)? = nil
    public var onTileLongPress: ((HeatMapTile) -> Void)? = nil

    public var changeProvider: ((HeatMapTile) -> Double)? = nil
    public var showValues: Bool = false
    public var weightByVolume: Bool = false
    public var boundOverride: Double? = nil
    public var palette: ColorPalette = .cool
    public var forceWhiteLabels: Bool = false
    public var highlightColors: [String: Color] = [:]
    public var strongBorders: Bool = false
    public var labelDensity: LabelDensity = .normal

    public var onShowAll: (() -> Void)? = nil

    public init(tiles: [HeatMapTile], timeframe: HeatMapTimeframe, selectedID: String? = nil, onTileTap: ((HeatMapTile) -> Void)? = nil, onTileLongPress: ((HeatMapTile) -> Void)? = nil, changeProvider: ((HeatMapTile) -> Double)? = nil, showValues: Bool = false, weightByVolume: Bool = false, boundOverride: Double? = nil, palette: ColorPalette = .cool, forceWhiteLabels: Bool = false, highlightColors: [String: Color] = [:], strongBorders: Bool = false, labelDensity: LabelDensity = .normal, onShowAll: (() -> Void)? = nil) {
        self.tiles = tiles
        self.timeframe = timeframe
        self.selectedID = selectedID
        self.onTileTap = onTileTap
        self.onTileLongPress = onTileLongPress
        self.changeProvider = changeProvider
        self.showValues = showValues
        self.weightByVolume = weightByVolume
        self.boundOverride = boundOverride
        self.palette = palette
        self.forceWhiteLabels = forceWhiteLabels
        self.highlightColors = highlightColors
        self.strongBorders = strongBorders
        self.labelDensity = labelDensity
        self.onShowAll = onShowAll
    }

    @ViewBuilder
    private func showAllOverlay(tilesCount: Int, maxItems: Int, alignTrailing: Bool, onShowAll: (() -> Void)?) -> some View {
        // Hidden overlay to reserve space for chip, always present
        Color.clear
            .frame(width: 120, height: 28)
            .opacity(0)
            .overlay(alignment: alignTrailing ? .topTrailing : .topLeading) {
                if tilesCount > maxItems {
                    let padEdge: Edge.Set = alignTrailing ? .trailing : .leading
                    Button(action: { Haptics.light.impactOccurred(); onShowAll?() }) {
                        Text("Show All (\(max(0, tilesCount - maxItems)))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(6)
                    .padding(padEdge, 8)
                }
            }
    }

    public var body: some View {
        GeometryReader { geo in
            let columnsCount: Int = max(2, Int(geo.size.width / 120))
            // SPACING FIX: Balanced spacing for professional grid appearance
            let itemSpacing: CGFloat = 3
            let outerPadding: CGFloat = 6
            let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: itemSpacing), count: columnsCount)
            let estTileHeight: CGFloat = max(56, geo.size.width / CGFloat(columnsCount) * 0.62)
            // Prefer 3 rows if each row can get at least a reasonable minimum height
            let minRowHeight: CGFloat = 54
            let candidate3Inner: CGFloat = (geo.size.height - itemSpacing * 2 - outerPadding) / 3
            let rowsToShow: Int = (candidate3Inner >= minRowHeight) ? 3 : 2
            let maxItems: Int = min(tiles.count, columnsCount * rowsToShow)
            let displayTiles: [HeatMapTile] = Array(tiles.prefix(maxItems))
            let innerHeight: CGFloat = (geo.size.height - CGFloat(rowsToShow - 1) * itemSpacing - outerPadding) / CGFloat(rowsToShow)
            let tileHeight: CGFloat = min(estTileHeight, innerHeight)
            let aspectRatio: CGFloat = geo.size.width / max(1, geo.size.height)
            let alignTrailing: Bool = (selectedID != nil) || (geo.size.width > 120 && aspectRatio > 1.4)
            let overlayAlignment: Alignment = alignTrailing ? .topTrailing : .topLeading

            LazyVGrid(columns: columns, spacing: itemSpacing) {
                ForEach(displayTiles) { tile in
                    Button {
                        Haptics.light.impactOccurred()
                        onTileTap?(tile)
                    } label: {
                        GeometryReader { proxy in
                            let w = proxy.size.width
                            let h = max(0, proxy.size.height)
                            if w.isFinite && h.isFinite && w > 0.01 && h > 0.01 {
                                GridTile(
                                    tile: tile,
                                    timeframe: timeframe,
                                    selected: selectedID == tile.id,
                                    changeProvider: changeProvider,
                                    showValues: showValues,
                                    weightByVolume: weightByVolume,
                                    boundOverride: boundOverride,
                                    palette: palette,
                                    forceWhiteLabels: forceWhiteLabels,
                                    highlight: highlightColors[tile.id],
                                    strongBorders: strongBorders,
                                    labelDensity: labelDensity,
                                    onTap: {},
                                    onLongPress: {}
                                )
                            } else {
                                Color.clear
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(height: tileHeight)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: overlayAlignment) {
                showAllOverlay(tilesCount: tiles.count, maxItems: maxItems, alignTrailing: alignTrailing, onShowAll: onShowAll)
            }
            .padding(.horizontal, 16)
        }
    }

    private struct GridTile: View {
        let tile: HeatMapTile
        let timeframe: HeatMapTimeframe
        let selected: Bool
        let changeProvider: ((HeatMapTile) -> Double)?
        let showValues: Bool
        let weightByVolume: Bool
        let boundOverride: Double?
        let palette: ColorPalette  // Keep for compatibility but use AppStorage instead
        let forceWhiteLabels: Bool
        let highlight: Color?
        let strongBorders: Bool
        let labelDensity: LabelDensity
        let onTap: () -> Void
        let onLongPress: () -> Void
        
        @State private var chipPop: Bool = false
        @Environment(\.colorScheme) private var colorScheme
        
        // PALETTE FIX: Read palette directly from AppStorage to bypass parameter chain issues
        @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
        private var effectivePalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }

        private var isDark: Bool { colorScheme == .dark }

        var body: some View {
            GeometryReader { proxy in
                let b = boundOverride ?? HeatMapSharedLib.bound(for: timeframe)
                // TIMEFRAME FALLBACK FIX: Use fallback data when exact timeframe is unavailable
                let (changeValue, _) = HeatMapSharedLib.changeWithFallback(for: tile, tf: timeframe)
                let ch = (changeProvider?(tile)) ?? changeValue
                let isLightMode = colorScheme == .light
                // COLOR MATCH FIX: Use ch directly for color to guarantee it matches the displayed percentage
                // Previously used colorWithFallback which recalculated and could get different values
                let fill = HeatMapSharedLib.color(for: ch, bound: b, palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode)
                let labels = HeatMapSharedLib.labelColors(for: ch, bound: b, palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected, isLightMode: isLightMode)
                let badgeLabels = HeatMapSharedLib.badgeLabelColors(for: ch, bound: b, palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected, isLightMode: isLightMode)
                let outlineOpacity = HeatMapSharedLib.labelOutlineOpacity(for: ch, bound: b, palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode)
                let width = proxy.size.width
                let small = width < 110
                let symbol = tile.id == "Others" ? tile.symbol : tile.symbol.uppercased()
                let symbolFont = max(10, min(16, width * 0.28))
                
                // Adaptive border colors using DS.Adaptive design system
                let borderColor: Color = strongBorders 
                    ? DS.Adaptive.strokeStrong 
                    : DS.Adaptive.stroke
                let borderWidth: CGFloat = isDark
                    ? (strongBorders ? 1.5 : (small ? 0.8 : 1.0))
                    : (strongBorders ? 1.4 : 1.2)
                // Balanced inner glow - adds depth without washing out colors
                // LIGHT MODE FIX: Reduced from 0.65 to 0.12 to prevent washing out tile colors
                let innerGlowColor: Color = DS.Adaptive.gradientHighlight.opacity(isDark ? 0.35 : 0.12)
                let selectionBorderColor: Color = isDark 
                    ? Color.white.opacity(0.9) 
                    : DS.Adaptive.textPrimary.opacity(0.7)

                let alignRight = selected || (width > 120 && (width / max(1, proxy.size.height)) > 1.4)
                let chipAlignment: Alignment = alignRight ? .topTrailing : .topLeading
                let padEdge: Edge.Set = alignRight ? .trailing : .leading
                
                // TIMEFRAME FALLBACK FIX: Use card background as fallback for seamless appearance
                // This ensures tiles blend with container during transitions
                let fallbackNeutral = DS.Adaptive.cardBackground

                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        // Base fallback color - ensures tile is never black during transitions
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(fallbackNeutral)
                        // Actual calculated fill on top (uses colorWithFallback for smooth transitions)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(fill)
                    }
                        .overlay(
                            LinearGradient(colors: [innerGlowColor, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(borderColor, lineWidth: borderWidth)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selectionBorderColor, lineWidth: 2)
                                .opacity(selected ? 1 : 0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(highlight ?? .clear, lineWidth: (highlight == nil ? 0 : 3))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        // TRUNCATION FIX: Added .fixedSize() to guarantee no "..." truncation
                        Text(symbol)
                            .font(.system(size: symbolFont, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .fixedSize(horizontal: true, vertical: false)
                        if showValues && width > labelDensity.gridValuesMinWidth {
                            Text(weightByVolume ? HeatMapSharedLib.valueAbbrev(tile.volume) : HeatMapSharedLib.valueAbbrev(tile.marketCap))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .opacity(0.95)
                        }
                    }
                    .foregroundColor(labels.text)
                    .background(labels.backdrop.opacity(small ? 0.92 : 1), in: RoundedRectangle(cornerRadius: small ? 5 : 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: small ? 5 : 6, style: .continuous)
                            .stroke(DS.Adaptive.overlay(0.18), lineWidth: 0.6)
                    )
                    // GRID LABEL FIX: Padding to keep label inside tile edges
                    .padding(.leading, 5)
                    .padding(.bottom, 5)
                }
                .overlay(alignment: chipAlignment) {
                    let metrics = HeatMapSharedLib.badgeMetrics(width: width, height: proxy.size.height)
                    let available = max(10, min(width - 10, metrics.maxW - 6))
                    let chipText = HeatMapSharedLib.condensedPercentString(ch, availableWidth: available)
                    let chipTextWidth = HeatMapSharedLib.measuredTextWidth(chipText, fontSize: metrics.font, weight: .semibold)
                    let chipVisualWidth = chipTextWidth + (metrics.hPad * 2) + 8
                    let symbolWidth = HeatMapSharedLib.measuredTextWidth(symbol, fontSize: symbolFont, weight: .heavy) + 10
                    let hasHorizontalRoom = width >= (chipVisualWidth + min(symbolWidth, width * 0.55) + 12)
                    let showChip = selected || ((width > labelDensity.gridPercentMinWidth) && hasHorizontalRoom)
                    if showChip {
                        SimplePercentChip(
                            text: chipText,
                            fontSize: metrics.font,
                            textColor: badgeLabels.text,
                            backdrop: badgeLabels.backdrop,
                            minWidth: metrics.minW,
                            maxWidth: metrics.maxW,
                            hPad: metrics.hPad,
                            vPad: metrics.vPad
                        )
                        .scaleEffect(chipPop ? 1.06 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: chipPop)
                        .padding(.top, metrics.pad)
                        .padding(padEdge, metrics.lead)
                        .allowsHitTesting(false)
                    }
                }
                .scaleEffect(selected ? 1.02 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
                // SMOOTH COLOR TRANSITION: Animate fill color when timeframe changes or data updates.
                .animation(.easeInOut(duration: 0.45), value: timeframe)
                .animation(.easeInOut(duration: 0.6), value: ch)
                .contentShape(Rectangle())
            }
        }
    }
}

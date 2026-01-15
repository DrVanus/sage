import SwiftUI
import Combine

struct OrderBookView: View {
    @ObservedObject var viewModel: OrderBookViewModel
    let symbol: String
    let isActiveTab: Bool
    @Binding var depthMode: DepthMode
    @Binding var useLogScale: Bool
    var rowsToShow: Int
    var tabBarReserve: CGFloat
    var onSelectPrice: (String) -> Void

    // Local UI state moved from TradeView
    @State private var highlightedBids: Set<String> = []
    @State private var highlightedAsks: Set<String> = []
    @State private var previousBidMap: [String: String] = [:]
    @State private var previousAskMap: [String: String] = [:]
    @State private var bidMaxEMA: Double = 1
    @State private var askMaxEMA: Double = 1

    private var displayedOrderBookRows: Int { rowsToShow }

    // MARK: - Best Bid/Ask & Spread
    private var bestBid: Double {
        viewModel.bids.compactMap { Double($0.price) }.max() ?? 0
    }
    private var bestAsk: Double {
        viewModel.asks.compactMap { Double($0.price) }.min() ?? 0
    }
    private var spreadAbs: Double {
        (bestAsk > 0 && bestBid > 0) ? (bestAsk - bestBid) : 0
    }
    private var spreadPct: Double {
        bestAsk > 0 ? (spreadAbs / bestAsk) * 100.0 : 0
    }
    private var spreadAbsString: String {
        formatPriceWithCommas(spreadAbs)
    }
    private var spreadPctString: String {
        String(format: "%.2f%%", spreadPct)
    }

    // MARK: - Order Book Depth Calculations
    private func bidDepth(_ entry: OrderBookViewModel.OrderBookEntry, maxV: Double) -> CGFloat {
        let value: Double = {
            let p = Double(entry.price) ?? 0
            let q = Double(entry.qty) ?? 0
            return depthMode == .qty ? q : (p * q)
        }()
        let maxV = max(maxV, 1)
        if useLogScale {
            let minV = maxV * 0.002 // 0.2% of max gets a visible width
            let v = max(value, minV)
            let scaled = log(v) - log(minV)
            let denom = log(maxV) - log(minV)
            let norm = denom > 0 ? CGFloat(scaled / denom) : 0
            return min(max(norm, 0.06), 1)
        } else {
            let norm = CGFloat(value / maxV)
            return min(max(norm, 0.04), 1)
        }
    }

    private func askDepth(_ entry: OrderBookViewModel.OrderBookEntry, maxV: Double) -> CGFloat {
        let value: Double = {
            let p = Double(entry.price) ?? 0
            let q = Double(entry.qty) ?? 0
            return depthMode == .qty ? q : (p * q)
        }()
        let maxV = max(maxV, 1)
        if useLogScale {
            let minV = maxV * 0.002
            let v = max(value, minV)
            let scaled = log(v) - log(minV)
            let denom = log(maxV) - log(minV)
            let norm = denom > 0 ? CGFloat(scaled / denom) : 0
            return min(max(norm, 0.06), 1)
        } else {
            let norm = CGFloat(value / maxV)
            return min(max(norm, 0.04), 1)
        }
    }

    // MARK: - UI Subviews
    private func bidsColumn(width: CGFloat) -> some View {
        let localMax = max(bidMaxEMA, 1)
        return LazyVStack(alignment: .leading, spacing: DS.Spacing.orderBookRowSpacing) {
            ForEach(viewModel.bids.prefix(displayedOrderBookRows), id: \.price) { bid in
                // Precompute width values to keep the view tree simple for the compiler
                let depthVal = bidDepth(bid, maxV: localMax)
                let rawW = width * depthVal
                let clampedW = max(min(rawW, width * 0.98), 6)

                ZStack(alignment: .leading) {
                    // Depth bar anchored to the left
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: {
                                        let base = highlightedBids.contains(bid.price) ? 0.55 : 0.35
                                        return [
                                            Color.green.opacity(base),
                                            Color.green.opacity(0)
                                        ]
                                    }()),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: clampedW, height: DS.Spacing.orderBookRowHeight)
                            .opacity(0.55 + 0.35 * Double(depthVal))
                            .cornerRadius(4)
                            .animation(nil, value: viewModel.bids)
                        Spacer(minLength: 0)
                    }
                    // Row content
                    HStack {
                        Text(formatUSD(Double(bid.price) ?? 0))
                            .numeric()
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .allowsTightening(true)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                        Spacer()
                        Text(bid.qty)
                            .numeric()
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .allowsTightening(true)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                    }
                    .frame(width: width, height: DS.Spacing.orderBookRowHeight)
                    .padding(.horizontal, 4)
                }
                .background(highlightedBids.contains(bid.price) ? Color.white.opacity(0.035) : Color.clear)
                .animation(.easeOut(duration: 0.12), value: highlightedBids)
                .frame(width: width, height: DS.Spacing.orderBookRowHeight)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { onSelectPrice(bid.price) }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: displayedOrderBookRows)
        .transaction { $0.animation = nil }
    }

    private func asksColumn(width: CGFloat) -> some View {
        let localMax = max(askMaxEMA, 1)
        return LazyVStack(alignment: .leading, spacing: DS.Spacing.orderBookRowSpacing) {
            ForEach(viewModel.asks.prefix(displayedOrderBookRows), id: \.price) { ask in
                // Precompute width values to keep the view tree simple for the compiler
                let depthVal = askDepth(ask, maxV: localMax)
                let rawW = width * depthVal
                let clampedW = max(min(rawW, width * 0.98), 6)

                ZStack(alignment: .trailing) {
                    // Depth bar anchored to the right
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: {
                                        let base = highlightedAsks.contains(ask.price) ? 0.55 : 0.35
                                        return [
                                            Color.red.opacity(base),
                                            Color.red.opacity(0)
                                        ]
                                    }()),
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: clampedW, height: DS.Spacing.orderBookRowHeight)
                            .opacity(0.55 + 0.35 * Double(depthVal))
                            .cornerRadius(4)
                            .animation(nil, value: viewModel.asks)
                    }
                    // Row content
                    HStack {
                        Text(formatUSD(Double(ask.price) ?? 0))
                            .numeric()
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .allowsTightening(true)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                        Spacer()
                        Text(ask.qty)
                            .numeric()
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .allowsTightening(true)
                            .minimumScaleFactor(0.9)
                            .lineLimit(1)
                    }
                    .frame(width: width, height: DS.Spacing.orderBookRowHeight)
                    .padding(.horizontal, 4)
                }
                .background(highlightedAsks.contains(ask.price) ? Color.white.opacity(0.035) : Color.clear)
                .animation(.easeOut(duration: 0.12), value: highlightedAsks)
                .frame(width: width, height: DS.Spacing.orderBookRowHeight)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { onSelectPrice(ask.price) }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: displayedOrderBookRows)
        .transaction { $0.animation = nil }
    }

    // MARK: - Depth Mode Toggle
    @ViewBuilder
    private var depthModeToggle: some View {
        HStack(spacing: 2) {
            Button(action: { depthMode = .qty }) {
                Text("Qty")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(chipGoldGradient)
                            .opacity(depthMode == .qty ? 1 : 0)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(ctaRimStrokeGradient, lineWidth: depthMode == .qty ? 0.8 : 0)
                    )
                    .foregroundColor(depthMode == .qty ? .black : .white)
            }
            Button(action: { depthMode = .notional }) {
                Text("Notional")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(chipGoldGradient)
                            .opacity(depthMode == .notional ? 1 : 0)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(ctaRimStrokeGradient, lineWidth: depthMode == .notional ? 0.8 : 0)
                    )
                    .foregroundColor(depthMode == .notional ? .black : .white)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Compact header: Bid + best bid | Spread | Ask + best ask
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Bid (\(viewModel.quoteCurrency))")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(bestBid > 0 ? formatUSD(bestBid) : "$0.00")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .opacity(0.95)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Spread \(spreadPctString) • \(spreadAbsString)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text("Ask (\(viewModel.quoteCurrency))")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(bestAsk > 0 ? formatUSD(bestAsk) : "$0.00")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .opacity(0.95)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            let depthHeight: CGFloat = {
                #if os(iOS)
                let screenH: CGFloat = UIScreen.main.bounds.height
                return UIScreen.main.traitCollection.horizontalSizeClass == .compact ? max(CGFloat(460), screenH * 0.58) : max(CGFloat(540), screenH * 0.62)
                #else
                return CGFloat(540)
                #endif
            }()

            ZStack {
                GeometryReader { geometry in
                    let colWidth = geometry.size.width * 0.45
                    let bottomPad = tabBarReserve + 24

                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 16) {
                            bidsColumn(width: colWidth)
                                .frame(width: colWidth, alignment: .leading)
                            asksColumn(width: colWidth)
                                .frame(width: colWidth, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, bottomPad)
                    }
                }
            }
            .clipped()
            .frame(height: depthHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.6), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .frame(height: 24)
            }
            .overlay(alignment: .bottomTrailing) {
                depthModeToggle
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .transaction { $0.animation = nil }
        .padding(.top, 4)
        .onReceive(
            Publishers.CombineLatest(viewModel.$bids, viewModel.$asks)
                .throttle(for: .milliseconds(160), scheduler: RunLoop.main, latest: true)
        ) { newBids, newAsks in
            DispatchQueue.main.async {
                let topBids = newBids.prefix(8)
                let changedBidPrices = topBids.compactMap { entry in
                    if let oldQty = previousBidMap[entry.price] { return oldQty != entry.qty ? entry.price : nil }
                    else { return entry.price }
                }
                previousBidMap = Dictionary(uniqueKeysWithValues: topBids.map { ($0.price, $0.qty) })

                let topAsks = newAsks.prefix(8)
                let changedAskPrices = topAsks.compactMap { entry in
                    if let oldQty = previousAskMap[entry.price] { return oldQty != entry.qty ? entry.price : nil }
                    else { return entry.price }
                }
                previousAskMap = Dictionary(uniqueKeysWithValues: topAsks.map { ($0.price, $0.qty) })

                // Update EMA of depth maxima from latest data (avoid mutating during view update)
                let rawBidMax = newBids.prefix(displayedOrderBookRows).compactMap { entry -> Double? in
                    guard let p = Double(entry.price), let q = Double(entry.qty) else { return nil }
                    return p * q
                }.max() ?? 1
                let rawAskMax = newAsks.prefix(displayedOrderBookRows).compactMap { entry -> Double? in
                    guard let p = Double(entry.price), let q = Double(entry.qty) else { return nil }
                    return p * q
                }.max() ?? 1
                let alpha = isActiveTab ? 0.25 : 0.12
                if bidMaxEMA <= 0 { bidMaxEMA = rawBidMax } else { bidMaxEMA = alpha * rawBidMax + (1 - alpha) * bidMaxEMA }
                if askMaxEMA <= 0 { askMaxEMA = rawAskMax } else { askMaxEMA = alpha * rawAskMax + (1 - alpha) * askMaxEMA }

                if isActiveTab {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        highlightedBids = Set(changedBidPrices)
                        highlightedAsks = Set(changedAskPrices)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            highlightedBids.removeAll()
                            highlightedAsks.removeAll()
                        }
                    }
                } else {
                    highlightedBids.removeAll()
                    highlightedAsks.removeAll()
                }
            }
        }
    }

    // MARK: - Helpers
    private func formatPriceWithCommas(_ value: Double) -> String { formatUSD(value) }
}

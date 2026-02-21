//
//  StrategyLearningHub.swift
//  CryptoSage
//
//  Educational hub for learning about trading strategies,
//  technical indicators, and risk management.
//

import SwiftUI

// MARK: - Strategy Learning Hub View

struct StrategyLearningHub: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedCategory: LearningCategory = .basics
    @State private var expandedTopics: Set<String> = []
    
    /// Optional callback when user wants to create a strategy
    var onCreateStrategy: (() -> Void)?
    /// Optional callback when user wants to browse templates
    var onBrowseTemplates: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome header
                    welcomeHeader
                    
                    // Category tabs
                    categoryTabs
                    
                    // Content for selected category
                    ForEach(selectedCategory.topics) { topic in
                        LearningTopicCard(
                            topic: topic,
                            isExpanded: expandedTopics.contains(topic.id)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if expandedTopics.contains(topic.id) {
                                    expandedTopics.remove(topic.id)
                                } else {
                                    expandedTopics.insert(topic.id)
                                }
                            }
                        }
                    }
                    
                    // Ready to Build CTA Section
                    if onCreateStrategy != nil || onBrowseTemplates != nil {
                        readyToBuildSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Strategy Academy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
    }
    
    // MARK: - Ready to Build CTA Section
    
    private var readyToBuildSection: some View {
        VStack(spacing: 16) {
            // Divider with text
            HStack {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                Text("Ready to Apply What You've Learned?")
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize()
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
            }
            .padding(.top, 20)
            
            // CTA Card
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldBase.opacity(0.2), BrandColors.goldLight.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldBase, BrandColors.goldLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 6) {
                    Text("Start Building")
                        .font(.headline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Put your knowledge into practice by creating your first algorithmic strategy")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    if let onCreateStrategy = onCreateStrategy {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onCreateStrategy()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("Create Strategy")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                        }
                    }
                    
                    if let onBrowseTemplates = onBrowseTemplates {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onBrowseTemplates()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 14))
                                Text("Templates")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DS.Adaptive.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandColors.goldBase.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Welcome Header
    
    private var welcomeHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldBase, BrandColors.goldLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Learn to Build Winning Strategies")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Master technical indicators, risk management, and algorithmic trading concepts")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    BrandColors.goldBase.opacity(0.15),
                    BrandColors.goldBase.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    // MARK: - Category Tabs
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LearningCategory.allCases, id: \.self) { category in
                    CategoryTab(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedCategory = category
                            expandedTopics.removeAll()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Category Tab

struct CategoryTab: View {
    let category: LearningCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(category.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? BrandColors.goldBase : DS.Adaptive.cardBackground)
            .foregroundColor(isSelected ? .black : DS.Adaptive.textPrimary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
}

// MARK: - Learning Topic Card

struct LearningTopicCard: View {
    let topic: LearningTopic
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(topic.color.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: topic.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(topic.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title)
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(topic.subtitle)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Difficulty badge
                    Text(topic.difficulty.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(topic.difficulty.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(topic.difficulty.color.opacity(0.15))
                        .cornerRadius(6)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(16)
            }
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    
                    // Main content
                    Text(topic.content)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineSpacing(4)
                    
                    // Key points
                    if !topic.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Points")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            ForEach(topic.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                    
                                    Text(point)
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                }
                            }
                        }
                    }
                    
                    // Example if available
                    if let example = topic.example {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Example")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text(example)
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Adaptive.overlay(0.05))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Pro tips
                    if !topic.proTips.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text("Pro Tips")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(DS.Adaptive.textPrimary)
                            
                            ForEach(topic.proTips, id: \.self) { tip in
                                Text("• \(tip)")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Learning Category

enum LearningCategory: String, CaseIterable {
    case basics = "Basics"
    case indicators = "Indicators"
    case strategies = "Strategies"
    case risk = "Risk Management"
    
    var icon: String {
        switch self {
        case .basics: return "book.fill"
        case .indicators: return "waveform.path"
        case .strategies: return "cpu"
        case .risk: return "shield.fill"
        }
    }
    
    var topics: [LearningTopic] {
        switch self {
        case .basics:
            return LearningContent.basicTopics
        case .indicators:
            return LearningContent.indicatorTopics
        case .strategies:
            return LearningContent.strategyTopics
        case .risk:
            return LearningContent.riskTopics
        }
    }
}

// MARK: - Learning Topic

struct LearningTopic: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let difficulty: Difficulty
    let content: String
    let keyPoints: [String]
    let example: String?
    let proTips: [String]
    
    enum Difficulty: String {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        
        var color: Color {
            switch self {
            case .beginner: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }
    }
}

// MARK: - Learning Content

enum LearningContent {
    
    // MARK: - Basics
    
    static let basicTopics: [LearningTopic] = [
        LearningTopic(
            id: "what-is-algo",
            title: "What is Algorithmic Trading?",
            subtitle: "Understanding automated strategies",
            icon: "cpu",
            color: .blue,
            difficulty: .beginner,
            content: "Algorithmic trading uses computer programs to execute trades based on predefined rules. Instead of making emotional decisions, algorithms follow strict conditions like 'buy when RSI drops below 30'. This removes human bias and enables consistent execution 24/7.",
            keyPoints: [
                "Removes emotional decision-making",
                "Executes trades automatically based on rules",
                "Enables backtesting against historical data",
                "Works around the clock without fatigue"
            ],
            example: "A simple algorithm: 'Buy BTC when its RSI(14) drops below 30 and MACD turns positive. Sell when RSI exceeds 70.'",
            proTips: [
                "Start with simple strategies and add complexity gradually",
                "Always backtest before deploying with real money",
                "Paper trading lets you validate strategies risk-free"
            ]
        ),
        LearningTopic(
            id: "entry-exit",
            title: "Entry & Exit Signals",
            subtitle: "When to buy and sell",
            icon: "arrow.left.arrow.right",
            color: .purple,
            difficulty: .beginner,
            content: "Entry signals tell you when to open a position (buy), while exit signals tell you when to close it (sell). Good strategies have clear rules for both. Entry without a planned exit is gambling, not trading.",
            keyPoints: [
                "Entry signals define when to open trades",
                "Exit signals define when to close trades",
                "Both should be objective and measurable",
                "Exit rules include both profit-taking and loss-cutting"
            ],
            example: "Entry: Buy when price crosses above the 20-day SMA. Exit: Sell when price crosses below the 20-day SMA OR hits 10% profit OR hits 5% loss.",
            proTips: [
                "Always know your exit before you enter",
                "Use technical indicators for objective signals",
                "Multiple confirmations reduce false signals"
            ]
        ),
        LearningTopic(
            id: "timeframes",
            title: "Understanding Timeframes",
            subtitle: "From minutes to weeks",
            icon: "clock.fill",
            color: .cyan,
            difficulty: .beginner,
            content: "Timeframe determines how often your strategy evaluates conditions. Shorter timeframes (1m, 5m) generate more signals but also more noise. Longer timeframes (1d, 1w) have stronger signals but fewer opportunities. Match your timeframe to your trading style.",
            keyPoints: [
                "Scalping: 1-5 minute charts",
                "Day trading: 15-60 minute charts",
                "Swing trading: 4h-1d charts",
                "Position trading: 1d-1w charts"
            ],
            example: "A day trader might use 15-minute charts for entry timing while checking the 4-hour chart for overall trend direction.",
            proTips: [
                "Start with longer timeframes - they're more forgiving",
                "Higher timeframes filter out market noise",
                "Match position size to timeframe - longer holds need wider stops"
            ]
        )
    ]
    
    // MARK: - Indicators
    
    static let indicatorTopics: [LearningTopic] = [
        LearningTopic(
            id: "rsi",
            title: "RSI (Relative Strength Index)",
            subtitle: "Momentum oscillator 0-100",
            icon: "waveform.path",
            color: .orange,
            difficulty: .beginner,
            content: "RSI measures how fast price is moving up vs down on a scale of 0-100. Below 30 suggests the asset is 'oversold' (potentially due for a bounce). Above 70 suggests 'overbought' (potentially due for a pullback). It works best in ranging markets.",
            keyPoints: [
                "RSI < 30: Oversold - potential buy signal",
                "RSI > 70: Overbought - potential sell signal",
                "Default period is 14 candles",
                "Divergence between RSI and price can signal reversals"
            ],
            example: "RSI drops to 25 while Bitcoin is at $90,000. This oversold condition suggests buyers may step in soon. Combined with support at $89,500, this could be a good entry.",
            proTips: [
                "RSI can stay overbought/oversold for weeks in strong trends",
                "Use RSI divergence for stronger signals",
                "Combine with support/resistance levels for better entries"
            ]
        ),
        LearningTopic(
            id: "macd",
            title: "MACD (Moving Average Convergence Divergence)",
            subtitle: "Trend and momentum indicator",
            icon: "chart.line.uptrend.xyaxis",
            color: .blue,
            difficulty: .intermediate,
            content: "MACD shows the relationship between two moving averages. The MACD line crossing above the signal line is bullish; crossing below is bearish. The histogram shows the distance between these lines - growing histogram means strengthening momentum.",
            keyPoints: [
                "MACD Line = 12 EMA - 26 EMA",
                "Signal Line = 9-period EMA of MACD",
                "Histogram = MACD Line - Signal Line",
                "Crossovers generate buy/sell signals"
            ],
            example: "MACD line crosses above signal line while both are below zero. This 'bullish crossover in bearish territory' often precedes trend reversals.",
            proTips: [
                "MACD is a lagging indicator - signals come after moves start",
                "Zero-line crossovers indicate trend changes",
                "Divergence between MACD and price is a powerful reversal signal"
            ]
        ),
        LearningTopic(
            id: "bollinger",
            title: "Bollinger Bands",
            subtitle: "Volatility-based bands",
            icon: "arrow.up.arrow.down",
            color: .purple,
            difficulty: .intermediate,
            content: "Bollinger Bands consist of a middle band (20 SMA) with upper and lower bands set 2 standard deviations away. When price touches the upper band, it's extended and may pull back. Touching the lower band suggests potential bounce. Band width indicates volatility.",
            keyPoints: [
                "Middle Band: 20-period SMA",
                "Upper/Lower: ±2 standard deviations",
                "Narrow bands = low volatility (squeeze)",
                "Price touching bands doesn't guarantee reversal"
            ],
            example: "Bollinger Bands squeeze tight for 2 weeks, then price breaks above upper band with high volume. This 'Bollinger Squeeze' breakout often leads to strong moves.",
            proTips: [
                "Bands squeeze before breakouts - be ready",
                "Walking the band = strong trend, don't fade it",
                "Combine with RSI for better reversal signals"
            ]
        ),
        LearningTopic(
            id: "moving-averages",
            title: "Moving Averages (SMA/EMA)",
            subtitle: "Trend identification basics",
            icon: "chart.xyaxis.line",
            color: .green,
            difficulty: .beginner,
            content: "Moving averages smooth price data to show trend direction. SMA (Simple) weights all prices equally. EMA (Exponential) weights recent prices more heavily. Common periods: 20 (short-term), 50 (medium), 200 (long-term).",
            keyPoints: [
                "Price above MA = uptrend",
                "Price below MA = downtrend",
                "MA crossovers signal trend changes",
                "200 SMA is widely watched as major support/resistance"
            ],
            example: "50 SMA crosses above 200 SMA = 'Golden Cross' - bullish. 50 SMA crosses below 200 SMA = 'Death Cross' - bearish.",
            proTips: [
                "Use multiple MAs for trend confirmation",
                "EMA reacts faster, SMA is smoother",
                "In strong trends, price bounces off MAs"
            ]
        )
    ]
    
    // MARK: - Strategies
    
    static let strategyTopics: [LearningTopic] = [
        LearningTopic(
            id: "dca",
            title: "DCA (Dollar Cost Averaging)",
            subtitle: "Systematic accumulation",
            icon: "repeat.circle.fill",
            color: .blue,
            difficulty: .beginner,
            content: "DCA involves buying a fixed dollar amount at regular intervals regardless of price. This smooths out volatility and removes timing stress. Great for long-term accumulation of assets you believe in.",
            keyPoints: [
                "Buy fixed amounts at regular intervals",
                "Removes emotion from buying decisions",
                "Works best for long-term holding",
                "Automatic - no technical analysis needed"
            ],
            example: "Buy $100 of Bitcoin every Monday. Over time, you'll buy more when prices are low and less when high, averaging out your cost basis.",
            proTips: [
                "DCA works best in long-term uptrends",
                "Consider increasing buys during major dips",
                "Set it and forget it - consistency is key"
            ]
        ),
        LearningTopic(
            id: "grid",
            title: "Grid Trading",
            subtitle: "Profit from volatility",
            icon: "square.grid.3x3.fill",
            color: .purple,
            difficulty: .intermediate,
            content: "Grid trading places buy orders below current price and sell orders above, creating a 'grid'. As price oscillates, the bot captures profits from each swing. Works best in ranging, volatile markets - not trending markets.",
            keyPoints: [
                "Places orders at regular price intervals",
                "Profits from price oscillation",
                "Best in sideways, volatile markets",
                "Can lose in strong trending markets"
            ],
            example: "BTC trading between $90,000-$95,000. Set buy orders every $500 below current price and sells $500 above. Each swing captures $500 profit per grid level.",
            proTips: [
                "Wide grids = fewer trades but larger profits per trade",
                "Tight grids = more trades but smaller profits",
                "Set stop loss below grid range for protection"
            ]
        ),
        LearningTopic(
            id: "trend-following",
            title: "Trend Following",
            subtitle: "Ride the momentum",
            icon: "arrow.up.right",
            color: .green,
            difficulty: .intermediate,
            content: "Trend following strategies buy when price starts moving up and sell when it starts moving down. They aim to catch the 'meat' of major moves. Uses moving averages, breakouts, or momentum indicators to identify trends.",
            keyPoints: [
                "Buy when uptrend confirmed",
                "Sell when downtrend confirmed",
                "Accepts missing exact tops/bottoms",
                "Wins big but has many small losses"
            ],
            example: "Buy when price closes above 50 SMA with RSI > 50. Sell when price closes below 50 SMA OR hits trailing stop. This captures major trends.",
            proTips: [
                "The trend is your friend - don't fight it",
                "Use trailing stops to lock in profits",
                "Expect many small losses for occasional big wins"
            ]
        ),
        LearningTopic(
            id: "mean-reversion",
            title: "Mean Reversion",
            subtitle: "Fade the extremes",
            icon: "arrow.triangle.swap",
            color: .orange,
            difficulty: .advanced,
            content: "Mean reversion assumes prices eventually return to their average. Buy when price is far below the mean (oversold), sell when far above (overbought). Works in ranging markets, fails in trending markets.",
            keyPoints: [
                "Buy oversold conditions (RSI < 30)",
                "Sell overbought conditions (RSI > 70)",
                "Price reverts to moving average",
                "Counter-trend trading"
            ],
            example: "RSI drops below 25 while price is 3 standard deviations below 20 SMA. Buy expecting bounce back to the mean.",
            proTips: [
                "Never fade a strong trend - mean reversion fails in trends",
                "Use tight stops - if it's not reversing, get out",
                "Combine multiple oversold indicators for confirmation"
            ]
        )
    ]
    
    // MARK: - Risk Management
    
    static let riskTopics: [LearningTopic] = [
        LearningTopic(
            id: "stop-loss",
            title: "Stop Losses",
            subtitle: "Protect your capital",
            icon: "shield.lefthalf.filled",
            color: .red,
            difficulty: .beginner,
            content: "A stop loss automatically sells your position if price falls to a certain level, limiting your loss. Without stop losses, small losses can become account-destroying losses. Always define your maximum loss before entering a trade.",
            keyPoints: [
                "Limits maximum loss per trade",
                "Should be set based on volatility (ATR)",
                "Place below support levels, not at them",
                "Crypto typically needs wider stops (5-10%)"
            ],
            example: "Buy BTC at $95,000. Set stop loss at $90,250 (5% below entry). Maximum loss is defined before the trade begins.",
            proTips: [
                "Never move stops further away from entry",
                "Use ATR to set stops based on actual volatility",
                "Mental stops don't count - always use actual orders"
            ]
        ),
        LearningTopic(
            id: "position-sizing",
            title: "Position Sizing",
            subtitle: "How much to risk per trade",
            icon: "chart.pie.fill",
            color: .blue,
            difficulty: .intermediate,
            content: "Position sizing determines how much capital to risk on each trade. The 1-2% rule suggests risking no more than 1-2% of your account per trade. This ensures no single trade can significantly damage your account.",
            keyPoints: [
                "Risk 1-2% of account per trade",
                "Position size = Risk Amount / (Entry - Stop Loss)",
                "Larger stops = smaller position sizes",
                "Preserves capital through losing streaks"
            ],
            example: "Account: $10,000. Max risk: 2% = $200. Entry: $95,000. Stop: $90,000 ($5,000 risk per BTC). Position size: $200 / $5,000 = 0.04 BTC.",
            proTips: [
                "Calculate position size BEFORE entering trade",
                "Reduce size during losing streaks",
                "Scale into positions to manage risk"
            ]
        ),
        LearningTopic(
            id: "risk-reward",
            title: "Risk/Reward Ratio",
            subtitle: "Make winners bigger than losers",
            icon: "scale.3d",
            color: .green,
            difficulty: .beginner,
            content: "Risk/Reward ratio compares potential profit to potential loss. A 1:2 R/R means you risk $1 to potentially make $2. Even with 50% win rate, positive R/R makes you profitable over time.",
            keyPoints: [
                "Aim for minimum 1:1.5 or 1:2",
                "Higher R/R = can be profitable with lower win rate",
                "R/R = (Target - Entry) / (Entry - Stop)",
                "Don't take trades with poor R/R"
            ],
            example: "Entry: $95,000. Stop: $93,000 (risk $2,000). Target: $101,000 (reward $6,000). R/R = 1:3. Even 40% win rate is profitable.",
            proTips: [
                "Quality over quantity - only take good R/R setups",
                "Use support/resistance for realistic targets",
                "Trailing stops can improve R/R on winning trades"
            ]
        ),
        LearningTopic(
            id: "drawdown",
            title: "Managing Drawdown",
            subtitle: "Surviving the dips",
            icon: "arrow.down.right.circle.fill",
            color: .orange,
            difficulty: .intermediate,
            content: "Drawdown is the peak-to-trough decline during a losing period. A 50% drawdown requires 100% gain to recover. Managing drawdown through position sizing and stop losses is crucial for long-term survival.",
            keyPoints: [
                "10% drawdown needs 11% to recover",
                "25% drawdown needs 33% to recover",
                "50% drawdown needs 100% to recover",
                "Set maximum acceptable drawdown (20-25%)"
            ],
            example: "Account drops from $10,000 to $7,500 (25% drawdown). To recover, you need 33% gain on $7,500 = $2,500 to get back to $10,000.",
            proTips: [
                "Reduce position sizes after losses",
                "Take a break after 3-5 consecutive losses",
                "Review and adjust strategy if drawdown exceeds limits"
            ]
        )
    ]
}

// MARK: - Preview

#if DEBUG
struct StrategyLearningHub_Previews: PreviewProvider {
    static var previews: some View {
        StrategyLearningHub()
            .preferredColorScheme(.dark)
    }
}
#endif

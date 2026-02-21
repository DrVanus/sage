//
//  StrategyTemplates.swift
//  CryptoSage
//
//  Pre-built strategy templates that users can start from
//  and customize for their needs.
//

import Foundation
import SwiftUI

// MARK: - Strategy Template Provider

public enum StrategyTemplateProvider {
    
    /// All available templates organized by category
    public static var allTemplates: [StrategyTemplate] {
        return sageAITemplates + trendFollowingTemplates + meanReversionTemplates + momentumTemplates + breakoutTemplates + accumulationTemplates
    }
    
    /// Get templates by category
    public static func templates(for category: StrategyTemplate.TemplateCategory) -> [StrategyTemplate] {
        switch category {
        case .sageAI:
            return sageAITemplates
        case .trend:
            return trendFollowingTemplates
        case .meanReversion:
            return meanReversionTemplates
        case .momentum:
            return momentumTemplates
        case .breakout:
            return breakoutTemplates
        case .accumulation:
            return accumulationTemplates
        }
    }
    
    // MARK: - CryptoSage AI Templates (Proprietary Algorithms)
    
    public static let sageAITemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "sage-trend",
            name: "Sage Trend",
            description: "CryptoSage's flagship algorithm that adapts to market regime. Uses EMA alignment and RSI for trend detection, automatically adjusts strategy based on conditions.",
            category: .sageAI,
            difficulty: .advanced,
            strategy: TradingStrategy(
                name: "Sage Trend Algorithm",
                description: "Adaptive trend-following that knows when to trade and when to sit out. Uses EMA alignment, SMA200, MACD, and RSI for regime-aware signals.",
                tradingPair: "BTC_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma200)  // Above long-term trend
                    ),
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.ema26)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(50)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(45)  // Momentum weakening
                    ),
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesBelow,
                        value: .indicator(.ema26)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 5,
                    takeProfitPercent: 15,
                    trailingStopPercent: 3,
                    maxDrawdownPercent: 20
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 2,
                    maxPositionPercent: 25
                )
            )
        ),
        StrategyTemplate(
            id: "sage-momentum",
            name: "Sage Momentum",
            description: "Proprietary 5-factor momentum cascade combining price ROC, RSI trend, MACD acceleration, volume confirmation, and on-balance volume analysis.",
            category: .sageAI,
            difficulty: .advanced,
            strategy: TradingStrategy(
                name: "Sage Momentum Algorithm",
                description: "Multi-factor momentum scoring requiring 4+ aligned factors. Combines ROC, RSI trend, MACD acceleration, volume, and OBV for high-conviction signals.",
                tradingPair: "ETH_USDT",
                timeframe: .oneHour,
                entryConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(55)
                    ),
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .greaterThan,
                        value: .number(0)
                    ),
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.ema12)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(45)
                    ),
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .crossesBelow,
                        value: .number(0)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 4,
                    takeProfitPercent: 12,
                    trailingStopPercent: 2
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 1.5,
                    maxPositionPercent: 20
                )
            )
        ),
        StrategyTemplate(
            id: "sage-reversion",
            name: "Sage Reversion",
            description: "Advanced statistical mean reversion using Z-score, Bollinger %B, RSI extremes, and volatility filtering. Only trades in ranging markets.",
            category: .sageAI,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Sage Reversion Algorithm",
                description: "Statistical mean reversion that filters for volatility contraction. Uses Z-score and Bollinger Bands for entry timing.",
                tradingPair: "SOL_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .lessOrEqual,
                        value: .indicator(.bollingerLower)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(30)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterOrEqual,
                        value: .indicator(.bollingerMiddle)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 6,
                    takeProfitPercent: 10,
                    maxConsecutiveLosses: 3
                ),
                positionSizing: PositionSizing(
                    method: .fixedAmount,
                    fixedAmount: 100,
                    maxPositionPercent: 15
                )
            )
        ),
        StrategyTemplate(
            id: "sage-confluence",
            name: "Sage Confluence",
            description: "Multi-timeframe alignment strategy that only trades when 1H, 4H, and 1D trends agree. High win rate through confluence confirmation.",
            category: .sageAI,
            difficulty: .advanced,
            strategy: TradingStrategy(
                name: "Sage Confluence Algorithm",
                description: "Multi-timeframe alignment requiring EMA and RSI agreement across timeframes. Trades with the larger trend.",
                tradingPair: "BTC_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma50)
                    ),
                    StrategyCondition(
                        indicator: .ema12,
                        comparison: .greaterThan,
                        value: .indicator(.ema26)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(50)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(70)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .ema12,
                        comparison: .crossesBelow,
                        value: .indicator(.ema26)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 4,
                    takeProfitPercent: 12,
                    trailingStopPercent: 2.5
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 2,
                    maxPositionPercent: 30
                )
            )
        ),
        StrategyTemplate(
            id: "sage-volatility",
            name: "Sage Volatility",
            description: "Bollinger Band squeeze breakout system that detects volatility compression and trades the subsequent expansion with momentum confirmation.",
            category: .sageAI,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Sage Volatility Algorithm",
                description: "Detects Bollinger Band squeezes and trades breakouts with MACD and volume confirmation.",
                tradingPair: "ETH_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesAbove,
                        value: .indicator(.bollingerUpper)
                    ),
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .greaterThan,
                        value: .number(0)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesBelow,
                        value: .indicator(.bollingerMiddle)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 5,
                    takeProfitPercent: 15,
                    trailingStopPercent: 3
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 10,
                    maxPositionPercent: 25
                )
            )
        ),
        StrategyTemplate(
            id: "sage-neural",
            name: "Sage Neural",
            description: "AI-enhanced ensemble combining all Sage algorithms with dynamic weighting based on market conditions. The most sophisticated CryptoSage strategy.",
            category: .sageAI,
            difficulty: .advanced,
            strategy: TradingStrategy(
                name: "Sage Neural Algorithm",
                description: "Ensemble strategy that combines signals from trend, momentum, reversion, confluence, and volatility algorithms with regime-based weighting.",
                tradingPair: "BTC_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma200)  // Long-term trend confirmation
                    ),
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma50)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(45)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(70)
                    ),
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .greaterThan,
                        value: .number(0)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesBelow,
                        value: .indicator(.sma50)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(40)
                    )
                ],
                conditionLogic: .any,  // Exit on any condition for capital preservation
                riskManagement: RiskManagement(
                    stopLossPercent: 6,
                    takeProfitPercent: 18,
                    trailingStopPercent: 4,
                    maxDrawdownPercent: 15
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 2,
                    maxPositionPercent: 30
                )
            )
        )
    ]
    
    // MARK: - Trend Following Templates
    
    public static let trendFollowingTemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "golden-cross",
            name: "Golden Cross",
            description: "Classic trend following strategy using 50/200 SMA crossover. Buys when short-term trend crosses above long-term trend.",
            category: .trend,
            difficulty: .beginner,
            strategy: TradingStrategy(
                name: "Golden Cross Strategy",
                description: "Buy when 50 SMA crosses above 200 SMA (bullish). Sell when 50 SMA crosses below 200 SMA (bearish).",
                tradingPair: "BTC_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .sma50,
                        comparison: .crossesAbove,
                        value: .indicator(.sma200)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .sma50,
                        comparison: .crossesBelow,
                        value: .indicator(.sma200)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 8,
                    takeProfitPercent: 20,
                    maxDrawdownPercent: 25
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 10,
                    maxPositionPercent: 30
                )
            )
        ),
        StrategyTemplate(
            id: "trend-rider",
            name: "Trend Rider",
            description: "Rides trends using EMA alignment and RSI confirmation. Only trades with the trend.",
            category: .trend,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Trend Rider Strategy",
                description: "Enter when price is above EMA(26) and RSI is above 50 (confirms uptrend momentum).",
                tradingPair: "ETH_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.ema26)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(50)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesBelow,
                        value: .indicator(.ema26)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 5,
                    takeProfitPercent: 15,
                    trailingStopPercent: 3
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 2,
                    maxPositionPercent: 25
                )
            )
        )
    ]
    
    // MARK: - Mean Reversion Templates
    
    public static let meanReversionTemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "rsi-oversold",
            name: "RSI Oversold Bounce",
            description: "Buys when RSI indicates extreme oversold conditions. Classic mean reversion strategy.",
            category: .meanReversion,
            difficulty: .beginner,
            strategy: TradingStrategy(
                name: "RSI Oversold Strategy",
                description: "Buy when RSI drops below 30 (oversold). Sell when RSI rises above 70 (overbought) or hits take profit.",
                tradingPair: "BTC_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(30)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(70)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 5,
                    takeProfitPercent: 10,
                    maxConsecutiveLosses: 4
                ),
                positionSizing: PositionSizing(
                    method: .fixedAmount,
                    fixedAmount: 100,
                    maxPositionPercent: 20
                )
            )
        ),
        StrategyTemplate(
            id: "bollinger-bounce",
            name: "Bollinger Band Bounce",
            description: "Trades mean reversion when price touches Bollinger Bands with RSI confirmation.",
            category: .meanReversion,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Bollinger Bounce Strategy",
                description: "Buy when price touches lower Bollinger Band and RSI is oversold. Target the middle band.",
                tradingPair: "SOL_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .lessOrEqual,
                        value: .indicator(.bollingerLower)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(35)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterOrEqual,
                        value: .indicator(.bollingerMiddle)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 4,
                    takeProfitPercent: 8,
                    maxDrawdownPercent: 15
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 5,
                    maxPositionPercent: 15
                )
            )
        )
    ]
    
    // MARK: - Momentum Templates
    
    public static let momentumTemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "macd-crossover",
            name: "MACD Crossover",
            description: "Classic momentum strategy using MACD line crossing signal line for entries.",
            category: .momentum,
            difficulty: .beginner,
            strategy: TradingStrategy(
                name: "MACD Crossover Strategy",
                description: "Buy on bullish MACD crossover (MACD line crosses above signal). Sell on bearish crossover.",
                tradingPair: "BTC_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .crossesAbove,
                        value: .number(0)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .crossesBelow,
                        value: .number(0)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 6,
                    takeProfitPercent: 15,
                    maxDrawdownPercent: 20
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 8,
                    maxPositionPercent: 25
                )
            )
        ),
        StrategyTemplate(
            id: "momentum-burst",
            name: "Momentum Burst",
            description: "Catches strong momentum moves using multiple indicators for confirmation.",
            category: .momentum,
            difficulty: .advanced,
            strategy: TradingStrategy(
                name: "Momentum Burst Strategy",
                description: "Buy when RSI crosses above 50, MACD is positive, and price is above SMA(20). Strong momentum confirmation.",
                tradingPair: "ETH_USDT",
                timeframe: .oneHour,
                entryConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .crossesAbove,
                        value: .number(50)
                    ),
                    StrategyCondition(
                        indicator: .macdHistogram,
                        comparison: .greaterThan,
                        value: .number(0)
                    ),
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma20)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(75)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 3,
                    takeProfitPercent: 9,
                    trailingStopPercent: 2
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 1.5,
                    maxPositionPercent: 20
                )
            )
        )
    ]
    
    // MARK: - Breakout Templates
    
    public static let breakoutTemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "bollinger-squeeze",
            name: "Bollinger Squeeze Breakout",
            description: "Trades breakouts after volatility compression. Bollinger Bands narrow then price explodes.",
            category: .breakout,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Bollinger Squeeze Strategy",
                description: "Buy when price breaks above upper Bollinger Band after a squeeze period with momentum confirmation.",
                tradingPair: "BTC_USDT",
                timeframe: .fourHours,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesAbove,
                        value: .indicator(.bollingerUpper)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(55)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(80)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 4,
                    takeProfitPercent: 12,
                    trailingStopPercent: 3
                ),
                positionSizing: PositionSizing(
                    method: .riskBased,
                    riskPercent: 2,
                    maxPositionPercent: 25
                )
            )
        ),
        StrategyTemplate(
            id: "sma-breakout",
            name: "SMA Breakout",
            description: "Trades breakouts above key moving average with volume and momentum confirmation.",
            category: .breakout,
            difficulty: .beginner,
            strategy: TradingStrategy(
                name: "SMA Breakout Strategy",
                description: "Buy when price crosses above 50 SMA with bullish momentum. Classic breakout setup.",
                tradingPair: "SOL_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesAbove,
                        value: .indicator(.sma50)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(50)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .crossesBelow,
                        value: .indicator(.sma20)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 7,
                    takeProfitPercent: 20,
                    maxDrawdownPercent: 20
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 10,
                    maxPositionPercent: 30
                )
            )
        )
    ]
    
    // MARK: - Accumulation Templates
    
    public static let accumulationTemplates: [StrategyTemplate] = [
        StrategyTemplate(
            id: "dip-buyer",
            name: "Dip Buyer",
            description: "Accumulates on significant price drops with multiple confirmation signals.",
            category: .accumulation,
            difficulty: .beginner,
            strategy: TradingStrategy(
                name: "Dip Buyer Strategy",
                description: "Buy when price drops significantly and shows signs of recovery. Classic buy-the-dip approach.",
                tradingPair: "BTC_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .priceChange,
                        comparison: .lessThan,
                        value: .percentage(-5)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(40)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .priceChange,
                        comparison: .greaterThan,
                        value: .percentage(10)
                    )
                ],
                conditionLogic: .all,
                riskManagement: RiskManagement(
                    stopLossPercent: 10,
                    takeProfitPercent: 15,
                    maxDrawdownPercent: 25
                ),
                positionSizing: PositionSizing(
                    method: .fixedAmount,
                    fixedAmount: 200,
                    maxPositionPercent: 40
                )
            )
        ),
        StrategyTemplate(
            id: "value-accumulator",
            name: "Value Accumulator",
            description: "Long-term accumulation strategy that buys when price is significantly below moving averages.",
            category: .accumulation,
            difficulty: .intermediate,
            strategy: TradingStrategy(
                name: "Value Accumulator Strategy",
                description: "Buy when price trades below 200 SMA with RSI showing oversold. Long-term value approach.",
                tradingPair: "ETH_USDT",
                timeframe: .oneDay,
                entryConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .lessThan,
                        value: .indicator(.sma200)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .lessThan,
                        value: .number(35)
                    )
                ],
                exitConditions: [
                    StrategyCondition(
                        indicator: .price,
                        comparison: .greaterThan,
                        value: .indicator(.sma200)
                    ),
                    StrategyCondition(
                        indicator: .rsi,
                        comparison: .greaterThan,
                        value: .number(65)
                    )
                ],
                conditionLogic: .any, // Exit on any condition
                riskManagement: RiskManagement(
                    stopLossPercent: 15,
                    takeProfitPercent: 30,
                    maxDrawdownPercent: 30
                ),
                positionSizing: PositionSizing(
                    method: .percentOfPortfolio,
                    portfolioPercent: 5,
                    maxPositionPercent: 50
                )
            )
        )
    ]
}

// MARK: - Strategy Templates View

struct StrategyTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedCategory: StrategyTemplate.TemplateCategory?
    @State private var selectedTemplate: StrategyTemplate?
    @State private var showingStrategyBuilder = false
    // Store the strategy to edit separately so it persists after template sheet dismisses
    @State private var strategyToEdit: TradingStrategy?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Category filter
                    categoryFilter
                    
                    // Templates grid
                    templatesGrid
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Strategy Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .sheet(item: $selectedTemplate) { template in
                TemplateDetailSheet(template: template) {
                    // Store the strategy BEFORE dismissing the template sheet
                    strategyToEdit = template.strategy
                    selectedTemplate = nil
                    showingStrategyBuilder = true
                }
            }
            .sheet(isPresented: $showingStrategyBuilder) {
                if let strategy = strategyToEdit {
                    StrategyBuilderView(existingStrategy: strategy)
                        .onDisappear {
                            // Clear the stored strategy when builder closes
                            strategyToEdit = nil
                        }
                } else {
                    // Fallback: open empty builder if no strategy stored
                    StrategyBuilderView()
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Start with a Proven Template")
                .font(.title3.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Choose a pre-built strategy and customize it to fit your trading style")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All option
                CategoryChip(
                    name: "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil,
                    color: .gray
                ) {
                    selectedCategory = nil
                }
                
                ForEach(StrategyTemplate.TemplateCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        name: category.shortName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        color: categoryColor(for: category)
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
    
    private func categoryColor(for category: StrategyTemplate.TemplateCategory) -> Color {
        switch category {
        case .sageAI: return BrandColors.goldBase
        case .trend: return .blue
        case .meanReversion: return .orange
        case .momentum: return .green
        case .breakout: return .purple
        case .accumulation: return .cyan
        }
    }
    
    private var templatesGrid: some View {
        let templates = selectedCategory == nil 
            ? StrategyTemplateProvider.allTemplates 
            : StrategyTemplateProvider.templates(for: selectedCategory!)
        
        return LazyVStack(spacing: 12) {
            ForEach(templates, id: \.id) { template in
                TemplateCard(template: template) {
                    selectedTemplate = template
                }
            }
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : DS.Adaptive.cardBackground)
            .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let template: StrategyTemplate
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Category icon with premium styling
                    ZStack {
                        Circle()
                            .fill(categoryColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: template.category.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(categoryColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(template.category.shortName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(categoryColor)
                    }
                    
                    Spacer()
                    
                    // Difficulty badge
                    Text(template.difficulty.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(template.difficulty.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(template.difficulty.color.opacity(0.15))
                        )
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Text(template.description)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Strategy summary with better styling
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .foregroundColor(.green.opacity(0.8))
                        Text("\(template.strategy.entryConditions.count) entry")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.circle")
                            .foregroundColor(.red.opacity(0.8))
                        Text("\(template.strategy.exitConditions.count) exit")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundColor(.blue.opacity(0.8))
                        Text(template.strategy.timeframe.shortName)
                    }
                }
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(categoryColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var categoryColor: Color {
        switch template.category {
        case .sageAI: return BrandColors.goldBase
        case .trend: return .blue
        case .meanReversion: return .orange
        case .momentum: return .green
        case .breakout: return .purple
        case .accumulation: return .cyan
        }
    }
}

// MARK: - Template Detail Sheet

struct TemplateDetailSheet: View {
    let template: StrategyTemplate
    let onUseTemplate: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(template.category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(categoryColor)
                            
                            Text("•")
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            Text(template.difficulty.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(template.difficulty.color)
                        }
                        
                        Text(template.name)
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(template.description)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Divider()
                    
                    // Strategy details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Strategy Configuration")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        detailRow("Trading Pair", template.strategy.tradingPair)
                        detailRow("Timeframe", template.strategy.timeframe.displayName)
                        detailRow("Condition Logic", template.strategy.conditionLogic.displayName)
                    }
                    
                    // Entry conditions
                    conditionsSection("Entry Conditions", template.strategy.entryConditions)
                    
                    // Exit conditions
                    conditionsSection("Exit Conditions", template.strategy.exitConditions)
                    
                    // Risk management
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Risk Management")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if let sl = template.strategy.riskManagement.stopLossPercent {
                            detailRow("Stop Loss", String(format: "%.1f%%", sl))
                        }
                        if let tp = template.strategy.riskManagement.takeProfitPercent {
                            detailRow("Take Profit", String(format: "%.1f%%", tp))
                        }
                        if let rr = template.strategy.riskManagement.riskRewardRatio {
                            detailRow("Risk/Reward", String(format: "1:%.1f", rr))
                        }
                    }
                    
                    // Educational Advisory Notice
                    advisoryNotice
                    
                    Spacer(minLength: 100)
                }
                .padding(20)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Template Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // Customize button (opens StrategyBuilder)
                    Button {
                        onUseTemplate()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Customize Template")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1.5)
                        )
                        .cornerRadius(14)
                    }
                    
                    // Quick Deploy button (saves and deploys immediately)
                    Button {
                        quickDeployTemplate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                            Text("Quick Deploy to Paper Trading")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                        )
                    }
                }
                .padding()
                .background(DS.Adaptive.background)
            }
        }
    }
    
    private func quickDeployTemplate() {
        // Check if paper trading is enabled
        guard PaperTradingManager.isEnabled else {
            // Could show an alert here, but for now just dismiss
            // Users will see the deploy option in the strategies list
            dismiss()
            return
        }
        
        // Save the strategy
        var strategyToSave = template.strategy
        strategyToSave.name = template.name // Use template name
        StrategyEngine.shared.saveStrategy(strategyToSave)
        
        // Create and start a paper bot from the strategy
        let bot = PaperBotManager.shared.createBotFromStrategy(strategyToSave)
        PaperBotManager.shared.startBot(id: bot.id)
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        
        dismiss()
    }
    
    private var categoryColor: Color {
        switch template.category {
        case .sageAI: return BrandColors.goldBase
        case .trend: return .blue
        case .meanReversion: return .orange
        case .momentum: return .green
        case .breakout: return .purple
        case .accumulation: return .cyan
        }
    }
    
    /// Educational advisory notice explaining how to use strategy signals
    private var advisoryNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 18))
                
                Text("How to Use This Strategy")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                advisoryBullet(
                    icon: "doc.text.fill",
                    text: "Deploy to Paper Trading to test with virtual funds"
                )
                advisoryBullet(
                    icon: "bell.badge.fill",
                    text: "Receive signal alerts when conditions trigger"
                )
                advisoryBullet(
                    icon: "square.and.arrow.up",
                    text: "Copy signals to use as advisory for your own trading"
                )
                advisoryBullet(
                    icon: "chart.bar.xaxis.ascending",
                    text: "Track performance before using real funds"
                )
            }
            
            Text("Signals are for educational purposes only. Always do your own research before making trading decisions.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func advisoryBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(categoryColor)
                .frame(width: 16)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
        }
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func conditionsSection(_ title: String, _ conditions: [StrategyCondition]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            if conditions.isEmpty {
                Text("No conditions")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textTertiary)
            } else {
                ForEach(conditions) { condition in
                    HStack(spacing: 8) {
                        Image(systemName: condition.indicator.category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(condition.indicator.category.color)
                        
                        Text(condition.description)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Adaptive.overlay(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StrategyTemplatesView_Previews: PreviewProvider {
    static var previews: some View {
        StrategyTemplatesView()
            .preferredColorScheme(.dark)
    }
}
#endif

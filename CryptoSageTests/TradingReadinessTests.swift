import Testing
@testable import CryptoSage

struct TradingReadinessTests {
    @Test("Capability matrix maps derivatives exchange identifiers")
    func capabilityMatrixExchangeMapping() {
        #expect(TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: "coinbase") == .coinbase)
        #expect(TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: "binance") == .binance)
        #expect(TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: "kucoin") == .kucoin)
        #expect(TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: "bybit") == .bybit)
        #expect(TradingCapabilityMatrix.tradingExchange(forDerivativesExchangeId: "unknown") == nil)
    }
    
    @Test("Capability matrix reflects paper short limitation")
    func paperShortingCapabilityIsDisabled() {
        let coinbaseProfile = TradingCapabilityMatrix.profile(for: .coinbase)
        #expect(coinbaseProfile.supportsLiveDerivatives)
        #expect(coinbaseProfile.supportsLeverage)
        #expect(coinbaseProfile.supportsLiveShorting)
        #expect(!coinbaseProfile.supportsPaperShorting)
        #expect(!TradingCapabilityMatrix.paperTradingProfile.supportsPaperShorting)
    }
    
    @MainActor
    @Test("Trade view model blocks paper-mode short sells")
    func tradeViewModelBlocksPaperShorts() {
        let viewModel = TradeViewModel(symbol: "BTCUSDT")
        viewModel.currentPrice = 100_000
        viewModel.balance = 0
        viewModel.quoteBalance = 10_000
        
        viewModel.executeTrade(
            side: .sell,
            symbol: "BTCUSDT",
            orderType: .market,
            quantity: "0.01"
        )
        
        #expect(viewModel.orderErrorMessage?.contains("short positions are not supported") == true)
    }
}

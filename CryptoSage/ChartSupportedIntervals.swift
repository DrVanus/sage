import Foundation

// Shared list of supported chart intervals used across TradeView and CoinDetailView.
// Keeping this in a single place avoids mismatches between screens.
// Full set of 15 intervals for comprehensive timeframe selection.
let supportedIntervals: [ChartInterval] = [
    .live,
    .oneMin,
    .fiveMin,
    .fifteenMin,
    .thirtyMin,
    .oneHour,
    .fourHour,
    .oneDay,
    .oneWeek,
    .oneMonth,
    .threeMonth,
    .sixMonth,
    .oneYear,
    .threeYear,
    .all
]


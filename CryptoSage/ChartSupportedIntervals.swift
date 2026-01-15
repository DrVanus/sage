import Foundation

// Shared list of supported chart intervals used across TradeView and CoinDetailView.
// Keeping this in a single place avoids mismatches between screens.
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
    .oneYear,
    .threeYear,
    .all
]


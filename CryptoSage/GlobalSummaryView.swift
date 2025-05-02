//
// GlobalSummaryView.swift
// CryptoSage
//
// Created by ChatGPT on 05/24/25
// Deprecated: replaced by MarketStatsView. Remove this file if no longer referenced.
//

import SwiftUI

@available(*, deprecated, message: "Use MarketStatsView instead")
struct GlobalSummaryView: View {
    var body: some View {
        Text("GlobalSummaryView is deprecated. Use MarketStatsView.")
            .italic()
            .foregroundColor(.gray)
    }
}

struct GlobalSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        GlobalSummaryView()
    }
}

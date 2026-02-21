//
//  PriceView.swift
//  CryptoSage
//
//  Created by DM on 7/17/25.
//


import SwiftUI

struct PriceView: View {
    @ObservedObject var viewModel: PriceViewModel

    init(symbol: String) {
        _viewModel = ObservedObject(wrappedValue:
            PriceViewModel(symbol: symbol, timeframe: .live)
        )
    }

    var body: some View {
        VStack {
            Text("$\(viewModel.price, specifier: "%.2f")")
                .font(.largeTitle)
                .bold()
                .monospacedDigit()
                // PERFORMANCE FIX: Use contentTransition for efficient numeric text updates
                // This is GPU-accelerated and more efficient than full view animations
                .contentTransition(.numericText(countsDown: false))
                // Only animate if not scrolling to preserve 60fps during scroll
                .transaction { txn in
                    if ScrollStateManager.shared.isScrolling {
                        txn.animation = nil
                    } else {
                        txn.animation = .easeInOut(duration: 0.2)
                    }
                }

            // …any other UI…
        }
    }
}

// Preview
struct PriceView_Previews: PreviewProvider {
    static var previews: some View {
        PriceView(symbol: "BTC")
    }
}

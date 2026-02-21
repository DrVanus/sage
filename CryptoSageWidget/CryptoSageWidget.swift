//
//  CryptoSageWidget.swift
//  CryptoSageWidget
//
//  Widget extension entry point for CryptoSage iOS widgets.
//

import WidgetKit
import SwiftUI

@main
struct CryptoSageWidgetBundle: WidgetBundle {
    var body: some Widget {
        PriceTickerWidget()
        PortfolioWidget()
        FearGreedWidget()
    }
}

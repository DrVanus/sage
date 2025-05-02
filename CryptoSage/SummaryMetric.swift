//
//  SummaryMetric.swift
//  CryptoSage
//
//  Created by DM on 5/31/25.
//


import Foundation

struct SummaryMetric: Identifiable {
    let id = UUID()
    let iconName: String
    let valueText: String
    let title: String

    init(iconName: String, valueText: String, title: String) {
        self.iconName = iconName
        self.valueText = valueText
        self.title = title
    }
}
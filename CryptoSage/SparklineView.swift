//
//  SparklineView.swift
//  CryptoSage
//
//  Created by DM on 5/25/25.
//


import SwiftUI
import Charts

/// A reusable sparkline chart view for rendering an array of price points.
struct SparklineView: View {
    /// The series of prices to plot
    let data: [Double]
    /// Whether the line should be colored green (positive) or red (negative)
    let isPositive: Bool

    var body: some View {
        Chart {
            ForEach(data.indices, id: \.self) { index in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Price", data[index])
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(isPositive ? .green : .red)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (data.min() ?? 0)...(data.max() ?? 1))
        .frame(height: 30)
    }
}

#if DEBUG
struct SparklineView_Previews: PreviewProvider {
    static var previews: some View {
        SparklineView(data: [1, 3, 2, 5, 4, 6, 5], isPositive: true)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
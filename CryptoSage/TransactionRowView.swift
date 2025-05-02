//
//  TransactionsRow.swift
//  CSAI1
//
//  Created by DM on 3/26/25.
//


import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack {
            CoinImageView(symbol: transaction.coinSymbol, url: nil, size: 24)
            
            VStack(alignment: .leading) {
                Text("\(transaction.isBuy ? "Buy" : "Sell") \(transaction.coinSymbol)")
                    .font(.headline)
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(transaction.quantity, specifier: "%.2f") @ $\(transaction.pricePerUnit, specifier: "%.2f")")
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

struct TransactionRowView_Previews: PreviewProvider {
    static var previews: some View {
        TransactionRowView(transaction: Transaction(coinSymbol: "BTC", quantity: 0.5, pricePerUnit: 20000, date: Date(), isBuy: true))
            .previewLayout(.sizeThatFits)
    }
}

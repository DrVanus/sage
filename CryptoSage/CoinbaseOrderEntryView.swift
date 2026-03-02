//
//  CoinbaseOrderEntryView.swift
//  CryptoSage
//
//  Order entry UI for Coinbase trading
//

import SwiftUI

struct CoinbaseOrderEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tradingVM = CoinbaseTradingViewModel.shared

    let productId: String
    let currentPrice: Double
    @State var side: TradeSide

    @State private var orderType: OrderType = .market
    @State private var size: String = ""
    @State private var limitPrice: String = ""
    @State private var stopPrice: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingSuccessAlert = false

    enum OrderType: String, CaseIterable, Identifiable {
        case market = "Market"
        case limit = "Limit"

        var id: String { rawValue }
    }

    private var estimatedTotal: Double? {
        guard let sizeValue = Double(size) else { return nil }

        switch orderType {
        case .market:
            return sizeValue * currentPrice
        case .limit:
            guard let limitValue = Double(limitPrice) else { return nil }
            return sizeValue * limitValue
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header Card
                        headerCard

                        // Order Type Selector
                        orderTypeSelector

                        // Size Input
                        sizeInputCard

                        // Price Inputs (conditionally shown)
                        if orderType == .limit {
                            limitPriceCard
                        }

                        // Estimated Total
                        if let total = estimatedTotal {
                            estimatedTotalCard(total: total)
                        }

                        // Paper Trading Toggle
                        paperTradingCard

                        // Submit Button
                        submitButton

                        // Error Message
                        if let error = errorMessage {
                            errorCard(message: error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("\(side == .buy ? "Buy" : "Sell") \(productId)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
            .alert("Order Placed", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(tradingVM.isPaperTrading ? "Paper trade executed successfully" : "Live order placed successfully")
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            Text(productId)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)

            Text(formatPrice(currentPrice))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(side == .buy ? DS.Adaptive.primaryGreen : DS.Adaptive.primaryRed)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Order Type Selector

    private var orderTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Order Type")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)

            Picker("Type", selection: $orderType) {
                ForEach(OrderType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Size Input Card

    private var sizeInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amount")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)

            HStack {
                TextField("0.00", text: $size)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text(productId.replacingOccurrences(of: "-USD", with: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding()
            .background(DS.Adaptive.background)
            .cornerRadius(10)
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Limit Price Card

    private var limitPriceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Limit Price")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)

            HStack {
                Text("$")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)

                TextField("0.00", text: $limitPrice)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text("USD")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding()
            .background(DS.Adaptive.background)
            .cornerRadius(10)

            // Suggested prices
            HStack(spacing: 8) {
                ForEach([-5.0, -2.0, 0.0, 2.0, 5.0], id: \.self) { percent in
                    Button(action: {
                        let adjustedPrice = currentPrice * (1 + percent / 100)
                        limitPrice = formatPriceString(adjustedPrice)
                    }) {
                        Text("\(percent > 0 ? "+" : "")\(Int(percent))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DS.Adaptive.background)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Estimated Total Card

    private func estimatedTotalCard(total: Double) -> some View {
        HStack {
            Text("Estimated Total")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)

            Spacer()

            Text(formatPrice(total))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Paper Trading Card

    private var paperTradingCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paper Trading Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text("Practice with virtual money")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $tradingVM.isPaperTrading)
                .labelsHidden()
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button(action: submitOrder) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: side == .buy ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 20))

                    Text("Place \(side == .buy ? "Buy" : "Sell") Order")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(side == .buy ? DS.Adaptive.primaryGreen : DS.Adaptive.primaryRed)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(isSubmitting || size.isEmpty || (orderType == .limit && limitPrice.isEmpty))
        .opacity((isSubmitting || size.isEmpty || (orderType == .limit && limitPrice.isEmpty)) ? 0.5 : 1.0)
    }

    // MARK: - Error Card

    private func errorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.red)

            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func submitOrder() {
        guard let sizeValue = Double(size) else {
            errorMessage = "Invalid size"
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                switch orderType {
                case .market:
                    try await tradingVM.placeMarketOrder(
                        productId: productId,
                        side: side,
                        size: sizeValue
                    )

                case .limit:
                    guard let limitValue = Double(limitPrice) else {
                        errorMessage = "Invalid limit price"
                        isSubmitting = false
                        return
                    }
                    try await tradingVM.placeLimitOrder(
                        productId: productId,
                        side: side,
                        size: sizeValue,
                        price: limitValue
                    )
                }

                showingSuccessAlert = true
            } catch {
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Double) -> String {
        if price < 0.01 {
            return String(format: "$%.8f", price)
        } else if price < 1 {
            return String(format: "$%.6f", price)
        } else if price < 100 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.2f", price)
        }
    }

    private func formatPriceString(_ price: Double) -> String {
        if price < 0.01 {
            return String(format: "%.8f", price)
        } else if price < 1 {
            return String(format: "%.6f", price)
        } else if price < 100 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.2f", price)
        }
    }
}

// MARK: - Design System Extensions (if not already defined)

extension DS.Adaptive {
    static var primaryGreen: Color {
        Color(red: 50/255, green: 215/255, blue: 75/255)
    }

    static var primaryRed: Color {
        Color(red: 255/255, green: 59/255, blue: 48/255)
    }
}

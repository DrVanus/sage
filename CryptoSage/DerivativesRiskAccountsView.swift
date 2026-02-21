//
//  DerivativesRiskAccountsView.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI

struct DerivativesRiskAccountsView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    let isUSUser: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Exchange & Market Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXCHANGE & MARKET")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    VStack(spacing: 1) {
                        Picker("Exchange", selection: $viewModel.selectedExchange) {
                            ForEach(viewModel.availableDerivativesExchanges, id: \.self) { ex in
                                let disabled = isUSUser && (ex.name == "Coinbase Perps" || ex.name == "Binance Futures")
                                HStack {
                                    Text(ex.name)
                                    if disabled {
                                        Spacer()
                                        Text("Not available")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                                .tag(Optional(ex))
                                .disabled(disabled)
                            }
                        }
                        Picker("Market", selection: $viewModel.selectedMarket) {
                            ForEach(viewModel.marketsForSelectedExchange, id: \.self) { m in
                                Text(m.title).tag(Optional(m))
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.2)))
                }

                // Risk Management Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("RISK MANAGEMENT")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    VStack(spacing: 1) {
                        Stepper("Leverage: \(viewModel.leverage)x",
                                value: $viewModel.leverage,
                                in: 1...viewModel.maxLeverage)
                        Toggle("Isolated Margin", isOn: $viewModel.isIsolated)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.2)))
                }

                // Start/Stop Button
                Button(action: { viewModel.toggleDerivativesBot() }) {
                    Text(viewModel.isRunning ? "Stop Bot" : "Start Bot")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isRunning ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct DerivativesRiskAccountsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DerivativesRiskAccountsView(viewModel: DerivativesBotViewModel(),
                                        isUSUser: false)
        }
    }
}

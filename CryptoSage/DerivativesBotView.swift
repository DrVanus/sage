//
//  DerivativesBotView.swift
//  CryptoSage
//

import SwiftUI

struct DerivativesBotView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    let isUSUser: Bool

    var body: some View {
        VStack(spacing: 16) {
            // MARK: Tab Picker
            Picker("Select Tab", selection: $viewModel.selectedTab) {
                ForEach(DerivativesBotViewModel.BotTab.allCases) { tab in
                    Text(tab.title)
                        .foregroundColor(Theme.buttonTextColor)
                        .tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .foregroundColor(Theme.buttonTextColor)

            // MARK: Tab Content
            Group {
                switch viewModel.selectedTab {
                case .chat:
                    DerivativesChatView(viewModel: viewModel)

                case .strategy:
                    VStack {
                        Text("Strategy UI coming soon")
                            .font(.headline)
                            .foregroundColor(Theme.buttonTextColor)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    

                case .risk:
                    // Compute filtered exchanges for US users
                    let filteredExchanges: [Exchange] = isUSUser
                        ? viewModel.availableDerivativesExchanges.filter {
                            $0.name != "Coinbase Perps" && $0.name != "Binance Futures"
                          }
                        : viewModel.availableDerivativesExchanges

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Exchange & Market Card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("EXCHANGE & MARKET")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)

                                // Exchange menu
                                Menu {
                                    ForEach(filteredExchanges, id: \.self) { ex in
                                        Button(ex.name) {
                                            viewModel.selectedExchange = ex
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(viewModel.selectedExchange?.name ?? "Select Exchange")
                                            .font(.headline)
                                            .foregroundColor(Theme.accentBlue)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(Theme.accentBlue)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.cardGray)
                                    )
                                    .padding(.horizontal)
                                }

                                if isUSUser &&
                                   viewModel.availableDerivativesExchanges.contains(where: {
                                       $0.name == "Coinbase Perps" || $0.name == "Binance Futures"
                                   }) {
                                    Text("Perpetual futures trading is not available in your region.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                }

                                // Market menu
                                Menu {
                                    ForEach(viewModel.marketsForSelectedExchange, id: \.self) { m in
                                        Button(m.title) {
                                            viewModel.selectedMarket = m
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(viewModel.selectedMarket?.title ?? "Select Market")
                                            .font(.headline)
                                            .foregroundColor(Theme.accentBlue)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(Theme.accentBlue)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.cardGray)
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top, 16)

                            // Risk Management Card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RISK MANAGEMENT")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)

                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Leverage: \(viewModel.leverage)x")
                                            .foregroundColor(Theme.buttonTextColor)
                                        Spacer()
                                        Button {
                                            viewModel.leverage = max(1, viewModel.leverage - 1)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(Theme.accentBlue)
                                        }
                                        Button {
                                            viewModel.leverage = min(viewModel.maxLeverage, viewModel.leverage + 1)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(Theme.accentBlue)
                                        }
                                    }

                                    Toggle("Isolated Margin", isOn: $viewModel.isIsolated)
                                        .toggleStyle(SwitchToggleStyle(tint: Theme.toggleOnColor))
                                        .foregroundColor(Theme.buttonTextColor)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.cardGray)
                                )
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .animation(.default, value: viewModel.selectedTab)
            

            Spacer()

            // MARK: Start Bot Button
            Button {
                guard let ex = viewModel.selectedExchange,
                      let mk = viewModel.selectedMarket else { return }
                let config = DerivativesBotConfig(
                    exchange: ex,
                    market: mk,
                    leverage: viewModel.leverage,
                    isIsolated: viewModel.isIsolated
                )
                viewModel.startBot(with: config)
            } label: {
                Text(viewModel.isRunning ? "Stop Bot" : "Start Bot")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        viewModel.isRunning ? Theme.errorRed : Theme.primaryGreen
                    )
                    .foregroundColor(Theme.buttonTextColor)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Theme.backgroundBlack.edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Derivatives Bot")
        .onAppear {
            viewModel.loadChatHistory()
        }
    }
}

import SwiftUI

struct DerivativesStrategyView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Main card
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MAIN").font(.caption2).foregroundColor(.gray)
                        textFieldRow(title: "Bot Name", text: $viewModel.botName)

                        // Exchange / Market pickers as Menus
                        menuRow(title: "Exchange", label: viewModel.selectedExchange?.name ?? "Select Exchange") {
                            ForEach(viewModel.availableDerivativesExchanges, id: \.self) { ex in
                                Button(ex.name) { viewModel.selectedExchange = ex }
                            }
                        }
                        menuRow(title: "Market", label: viewModel.selectedMarket?.title ?? "Select Market") {
                            ForEach(viewModel.marketsForSelectedExchange, id: \.self) { m in
                                Button(m.title) { viewModel.selectedMarket = m }
                            }
                        }
                    }
                }

                // Strategy & Side
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STRATEGY").font(.caption2).foregroundColor(.gray)
                        segmentedRow(title: "Type", selection: $viewModel.strategyType, options: DerivativesBotViewModel.StrategyType.allCases.map { $0 }) { type in
                            Text(type.rawValue)
                        }
                        segmentedRow(title: "Side", selection: $viewModel.positionSide, options: DerivativesBotViewModel.PositionSide.allCases.map { $0 }) { side in
                            Text(side.rawValue)
                        }
                        textFieldRow(title: "Position Size (Quote)", text: $viewModel.positionSize, keyboard: .decimalPad)
                    }
                }

                // Grid-only fields
                if viewModel.strategyType == .grid {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("GRID SETTINGS").font(.caption2).foregroundColor(.gray)
                            textFieldRow(title: "Lower Price", text: $viewModel.lowerPrice, keyboard: .decimalPad)
                            textFieldRow(title: "Upper Price", text: $viewModel.upperPrice, keyboard: .decimalPad)
                            textFieldRow(title: "Grid Levels", text: $viewModel.gridLevels, keyboard: .numberPad)
                            textFieldRow(title: "Order Volume", text: $viewModel.orderVolume, keyboard: .decimalPad)
                        }
                    }
                }

                // Exit / Risk
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EXIT & RISK").font(.caption2).foregroundColor(.gray)
                        textFieldRow(title: "Take Profit (%)", text: $viewModel.takeProfitPct, keyboard: .decimalPad)
                        textFieldRow(title: "Stop Loss (%)", text: $viewModel.stopLossPct, keyboard: .decimalPad)
                        Toggle(isOn: $viewModel.trailingStop) { Text("Trailing Stop").foregroundColor(.white) }
                            .toggleStyle(SwitchToggleStyle(tint: Color.yellow))
                        textFieldRow(title: "Entry Condition", text: $viewModel.entryCondition, placeholder: "e.g. RSI < 30 then scale in")
                    }
                }

                // AI generate
                Button(action: { viewModel.generateDerivativesConfig() }) {
                    Text("AI Generate Strategy")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.black)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // Summary
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUMMARY").font(.caption2).foregroundColor(.gray)
                        Text(viewModel.strategySummary)
                            .foregroundColor(.white)
                            .font(.footnote)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.vertical, 12)
        }
        .background(Color.black)
    }

    // MARK: - Reusable UI helpers
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
            .padding(.horizontal)
    }

    private func textFieldRow(title: String, text: Binding<String>, placeholder: String? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.white)
            TextField(placeholder ?? title, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }

    private func menuRow<Content: View>(title: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.white)
            Menu {
                content()
            } label: {
                HStack {
                    Text(label).foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(.white)
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    private func segmentedRow<T: Hashable, LabelView: View>(title: String, selection: Binding<T>, options: [T], @ViewBuilder label: (T) -> LabelView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.white)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { opt in
                    label(opt).tag(opt)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
}

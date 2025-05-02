import SwiftUI

#if DEBUG
import Combine

/// A dummy PriceService for SwiftUI previews
private struct PreviewPriceService: PriceService {
    func pricePublisher(for symbols: [String], interval: TimeInterval) -> AnyPublisher<[String: Double], Never> {
        Just([:]).eraseToAnyPublisher()
    }
}
#endif

struct AddTransactionView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: PortfolioViewModel

    @State private var coinSymbol: String = ""
    @State private var quantity: String = ""
    @State private var pricePerUnit: String = ""
    @State private var isBuy: Bool = true
    @State private var date: Date = Date()

    // MARK: - Edit Mode
    private var isEditing: Bool {
        viewModel.editingTransaction != nil
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header:
                    Text("Coin Details")
                        .font(.headline)
                        .foregroundColor(.yellow)
                ) {
                    TextField("Coin Symbol (e.g. BTC)", text: $coinSymbol)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header:
                    Text("Transaction Details")
                        .font(.headline)
                        .foregroundColor(.yellow)
                ) {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Price per Unit", text: $pricePerUnit)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Toggle(isOn: $isBuy) {
                        Text(isBuy ? "Buy" : "Sell")
                    }
                    .tint(.yellow)
                    DatePicker("Transaction Date", selection: $date, displayedComponents: .date)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Button(action: addTransaction) {
                        Text(isEditing ? "Save Transaction" : "Add Transaction")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.yellow)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(InsetGroupedListStyle())
            .background(Color(.systemGroupedBackground))
            .onAppear {
                if let tx = viewModel.editingTransaction {
                    coinSymbol = tx.coinSymbol
                    quantity = String(tx.quantity)
                    pricePerUnit = String(tx.pricePerUnit)
                    isBuy = tx.isBuy
                    date = tx.date
                }
            }
            .navigationBarTitle(isEditing ? "Edit Transaction" : "Add Transaction", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .accentColor(.yellow)
        }
    }

    private func addTransaction() {
        guard let qty = Double(quantity),
              let price = Double(pricePerUnit) else { return }

        let newTx = Transaction(
            coinSymbol: coinSymbol,
            quantity: qty,
            pricePerUnit: price,
            date: date,
            isBuy: isBuy,
            isManual: true
        )

        if let oldTx = viewModel.editingTransaction {
            viewModel.updateTransaction(oldTx: oldTx, newTx: newTx)
            viewModel.editingTransaction = nil
        } else {
            viewModel.addTransaction(newTx)
        }

        presentationMode.wrappedValue.dismiss()
    }
}

struct AddTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a preview repository and VM
        let manualService = ManualPortfolioDataService(initialHoldings: [], initialTransactions: [])
        let liveService   = LivePortfolioDataService()
#if DEBUG
        let priceService  = PreviewPriceService()
#else
        let priceService  = CoinPaprikaData()
#endif
        let repo = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        let vm = PortfolioViewModel(repository: repo)
        return AddTransactionView(viewModel: vm)
    }
}

import SwiftUI

// Bot model
struct Bot: Identifiable, Codable {
    let id: Int
    let name: String
    let exchange: String
    let strategy: String
    let status: String
    let profit: Double?
}

// ViewModel for fetching bots (dummy implementation for now)
class BotManagementViewModel: ObservableObject {
    @Published var bots: [Bot] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Replace this simulated fetch with your real network request to the 3commas API.
    func fetchBots(apiKey: String, apiSecret: String) {
        isLoading = true
        errorMessage = nil
        
        // PRODUCTION FIX: Require real 3Commas API credentials.
        // Previously returned dummy bots with fake profit data.
        guard !apiKey.isEmpty, apiKey != "your_api_key_here",
              !apiSecret.isEmpty, apiSecret != "your_api_secret_here" else {
            DispatchQueue.main.async {
                self.bots = []
                self.errorMessage = "Connect your 3Commas account to manage bots."
                self.isLoading = false
            }
            return
        }
        
        // Placeholder for real 3Commas bot fetching
        // The actual bot management is handled via Link3CommasView and ThreeCommasService
        DispatchQueue.main.async {
            self.bots = []
            self.errorMessage = nil
            self.isLoading = false
        }
    }
}

// BotManagementView without its own NavigationView so that it can be pushed onto the navigation stack
struct BotManagementView: View {
    @StateObject private var viewModel = BotManagementViewModel()
    // In production these values would be securely stored after a successful pairing.
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    
    var body: some View {
        VStack {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
            if viewModel.isLoading {
                ProgressView("Loading bots...")
                    .padding()
            } else {
                List(viewModel.bots) { bot in
                    NavigationLink(destination: BotDetailView(bot: bot)) {
                        BotRow(bot: bot)
                    }
                }
            }
        }
        .navigationTitle("My 3Commas Bots")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.fetchBots(apiKey: apiKey, apiSecret: apiSecret)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            // PRODUCTION FIX: Load real credentials from secure storage
            DispatchQueue.main.async {
                apiKey = ThreeCommasConfig.apiKey
                apiSecret = ThreeCommasConfig.tradingSecret
                viewModel.fetchBots(apiKey: apiKey, apiSecret: apiSecret)
            }
        }
    }
}

// A view representing a single bot row in the list.
struct BotRow: View {
    let bot: Bot
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bot.name)
                    .font(.headline)
                Text("\(bot.exchange) • \(bot.strategy)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Text(bot.status)
                .foregroundColor(bot.status == "Active" ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

// A detailed view for a selected bot.
struct BotDetailView: View {
    let bot: Bot
    var body: some View {
        VStack(spacing: 20) {
            Text(bot.name)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Exchange: \(bot.exchange)")
            Text("Strategy: \(bot.strategy)")
            Text("Status: \(bot.status)")
            if let profit = bot.profit {
                Text(String(format: "Profit: %.2f", profit))
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Bot Details")
    }
}

// Preview provider for testing in Xcode's canvas.
struct BotManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BotManagementView()
        }
        .preferredColorScheme(.light)
    }
}

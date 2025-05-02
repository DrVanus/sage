import Foundation
import Combine

// MARK: - Data Models

struct FearGreedData: Decodable {
    let value: String
    let value_classification: String
    let timestamp: String
    let time_until_update: String?  // only present on the latest data point

    // Friendly computed property for your UI
    var valueClassification: String { value_classification }
}

struct FearGreedResponse: Decodable {
    let name: String
    let data: [FearGreedData]
    let metadata: FearGreedMetadata
}

struct FearGreedMetadata: Decodable {
    let error: String?
}

// MARK: - ViewModel

final class ExtendedFearGreedViewModel: ObservableObject {
    @Published var isLoading: Bool      = false
    @Published var errorMessage: String?
    @Published var data: [FearGreedData] = []

    // Conveniences for the view
    var currentValue: Int? {
        guard let raw = data.first?.value else { return nil }
        return Int(raw)
    }
    var yesterdayData: FearGreedData? {
        data.count > 1 ? data[1] : nil
    }
    var lastWeekData: FearGreedData? {
        data.count > 6 ? data[6] : nil
    }
    var lastMonthData: FearGreedData? {
        data.count > 29 ? data[29] : nil
    }

    private var cancellables = Set<AnyCancellable>()

    func fetchData() {
        guard let url = URL(string: "https://api.alternative.me/fng/?limit=30") else {
            self.errorMessage = "Invalid URL."
            return
        }

        isLoading    = true
        errorMessage = nil

        URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { output -> Data in
                let raw = output.data
                if let jsonString = String(data: raw, encoding: .utf8) {
                    print("Fear & Greed raw JSON:", jsonString)
                }
                return raw
            }
            .decode(type: FearGreedResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoading = false
                if case let .failure(err) = completion {
                    self.errorMessage = err.localizedDescription
                }
            } receiveValue: { response in
                self.data = response.data
            }
            .store(in: &cancellables)
    }
}

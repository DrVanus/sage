import Foundation
import SwiftUI

// ————————————
// 1) MarketSegment enum
// ————————————
enum MarketSegment: String, CaseIterable, Identifiable {
    case all       = "All"
    case trending  = "Trending"
    case gainers   = "Gainers"
    case losers    = "Losers"
    case favorites = "Favorites"
    var id: String { rawValue }
}

// ————————————
// 2) SortField enum
// ————————————
enum SortField: String, CaseIterable, Identifiable {
    case coin        = "Coin"
    case price       = "Price"
    case dailyChange = "24h"
    case volume      = "Volume"
    case marketCap   = "Market Cap"
    var id: String { rawValue }
}

// ————————————
// 3) SortDirection enum
// ————————————
enum SortDirection: String, CaseIterable, Identifiable {
    case asc  = "Ascending"
    case desc = "Descending"
    var id: String { rawValue }
}

// ————————————
// 4) MarketSegmentViewModel
// ————————————
final class MarketSegmentViewModel: ObservableObject {
    @Published var selectedSegment: MarketSegment = .all
    @Published var sortField: SortField = .marketCap
    @Published var sortDirection: SortDirection = .desc

    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
    }

    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection = (sortDirection == .asc ? .desc : .asc)
        } else {
            sortField = field
            sortDirection = .desc
        }
    }
}

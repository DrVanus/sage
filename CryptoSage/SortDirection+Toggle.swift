import Foundation

// Provides a convenient toggle helper for ascending/descending sort direction.
// Safe to include even if SortDirection lives in another file.
public extension SortDirection {
    mutating func toggle() {
        switch self {
        case .ascending: self = .descending
        case .descending: self = .ascending
        }
    }

    var toggled: SortDirection {
        switch self {
        case .ascending: return .descending
        case .descending: return .ascending
        }
    }
}

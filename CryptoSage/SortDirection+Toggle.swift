import Foundation

// Provides a convenient toggle helper for asc/desc sort direction.
// Safe to include even if SortDirection lives in another file.
extension SortDirection {
    mutating func toggle() {
        self = (self == .asc) ? .desc : .asc
    }

    var toggled: SortDirection {
        self == .asc ? .desc : .asc
    }
}

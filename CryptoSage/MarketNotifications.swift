import Foundation

public extension Notification.Name {
    /// Post with object: String (base symbol, e.g., "BTC") to request showing the Markets sheet for that symbol.
    static let showPairsForSymbol = Notification.Name("ShowPairsForSymbol")
}

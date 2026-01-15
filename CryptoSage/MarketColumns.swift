import Foundation

/// A shared struct containing static constants defining the widths of columns in the market list.
/// These widths are chosen to provide perfect alignment across all iPhone sizes.
struct MarketListColumnWidths {
    /// Width of the column displaying the market rank number.
    static let rankColumnWidth: CGFloat = 40.0
    
    /// Width of the column displaying the market icon.
    static let iconColumnWidth: CGFloat = 30.0
    
    /// Width of the column displaying the market name.
    static let nameColumnWidth: CGFloat = 120.0
    
    /// Width of the column displaying the market price.
    static let priceColumnWidth: CGFloat = 100.0
    
    /// Width of the column displaying the market price change percentage.
    static let changeColumnWidth: CGFloat = 80.0
    
    /// Width of the column displaying the market volume.
    static let volumeColumnWidth: CGFloat = 100.0
}

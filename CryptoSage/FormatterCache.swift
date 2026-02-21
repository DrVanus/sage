import Foundation

enum FormatterCache {
    static let currency0: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = CurrencyManager.currencyCode
        f.maximumFractionDigits = 0
        return f
    }()

    static let currency2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = CurrencyManager.currencyCode
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static let decimal2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static let decimalUpTo8: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 8
        return f
    }()
}

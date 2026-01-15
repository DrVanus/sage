import Foundation

enum StaticNewsSeed {
    static func sampleArticles() -> [CryptoNewsArticle] {
        let now = Date()
        let items: [(String, String, String, String?)] = [
            (
                "Bitcoin holds steady as market eyes ETF flows",
                "Coindesk",
                "https://www.coindesk.com/markets/",
                "https://static.coindesk.com/wp-content/uploads/2023/01/bitcoin-2-1200x628.jpg"
            ),
            (
                "Ethereum developers outline next upgrade milestones",
                "CoinTelegraph",
                "https://cointelegraph.com/",
                "https://images.ctfassets.net/9sy2a0egs6zh/eth_upgrade/hero.jpg"
            ),
            (
                "Solana network activity climbs amid DeFi resurgence",
                "The Block",
                "https://www.theblock.co/",
                nil
            ),
            (
                "DeFi TVL rises as risk appetite returns",
                "Decrypt",
                "https://decrypt.co/",
                nil
            ),
            (
                "Regulatory clarity could boost institutional crypto adoption",
                "Bitcoin Magazine",
                "https://bitcoinmagazine.com/",
                nil
            )
        ]
        return items.enumerated().compactMap { idx, tup in
            guard let url = URL(string: tup.2) else { return nil }
            let img = tup.3.flatMap { URL(string: $0) }
            let date = now.addingTimeInterval(TimeInterval(-idx * 900))
            return CryptoNewsArticle(title: tup.0, description: nil, url: url, urlToImage: img, sourceName: tup.1, publishedAt: date)
        }
    }
}

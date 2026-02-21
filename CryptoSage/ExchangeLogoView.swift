//
//  ExchangeLogoView.swift
//  CryptoSage
//
//  Async exchange/wallet logo loader with caching.
//

import SwiftUI
import CryptoKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Exchange Logo URL Mapping

/// Maps exchange/wallet names to their official logo URLs
struct ExchangeLogos {
    /// Known exchange logo URLs - using reliable CDN PNG sources
    /// Primary: CoinMarketCap S3 CDN (64x64 PNGs, very reliable)
    /// For chain wallets: CoinMarketCap coin images
    static let exchangeURLs: [String: String] = [
        // Major Exchanges - CoinMarketCap Exchange Images
        "binance": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/270.png",
        "binance us": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/270.png",
        "coinbase": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/89.png",
        "coinbase pro": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/89.png",
        "kraken": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/24.png",
        "kucoin": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/311.png",
        "bitstamp": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/70.png",
        "poloniex": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/27.png",
        "okx": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/294.png",
        "huobi": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/102.png",
        "htx": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/102.png",
        "gemini": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/151.png",
        "gate.io": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/302.png",
        "bitmex": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/127.png",
        "bybit": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/521.png",
        "deribit": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/468.png",
        "binance futures": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/270.png",
        "mexc": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/544.png",
        "crypto.com": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/343.png",
        "bitget": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/513.png",
        "bitfinex": "https://s2.coinmarketcap.com/static/img/exchanges/64x64/37.png",
        
        // Blockchain Chain Wallets - CoinMarketCap Coin Images
        "ethereum wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png",
        "bitcoin wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png",
        "solana wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/5426.png",
        "polygon wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/3890.png",
        "arbitrum wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/11841.png",
        "base wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/27716.png",
        "avalanche wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/5805.png",
        "bnb chain wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/1839.png",
        
        // Software Wallets - PNG sources
        "metamask": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/MetaMask_Fox.svg/512px-MetaMask_Fox.svg.png",
        "trust wallet": "https://s2.coinmarketcap.com/static/img/coins/64x64/11085.png",
        "rainbow": "https://rainbow.me/favicon.ico",
        "exodus": "https://s2.coinmarketcap.com/static/img/coins/64x64/7580.png",
        "ledger live": "https://www.ledger.com/wp-content/uploads/2021/11/Ledger_favicon.png",
        "trezor": "https://trezor.io/static/images/favicon.ico"
    ]
    
    /// Alternative CDN URLs as fallbacks (CoinGecko market images)
    static let fallbackURLs: [String: [String]] = [
        // Exchanges - CoinGecko market images as fallback
        "binance": [
            "https://assets.coingecko.com/markets/images/52/large/binance.jpg",
            "https://cryptologos.cc/logos/binance-coin-bnb-logo.png"
        ],
        "binance us": [
            "https://assets.coingecko.com/markets/images/52/large/binance.jpg"
        ],
        "coinbase": [
            "https://assets.coingecko.com/markets/images/23/large/Coinbase_Coin_Primary.jpg"
        ],
        "kraken": [
            "https://assets.coingecko.com/markets/images/29/large/kraken.jpg"
        ],
        "kucoin": [
            "https://assets.coingecko.com/markets/images/61/large/kucoin.jpg"
        ],
        "okx": [
            "https://assets.coingecko.com/markets/images/96/large/WeChat_Image_20220117220452.jpg"
        ],
        "huobi": [
            "https://assets.coingecko.com/markets/images/25/large/huobi.jpg"
        ],
        "htx": [
            "https://assets.coingecko.com/markets/images/25/large/huobi.jpg"
        ],
        "bybit": [
            "https://assets.coingecko.com/markets/images/698/large/bybit_spot.jpg"
        ],
        "gate.io": [
            "https://assets.coingecko.com/markets/images/60/large/gate_io.jpg"
        ],
        "gemini": [
            "https://assets.coingecko.com/markets/images/50/large/gemini.jpg"
        ],
        "bitstamp": [
            "https://assets.coingecko.com/markets/images/9/large/bitstamp.jpg"
        ],
        "bitfinex": [
            "https://assets.coingecko.com/markets/images/4/large/BItfinex.jpg"
        ],
        "mexc": [
            "https://assets.coingecko.com/markets/images/409/large/MEXC_logo_square.jpg"
        ],
        "bitget": [
            "https://assets.coingecko.com/markets/images/540/large/Bitget.jpg"
        ],
        "crypto.com": [
            "https://assets.coingecko.com/markets/images/589/large/crypto_com.jpg"
        ],
        
        // Chain Wallets - CoinGecko coin images as fallback
        "ethereum wallet": [
            "https://assets.coingecko.com/coins/images/279/large/ethereum.png"
        ],
        "bitcoin wallet": [
            "https://assets.coingecko.com/coins/images/1/large/bitcoin.png"
        ],
        "solana wallet": [
            "https://assets.coingecko.com/coins/images/4128/large/solana.png"
        ],
        "polygon wallet": [
            "https://assets.coingecko.com/coins/images/4713/large/polygon.png"
        ],
        "arbitrum wallet": [
            "https://assets.coingecko.com/coins/images/16547/large/photo_2023-03-29_21.47.00.jpeg"
        ],
        "avalanche wallet": [
            "https://assets.coingecko.com/coins/images/12559/large/Avalanche_Circle_RedWhite_Trans.png"
        ],
        "bnb chain wallet": [
            "https://assets.coingecko.com/coins/images/825/large/bnb-icon2_2x.png"
        ],
        
        // Software Wallets
        "metamask": [
            "https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/MetaMask_Fox.svg/512px-MetaMask_Fox.svg.png"
        ],
        "trust wallet": [
            "https://assets.coingecko.com/coins/images/11085/large/Trust.jpg"
        ]
    ]
    
    /// Normalize name for dictionary lookup (handles variations)
    private static func normalizedKey(_ name: String) -> String {
        return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get the primary URL for an exchange/wallet
    static func url(for name: String) -> URL? {
        let key = normalizedKey(name)
        if let urlString = exchangeURLs[key] {
            return URL(string: urlString)
        }
        // Try without " wallet" suffix for chain wallet lookups
        let stripped = key.replacingOccurrences(of: " wallet", with: "")
        if stripped != key, let urlString = exchangeURLs[stripped] {
            return URL(string: urlString)
        }
        return nil
    }
    
    /// Get all fallback URLs for an exchange/wallet
    static func fallbacks(for name: String) -> [URL] {
        let key = normalizedKey(name)
        if let urls = fallbackURLs[key] {
            return urls.compactMap { URL(string: $0) }
        }
        // Try without " wallet" suffix
        let stripped = key.replacingOccurrences(of: " wallet", with: "")
        if stripped != key, let urls = fallbackURLs[stripped] {
            return urls.compactMap { URL(string: $0) }
        }
        return []
    }
    
    /// SF Symbol fallback for each exchange type
    static func sfSymbol(for name: String) -> String {
        let key = name.lowercased()
        // Chain wallets get their chain-specific icon
        let chainWallets = [
            "ethereum wallet", "bitcoin wallet", "solana wallet",
            "polygon wallet", "arbitrum wallet", "base wallet",
            "avalanche wallet", "bnb chain wallet"
        ]
        if chainWallets.contains(key) || key.hasSuffix(" wallet") {
            return "circle.hexagongrid.fill"
        }
        // Software wallets get wallet icon
        let softwareWallets = ["metamask", "trust wallet", "rainbow", "exodus", "ledger live", "trezor"]
        if softwareWallets.contains(key) {
            return "wallet.pass.fill"
        }
        // Exchanges get building icon
        return "building.columns.fill"
    }
    
    /// Brand color for each exchange (for SF Symbol tint)
    static func brandColor(for name: String) -> Color {
        let key = name.lowercased()
        switch key {
        // Exchanges
        case "binance", "binance us", "binance futures":
            return Color(red: 0.95, green: 0.77, blue: 0.06) // #F3BA2F
        case "coinbase", "coinbase pro":
            return Color(red: 0.02, green: 0.33, blue: 0.98) // #0552F7
        case "kraken":
            return Color(red: 0.38, green: 0.30, blue: 0.87) // #614CDE
        case "kucoin":
            return Color(red: 0.15, green: 0.78, blue: 0.62) // #26C79E
        case "okx":
            return Color.white
        case "huobi", "htx":
            return Color(red: 0.09, green: 0.47, blue: 0.95) // #1878F3
        case "bybit":
            return Color(red: 0.96, green: 0.65, blue: 0.14) // #F5A623
        case "gemini":
            return Color(red: 0.0, green: 0.87, blue: 0.87) // #00DCDC
        case "gate.io":
            return Color(red: 0.11, green: 0.75, blue: 0.40) // #1CBF66
        case "bitstamp":
            return Color(red: 0.20, green: 0.65, blue: 0.20) // Green
        case "bitfinex":
            return Color(red: 0.09, green: 0.74, blue: 0.51) // #17BF82
        case "mexc":
            return Color(red: 0.09, green: 0.47, blue: 0.95) // Blue
        case "crypto.com":
            return Color(red: 0.07, green: 0.20, blue: 0.47) // #103377 dark blue
        case "bitget":
            return Color(red: 0.0, green: 0.82, blue: 0.70) // #00D1B2 teal
        case "bitmex":
            return Color(red: 0.95, green: 0.17, blue: 0.17) // Red
        case "deribit":
            return Color(red: 0.15, green: 0.78, blue: 0.40) // Green
        // Chain Wallets
        case "ethereum wallet":
            return Color(red: 0.38, green: 0.49, blue: 0.92) // #627EEA
        case "bitcoin wallet":
            return Color(red: 0.97, green: 0.58, blue: 0.10) // #F7931A
        case "solana wallet":
            return Color(red: 0.60, green: 0.27, blue: 1.0)  // #9945FF
        case "polygon wallet":
            return Color(red: 0.51, green: 0.28, blue: 0.90) // #8247E5
        case "arbitrum wallet":
            return Color(red: 0.16, green: 0.63, blue: 0.94) // #28A0F0
        case "base wallet":
            return Color(red: 0.0, green: 0.32, blue: 1.0)   // #0052FF
        case "avalanche wallet":
            return Color(red: 0.91, green: 0.25, blue: 0.26) // #E84142
        case "bnb chain wallet":
            return Color(red: 0.94, green: 0.72, blue: 0.04) // #F0B90B
        // Software Wallets
        case "metamask":
            return Color(red: 0.96, green: 0.62, blue: 0.26) // #F5A142
        case "trust wallet":
            return Color(red: 0.20, green: 0.55, blue: 0.98) // #338DFA
        case "rainbow":
            return Color(red: 0.0, green: 0.5, blue: 1.0)    // Blue
        case "exodus":
            return Color(red: 0.38, green: 0.27, blue: 0.95) // Purple
        case "ledger live":
            return Color.white
        case "trezor":
            return Color(red: 0.0, green: 0.65, blue: 0.36)  // Green
        default:
            return Color.white.opacity(0.8)
        }
    }
}

// MARK: - Exchange Logo View

struct ExchangeLogoView: View {
    let name: String
    let size: CGFloat
    
    @State private var loadedImage: UIImage? = nil
    @State private var currentURLIndex: Int = 0
    @State private var allURLs: [URL] = []
    @State private var hasTriedAll: Bool = false
    
    // MARK: - Caching
    
    // PERFORMANCE FIX: Added cache size limits to prevent unbounded memory growth
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 10  // MEMORY FIX v3: Reduced from 25 to 10
        cache.totalCostLimit = 1 * 1024 * 1024  // MEMORY FIX v3: Reduced from 3MB to 1MB
        return cache
    }()
    private static let diskCacheFolderName = "ExchangeLogoCache"
    private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()
    
    private static func cacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(diskCacheFolderName, isDirectory: true)
    }
    
    private static func ensureDiskCacheDirectory() {
        if let dir = cacheDirectoryURL() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    private static func hashed(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func cacheFileURL(for key: String) -> URL? {
        ensureDiskCacheDirectory()
        guard let dir = cacheDirectoryURL() else { return nil }
        let name = hashed(key) + ".png"
        return dir.appendingPathComponent(name)
    }
    
    private static func loadFromDiskCache(key: String) -> UIImage? {
        guard let fileURL = cacheFileURL(for: key),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    private static func saveToDiskCache(_ image: UIImage, key: String) {
        guard let fileURL = cacheFileURL(for: key),
              let data = image.pngData() else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
    
    /// Fast memory-only cache check (safe for View.body — no disk I/O)
    private static func getMemoryCachedImage(for name: String) -> UIImage? {
        let key = name.lowercased() as NSString
        return memoryCache.object(forKey: key)
    }
    
    /// Full cache check including disk (use only in async/.task contexts)
    private static func getCachedImage(for name: String) -> UIImage? {
        let key = name.lowercased() as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        if let diskImage = loadFromDiskCache(key: name.lowercased()) {
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }
        return nil
    }
    
    private static func cacheImage(_ image: UIImage, for name: String) {
        let key = name.lowercased() as NSString
        memoryCache.setObject(image, forKey: key)
        saveToDiskCache(image, key: name.lowercased())
    }
    
    // MARK: - URL Building
    
    private func buildURLList() -> [URL] {
        var urls: [URL] = []
        if let primary = ExchangeLogos.url(for: name) {
            urls.append(primary)
        }
        urls.append(contentsOf: ExchangeLogos.fallbacks(for: name))
        return urls
    }
    
    // MARK: - Loading
    
    private func loadImage() async {
        // Check cache first
        if let cached = Self.getCachedImage(for: name) {
            await MainActor.run {
                self.loadedImage = cached
            }
            return
        }
        
        // Build URL list
        let urls = buildURLList()
        await MainActor.run {
            self.allURLs = urls
        }
        
        // Try each URL
        for (index, url) in urls.enumerated() {
            await MainActor.run {
                self.currentURLIndex = index
            }
            
            if let image = await downloadImage(from: url) {
                Self.cacheImage(image, for: name)
                await MainActor.run {
                    self.loadedImage = image
                }
                return
            }
        }
        
        // All URLs failed
        await MainActor.run {
            self.hasTriedAll = true
        }
    }
    
    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await Self.imageSession.data(for: request)
            
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count > 100 else {
                return nil
            }
            
            // Handle SVG - convert to rasterized image
            if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("svg") {
                // For SVG, we'll use fallback since iOS doesn't natively render SVG
                return nil
            }
            
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        // PERFORMANCE FIX: Memory-only cache check in body (no disk I/O on main thread).
        // Disk cache is checked asynchronously in the .task modifier.
        let cachedImage = Self.getMemoryCachedImage(for: name)
        let brandColor = ExchangeLogos.brandColor(for: name)
        
        ZStack {
            // Background circle - brand tinted
            Circle()
                .fill(brandColor.opacity(loadedImage != nil || cachedImage != nil ? 0.05 : 0.15))
            
            if let image = cachedImage ?? loadedImage {
                // Show loaded image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.15)
            } else if hasTriedAll {
                // Show SF Symbol fallback with brand color
                Image(systemName: ExchangeLogos.sfSymbol(for: name))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(brandColor)
                    .padding(size * 0.25)
            } else {
                // Loading state - show brand-colored letter
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(brandColor.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(brandColor.opacity(0.2), lineWidth: 1)
        )
        .task {
            if cachedImage == nil && loadedImage == nil {
                await loadImage()
            }
        }
    }
}

// MARK: - Preview

struct ExchangeLogoView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ExchangeLogoView(name: "Binance", size: 48)
                ExchangeLogoView(name: "Coinbase", size: 48)
                ExchangeLogoView(name: "Kraken", size: 48)
                ExchangeLogoView(name: "KuCoin", size: 48)
            }
            HStack(spacing: 16) {
                ExchangeLogoView(name: "MetaMask", size: 48)
                ExchangeLogoView(name: "Trust Wallet", size: 48)
                ExchangeLogoView(name: "Ledger Live", size: 48)
                ExchangeLogoView(name: "Unknown", size: 48)
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}

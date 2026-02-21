//
//  StockLogoService.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Service for fetching and caching company logos for stocks and ETFs.
//  Uses multiple logo APIs with fallbacks (Brandfetch, Unavatar, Google).
//

import Foundation
import SwiftUI
import CryptoKit

#if canImport(UIKit)
import UIKit
typealias StockPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias StockPlatformImage = NSImage
#endif

// MARK: - Hardcoded Reliable Stock Logo URLs

/// Direct logo URLs for popular stocks - bypass the full API fetching pipeline.
/// UPDATED 2026-02: Using Unavatar as primary (proven working per logs) with Google Favicon
/// as backup format. Brandfetch CDN returns 403 without auth, Clearbit deprecated Dec 2025.
/// Unavatar aggregates multiple sources and has been the most reliable free option.
private let HardcodedStockLogos: [String: URL] = [
    // Big Tech
    "AAPL": URL(string: "https://unavatar.io/apple.com?fallback=false")!,
    "TSLA": URL(string: "https://unavatar.io/tesla.com?fallback=false")!,
    "NVDA": URL(string: "https://unavatar.io/nvidia.com?fallback=false")!,
    "MSFT": URL(string: "https://unavatar.io/microsoft.com?fallback=false")!,
    "GOOGL": URL(string: "https://unavatar.io/google.com?fallback=false")!,
    "GOOG": URL(string: "https://unavatar.io/google.com?fallback=false")!,
    "AMZN": URL(string: "https://unavatar.io/amazon.com?fallback=false")!,
    "META": URL(string: "https://unavatar.io/meta.com?fallback=false")!,
    "NFLX": URL(string: "https://unavatar.io/netflix.com?fallback=false")!,
    "AMD": URL(string: "https://unavatar.io/amd.com?fallback=false")!,
    "INTC": URL(string: "https://unavatar.io/intel.com?fallback=false")!,
    "CRM": URL(string: "https://unavatar.io/salesforce.com?fallback=false")!,
    "ORCL": URL(string: "https://unavatar.io/oracle.com?fallback=false")!,
    "ADBE": URL(string: "https://unavatar.io/adobe.com?fallback=false")!,
    "IBM": URL(string: "https://unavatar.io/ibm.com?fallback=false")!,
    
    // Finance
    "PYPL": URL(string: "https://unavatar.io/paypal.com?fallback=false")!,
    "V": URL(string: "https://unavatar.io/visa.com?fallback=false")!,
    "MA": URL(string: "https://unavatar.io/mastercard.com?fallback=false")!,
    "JPM": URL(string: "https://unavatar.io/jpmorganchase.com?fallback=false")!,
    "GS": URL(string: "https://unavatar.io/goldmansachs.com?fallback=false")!,
    "BAC": URL(string: "https://unavatar.io/bankofamerica.com?fallback=false")!,
    "COIN": URL(string: "https://unavatar.io/coinbase.com?fallback=false")!,
    
    // Consumer
    "DIS": URL(string: "https://unavatar.io/disney.com?fallback=false")!,
    "NKE": URL(string: "https://unavatar.io/nike.com?fallback=false")!,
    "SBUX": URL(string: "https://unavatar.io/starbucks.com?fallback=false")!,
    "MCD": URL(string: "https://unavatar.io/mcdonalds.com?fallback=false")!,
    "WMT": URL(string: "https://unavatar.io/walmart.com?fallback=false")!,
    "HD": URL(string: "https://unavatar.io/homedepot.com?fallback=false")!,
    "COST": URL(string: "https://unavatar.io/costco.com?fallback=false")!,
    "TGT": URL(string: "https://unavatar.io/target.com?fallback=false")!,
    "KO": URL(string: "https://unavatar.io/coca-cola.com?fallback=false")!,
    "PEP": URL(string: "https://unavatar.io/pepsico.com?fallback=false")!,
    "PG": URL(string: "https://unavatar.io/pg.com?fallback=false")!,
    
    // Healthcare
    "JNJ": URL(string: "https://unavatar.io/jnj.com?fallback=false")!,
    "PFE": URL(string: "https://unavatar.io/pfizer.com?fallback=false")!,
    "UNH": URL(string: "https://unavatar.io/unitedhealthgroup.com?fallback=false")!,
    "MRNA": URL(string: "https://unavatar.io/modernatx.com?fallback=false")!,
    "LLY": URL(string: "https://unavatar.io/lilly.com?fallback=false")!,
    "ABBV": URL(string: "https://unavatar.io/abbvie.com?fallback=false")!,
    
    // Automotive
    "F": URL(string: "https://unavatar.io/ford.com?fallback=false")!,
    "GM": URL(string: "https://unavatar.io/gm.com?fallback=false")!,
    "RIVN": URL(string: "https://unavatar.io/rivian.com?fallback=false")!,
    
    // Energy
    "XOM": URL(string: "https://unavatar.io/exxonmobil.com?fallback=false")!,
    "CVX": URL(string: "https://unavatar.io/chevron.com?fallback=false")!,
    
    // Industrials
    "BA": URL(string: "https://unavatar.io/boeing.com?fallback=false")!,
    "CAT": URL(string: "https://unavatar.io/caterpillar.com?fallback=false")!,
    
    // Semiconductors
    "QCOM": URL(string: "https://unavatar.io/qualcomm.com?fallback=false")!,
    "AVGO": URL(string: "https://unavatar.io/broadcom.com?fallback=false")!,
    "TSM": URL(string: "https://unavatar.io/tsmc.com?fallback=false")!,
    "MU": URL(string: "https://unavatar.io/micron.com?fallback=false")!,
    
    // Entertainment & Services
    "SPOT": URL(string: "https://unavatar.io/spotify.com?fallback=false")!,
    "UBER": URL(string: "https://unavatar.io/uber.com?fallback=false")!,
    "ABNB": URL(string: "https://unavatar.io/airbnb.com?fallback=false")!,
    
    // Crypto-related
    "MSTR": URL(string: "https://unavatar.io/microstrategy.com?fallback=false")!,
    "HOOD": URL(string: "https://unavatar.io/robinhood.com?fallback=false")!,
    
    // ETFs - use provider logos
    "VOO": URL(string: "https://unavatar.io/vanguard.com?fallback=false")!,
    "VTI": URL(string: "https://unavatar.io/vanguard.com?fallback=false")!,
    "SPY": URL(string: "https://unavatar.io/ssga.com?fallback=false")!,
    "QQQ": URL(string: "https://unavatar.io/invesco.com?fallback=false")!,
    "DIA": URL(string: "https://unavatar.io/ssga.com?fallback=false")!,
    "IWM": URL(string: "https://unavatar.io/ishares.com?fallback=false")!,
    "ARKK": URL(string: "https://unavatar.io/ark-invest.com?fallback=false")!,
]

// MARK: - Stock Logo Service

/// Service for fetching and caching stock/company logos
actor StockLogoService {
    static let shared = StockLogoService()
    
    // MARK: - Caching
    
    // PERFORMANCE FIX: Added cache size limits to prevent unbounded memory growth
    private static let memoryCache: NSCache<NSString, StockPlatformImage> = {
        let cache = NSCache<NSString, StockPlatformImage>()
        cache.countLimit = 20   // MEMORY FIX v3: Reduced from 50 to 20
        cache.totalCostLimit = 2 * 1024 * 1024  // MEMORY FIX v3: Reduced from 5MB to 2MB
        return cache
    }()
    private static let diskCacheFolderName = "StockLogoCache"
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    // MARK: - Ticker to Domain Mapping
    
    /// Maps stock tickers to company domains for logo fetching (Brandfetch CDN, Unavatar, etc.)
    /// This covers the most popular stocks, ETFs, and commonly traded securities
    private let tickerToDomain: [String: String] = [
        // Big Tech
        "AAPL": "apple.com",
        "MSFT": "microsoft.com",
        "GOOGL": "google.com",
        "GOOG": "google.com",
        "AMZN": "amazon.com",
        "META": "meta.com",
        "NVDA": "nvidia.com",
        "TSLA": "tesla.com",
        "AMD": "amd.com",
        "INTC": "intel.com",
        "CRM": "salesforce.com",
        "ORCL": "oracle.com",
        "ADBE": "adobe.com",
        "CSCO": "cisco.com",
        "IBM": "ibm.com",
        "NFLX": "netflix.com",
        "PYPL": "paypal.com",
        "SQ": "squareup.com",
        "SHOP": "shopify.com",
        "UBER": "uber.com",
        "LYFT": "lyft.com",
        "SNAP": "snap.com",
        "PINS": "pinterest.com",
        "TWTR": "twitter.com",
        "SPOT": "spotify.com",
        "ZM": "zoom.us",
        "DOCU": "docusign.com",
        "SNOW": "snowflake.com",
        "PLTR": "palantir.com",
        "ABNB": "airbnb.com",
        "COIN": "coinbase.com",
        "HOOD": "robinhood.com",
        "RBLX": "roblox.com",
        "U": "unity.com",
        "NET": "cloudflare.com",
        "DDOG": "datadoghq.com",
        "MDB": "mongodb.com",
        "CRWD": "crowdstrike.com",
        "OKTA": "okta.com",
        "ZS": "zscaler.com",
        "PANW": "paloaltonetworks.com",
        "NOW": "servicenow.com",
        "WDAY": "workday.com",
        "TEAM": "atlassian.com",
        "VEEV": "veeva.com",
        "TTD": "thetradedesk.com",
        "ROKU": "roku.com",
        
        // Finance
        "JPM": "jpmorganchase.com",
        "BAC": "bankofamerica.com",
        "WFC": "wellsfargo.com",
        "C": "citigroup.com",
        "GS": "goldmansachs.com",
        "MS": "morganstanley.com",
        "BLK": "blackrock.com",
        "SCHW": "schwab.com",
        "AXP": "americanexpress.com",
        "V": "visa.com",
        "MA": "mastercard.com",
        "BRK.A": "berkshirehathaway.com",
        "BRK.B": "berkshirehathaway.com",
        
        // Healthcare
        "JNJ": "jnj.com",
        "UNH": "unitedhealthgroup.com",
        "PFE": "pfizer.com",
        "ABBV": "abbvie.com",
        "MRK": "merck.com",
        "LLY": "lilly.com",
        "TMO": "thermofisher.com",
        "ABT": "abbott.com",
        "DHR": "danaher.com",
        "BMY": "bms.com",
        "AMGN": "amgen.com",
        "GILD": "gilead.com",
        "MRNA": "modernatx.com",
        "BIIB": "biogen.com",
        "REGN": "regeneron.com",
        "VRTX": "vrtx.com",
        "ISRG": "intuitive.com",
        "ZTS": "zoetis.com",
        "CVS": "cvshealth.com",
        "CI": "cigna.com",
        "HUM": "humana.com",
        "ANTM": "anthem.com",
        
        // Consumer
        "WMT": "walmart.com",
        "HD": "homedepot.com",
        "COST": "costco.com",
        "TGT": "target.com",
        "LOW": "lowes.com",
        "NKE": "nike.com",
        "SBUX": "starbucks.com",
        "MCD": "mcdonalds.com",
        "KO": "coca-cola.com",
        "PEP": "pepsico.com",
        "PG": "pg.com",
        "CL": "colgate.com",
        "EL": "esteelauder.com",
        "DIS": "disney.com",
        "CMCSA": "comcast.com",
        "CHTR": "charter.com",
        "T": "att.com",
        "VZ": "verizon.com",
        "TMUS": "t-mobile.com",
        "LULU": "lululemon.com",
        "ROST": "rossstores.com",
        "TJX": "tjx.com",
        "ULTA": "ulta.com",
        "BKNG": "booking.com",
        "MAR": "marriott.com",
        "HLT": "hilton.com",
        "LVS": "sands.com",
        "WYNN": "wynnresorts.com",
        "MGM": "mgmresorts.com",
        
        // Industrial
        "BA": "boeing.com",
        "CAT": "caterpillar.com",
        "DE": "deere.com",
        "HON": "honeywell.com",
        "MMM": "3m.com",
        "GE": "ge.com",
        "RTX": "rtx.com",
        "LMT": "lockheedmartin.com",
        "NOC": "northropgrumman.com",
        "GD": "gd.com",
        "UPS": "ups.com",
        "FDX": "fedex.com",
        "UNP": "up.com",
        "CSX": "csx.com",
        "NSC": "nscorp.com",
        
        // Energy
        "XOM": "exxonmobil.com",
        "CVX": "chevron.com",
        "COP": "conocophillips.com",
        "OXY": "oxy.com",
        "SLB": "slb.com",
        "EOG": "eogresources.com",
        "PXD": "pxd.com",
        "MPC": "marathonpetroleum.com",
        "VLO": "valero.com",
        "PSX": "phillips66.com",
        
        // Electric Vehicles & Clean Energy
        "RIVN": "rivian.com",
        "LCID": "lucidmotors.com",
        "NIO": "nio.com",
        "XPEV": "xiaopeng.com",
        "LI": "lixiang.com",
        "ENPH": "enphase.com",
        "SEDG": "solaredge.com",
        "FSLR": "firstsolar.com",
        "RUN": "sunrun.com",
        "PLUG": "plugpower.com",
        "CHPT": "chargepoint.com",
        
        // Semiconductors
        "TSM": "tsmc.com",
        "ASML": "asml.com",
        "AVGO": "broadcom.com",
        "QCOM": "qualcomm.com",
        "TXN": "ti.com",
        "MU": "micron.com",
        "LRCX": "lamresearch.com",
        "AMAT": "appliedmaterials.com",
        "KLAC": "kla.com",
        "ADI": "analog.com",
        "MRVL": "marvell.com",
        "ON": "onsemi.com",
        "NXPI": "nxp.com",
        "ARM": "arm.com",
        
        // Gaming & Entertainment
        "EA": "ea.com",
        "ATVI": "activision.com",
        "TTWO": "take2games.com",
        "WBD": "wbd.com",
        "PARA": "paramount.com",
        "FOX": "fox.com",
        "FOXA": "fox.com",
        "LYV": "livenation.com",
        "MTCH": "match.com",
        
        // Real Estate
        "AMT": "americantower.com",
        "PLD": "prologis.com",
        "CCI": "crowncastle.com",
        "EQIX": "equinix.com",
        "DLR": "digitalrealty.com",
        "SPG": "simon.com",
        "O": "realtyincome.com",
        "WELL": "welltower.com",
        "AVB": "avalonbay.com",
        "EQR": "equityapartments.com",
        
        // ETFs - Vanguard
        "VOO": "vanguard.com",
        "VTI": "vanguard.com",
        "VTV": "vanguard.com",
        "VUG": "vanguard.com",
        "VGT": "vanguard.com",
        "VHT": "vanguard.com",
        "VNQ": "vanguard.com",
        "VWO": "vanguard.com",
        "VXUS": "vanguard.com",
        "BND": "vanguard.com",
        "BNDX": "vanguard.com",
        
        // ETFs - SPDR/State Street
        "SPY": "ssga.com",
        "DIA": "ssga.com",
        "GLD": "ssga.com",
        "XLF": "ssga.com",
        "XLK": "ssga.com",
        "XLE": "ssga.com",
        "XLV": "ssga.com",
        "XLI": "ssga.com",
        "XLY": "ssga.com",
        "XLP": "ssga.com",
        
        // ETFs - iShares/BlackRock
        "IWM": "ishares.com",
        "IWF": "ishares.com",
        "IWD": "ishares.com",
        "EEM": "ishares.com",
        "EFA": "ishares.com",
        "AGG": "ishares.com",
        "LQD": "ishares.com",
        "HYG": "ishares.com",
        "TLT": "ishares.com",
        "IYR": "ishares.com",
        "IEMG": "ishares.com",
        "ITOT": "ishares.com",
        
        // ETFs - Invesco
        "QQQ": "invesco.com",
        "QQQM": "invesco.com",
        "RSP": "invesco.com",
        
        // ETFs - ARK Invest
        "ARKK": "ark-invest.com",
        "ARKW": "ark-invest.com",
        "ARKG": "ark-invest.com",
        "ARKF": "ark-invest.com",
        "ARKQ": "ark-invest.com",
        
        // Crypto-related stocks
        "MSTR": "microstrategy.com",
        "MARA": "mara.com",
        "RIOT": "riotplatforms.com",
        "CLSK": "cleanspark.com",
        "HUT": "hut8.com",
        "BITF": "bitfarms.com",
        "BTBT": "bit-digital.com",
        
        // Chinese ADRs
        "BABA": "alibabagroup.com",
        "JD": "jd.com",
        "PDD": "pinduoduo.com",
        "BIDU": "baidu.com",
        "NTES": "netease.com",
        "TME": "tencentmusic.com",
        "BILI": "bilibili.com",
        "IQ": "iq.com",
        "TAL": "100tal.com",
        "EDU": "neworiental.org",
    ]
    
    // MARK: - Logo Source Priority
    
    /// Logo sources in order of preference (2026 working APIs)
    /// PERFORMANCE FIX v21: Removed Brandfetch from the cascade entirely.
    /// Logs show it returns 403 for EVERY ticker without auth, wasting a network round-trip
    /// per stock (76 stocks * 10s timeout = massive network congestion at startup).
    /// Unavatar is the most reliable free source (aggregates multiple providers).
    private enum LogoSource: CaseIterable {
        case unavatar       // Primary: Unavatar - aggregates multiple sources, proven reliable
        case googleFavicon  // Fallback 1: Google's high-res favicon service
        case duckduckgo     // Fallback 2: DuckDuckGo icons
        
        var displayName: String {
            switch self {
            case .unavatar: return "Unavatar"
            case .googleFavicon: return "Google"
            case .duckduckgo: return "DuckDuckGo"
            }
        }
        
        func url(for domain: String) -> URL? {
            // Encode domain for URL safety
            let encodedDomain = domain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? domain
            
            switch self {
            case .unavatar:
                // Unavatar - aggregates Clearbit, DuckDuckGo, Google, etc.
                return URL(string: "https://unavatar.io/\(encodedDomain)?fallback=false")
            case .googleFavicon:
                // Google's favicon service - reliable, supports up to 256px
                return URL(string: "https://www.google.com/s2/favicons?domain=\(encodedDomain)&sz=256")
            case .duckduckgo:
                // DuckDuckGo icons - good fallback
                return URL(string: "https://icons.duckduckgo.com/ip3/\(encodedDomain).ico")
            }
        }
    }
    
    // Track failed sources per ticker to avoid repeated failures
    private var failedSources: [String: Set<LogoSource>] = [:]
    // Coalesce simultaneous requests for the same ticker to avoid duplicate network work.
    private var inFlightFetches: [String: Task<StockPlatformImage?, Never>] = [:]
    
    /// The minimum dimension accepted for favicon-style logos.
    /// Many providers still serve 16x16/32x32 assets, so rejecting <48 causes false failures.
    private let minimumAcceptedLogoDimension: CGFloat = 16
    
    // MARK: - Public Methods
    
    /// Get the logo URL for a stock ticker (primary source - Unavatar)
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: URL for the company logo, or nil if unknown
    /// PERFORMANCE FIX v21: Switched from Brandfetch (always 403) to Unavatar (proven reliable)
    func logoURL(for ticker: String) -> URL? {
        let upperTicker = ticker.uppercased()
        guard let domain = tickerToDomain[upperTicker] else { return nil }
        return URL(string: "https://unavatar.io/\(domain)?fallback=false")
    }
    
    /// Fetch logo image for a stock ticker with multiple fallback sources
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Platform image if successful, nil otherwise
    func fetchLogo(for ticker: String) async -> StockPlatformImage? {
        let upperTicker = ticker.uppercased()
        
        // Check memory cache
        let cacheKey = upperTicker as NSString
        if let cached = Self.memoryCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Check disk cache
        if let diskImage = loadFromDisk(ticker: upperTicker) {
            Self.memoryCache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        // Coalesce in-flight requests for the same ticker.
        if let inFlight = inFlightFetches[upperTicker] {
            return await inFlight.value
        }

        let task = Task<StockPlatformImage?, Never> { [self] in
            await fetchAndCacheLogo(for: upperTicker, cacheKey: cacheKey)
        }
        inFlightFetches[upperTicker] = task
        let result = await task.value
        inFlightFetches[upperTicker] = nil
        return result
    }
    
    /// Network/logo-source fetch path after memory/disk cache checks.
    private func fetchAndCacheLogo(for upperTicker: String, cacheKey: NSString) async -> StockPlatformImage? {
        
        // PRIORITY: Try hardcoded reliable URLs first (for popular stocks)
        if let hardcodedURL = HardcodedStockLogos[upperTicker] {
            if let image = await fetchFromDirectURL(hardcodedURL, ticker: upperTicker) {
                Self.memoryCache.setObject(image, forKey: cacheKey)
                saveToDisk(image: image, ticker: upperTicker)
                #if DEBUG
                print("✅ [StockLogoService] Loaded \(upperTicker) from hardcoded URL")
                #endif
                return image
            }
        }
        
        // Get domain for this ticker
        guard let domain = tickerToDomain[upperTicker] else { return nil }
        
        // Try each logo source in order
        let sourcesToTry = LogoSource.allCases.filter { source in
            !(failedSources[upperTicker]?.contains(source) ?? false)
        }
        
        for source in sourcesToTry {
            if let image = await fetchFromSource(source, domain: domain, ticker: upperTicker) {
                // Cache successful result
                Self.memoryCache.setObject(image, forKey: cacheKey)
                saveToDisk(image: image, ticker: upperTicker)
                
                #if DEBUG
                print("✅ [StockLogoService] Loaded \(upperTicker) logo from \(source)")
                #endif
                
                return image
            } else {
                // Mark this source as failed for this ticker
                if failedSources[upperTicker] == nil {
                    failedSources[upperTicker] = []
                }
                failedSources[upperTicker]?.insert(source)
            }
        }
        
        #if DEBUG
        print("❌ [StockLogoService] All sources failed for \(upperTicker)")
        #endif
        
        return nil
    }
    
    /// Fetch logo from a specific source
    private func fetchFromSource(_ source: LogoSource, domain: String, ticker: String) async -> StockPlatformImage? {
        guard let url = source.url(for: domain) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.timeoutInterval = 10
            
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else { return nil }
            
            // Handle redirects and success codes
            guard (200..<400).contains(http.statusCode) else {
                #if DEBUG
                print("⚠️ [StockLogoService] \(source.displayName) returned \(http.statusCode) for \(ticker)")
                #endif
                return nil
            }
            
            // Basic payload guard: allow small favicons while rejecting empty responses.
            guard data.count >= 64 else { return nil }
            
            // Validate content type if provided
            if let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                // Accept image types and octet-stream (some CDNs use this)
                let isImage = ct.contains("image/") || ct.contains("application/octet-stream")
                // Reject HTML error pages
                if ct.contains("text/html") { return nil }
                guard isImage else { return nil }
            }
            
            return decodeLogoImage(from: data, minimumDimension: minimumAcceptedLogoDimension)
            
        } catch {
            #if DEBUG
            print("⚠️ [StockLogoService] \(source.displayName) failed for \(ticker): \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Fetch logo from a direct URL (for hardcoded reliable URLs)
    private func fetchFromDirectURL(_ url: URL, ticker: String) async -> StockPlatformImage? {
        do {
            var request = URLRequest(url: url)
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode),
                  data.count >= 64 else {
                return nil
            }

            return decodeLogoImage(from: data, minimumDimension: minimumAcceptedLogoDimension)
        } catch {
            #if DEBUG
            print("⚠️ [StockLogoService] Direct URL fetch failed for \(ticker): \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Decode and validate a logo image payload.
    private func decodeLogoImage(from data: Data, minimumDimension: CGFloat) -> StockPlatformImage? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        guard image.size.width >= minimumDimension && image.size.height >= minimumDimension else { return nil }
        return image
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        guard image.size.width >= minimumDimension && image.size.height >= minimumDimension else { return nil }
        return image
        #endif
    }
    
    /// Pre-fetch logos for a list of tickers
    /// - Parameter tickers: Array of stock ticker symbols
    /// PERFORMANCE FIX v21: Limited concurrency to 4 parallel fetches (was unlimited).
    /// Previously launched 76+ concurrent network requests, saturating the network and
    /// contributing to timeouts across the entire app (OrderBook, WebSocket, etc.).
    func prefetchLogos(for tickers: [String]) async {
        let normalizedTickers = Array(Set(tickers.map { $0.uppercased() }))
        guard !normalizedTickers.isEmpty else { return }

        // Skip work for tickers already cached in memory/disk.
        var pendingTickers: [String] = []
        pendingTickers.reserveCapacity(normalizedTickers.count)
        for ticker in normalizedTickers where !isLogoCached(for: ticker) {
            pendingTickers.append(ticker)
        }
        guard !pendingTickers.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for ticker in pendingTickers {
                if active >= 4 {
                    await group.next()
                    active -= 1
                }
                group.addTask {
                    _ = await self.fetchLogo(for: ticker)
                }
                active += 1
            }
        }
    }
    
    /// Check if a logo is cached (memory or disk) for a ticker
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: True if logo is cached
    func isLogoCached(for ticker: String) -> Bool {
        let upperTicker = ticker.uppercased()
        let cacheKey = upperTicker as NSString
        
        // Check memory
        if Self.memoryCache.object(forKey: cacheKey) != nil {
            return true
        }
        
        // Check disk
        if let _ = diskCacheFileURL(for: upperTicker) {
            let fm = FileManager.default
            if let url = diskCacheFileURL(for: upperTicker), fm.fileExists(atPath: url.path) {
                return true
            }
        }
        
        return false
    }
    
    /// Get cached logo synchronously (memory only)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Cached image if available in memory
    nonisolated func getCachedLogo(for ticker: String) -> StockPlatformImage? {
        let cacheKey = ticker.uppercased() as NSString
        return Self.memoryCache.object(forKey: cacheKey)
    }
    
    /// Clear all cached logos
    func clearCache() {
        Self.memoryCache.removeAllObjects()
        failedSources.removeAll()
        
        // Clear disk cache
        if let cacheDir = Self.diskCacheDirectory() {
            try? FileManager.default.removeItem(at: cacheDir)
        }
    }
    
    /// Reset failed sources tracking (allows retry of previously failed sources)
    func resetFailedSources(for ticker: String? = nil) {
        if let ticker = ticker {
            failedSources.removeValue(forKey: ticker.uppercased())
        } else {
            failedSources.removeAll()
        }
    }
    
    // MARK: - Disk Cache
    
    private static func diskCacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(diskCacheFolderName, isDirectory: true)
    }
    
    private func ensureDiskCacheDirectory() {
        guard let dir = Self.diskCacheDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    private func diskCacheFileURL(for ticker: String) -> URL? {
        ensureDiskCacheDirectory()
        guard let dir = Self.diskCacheDirectory() else { return nil }
        // Use SHA256 hash for safe filename
        let data = Data(ticker.utf8)
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(hash).png")
    }
    
    private func loadFromDisk(ticker: String) -> StockPlatformImage? {
        guard let fileURL = diskCacheFileURL(for: ticker),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
    
    private func saveToDisk(image: StockPlatformImage, ticker: String) {
        guard let fileURL = diskCacheFileURL(for: ticker) else { return }
        
        #if canImport(UIKit)
        guard let data = image.pngData() else { return }
        #elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        #endif
        
        try? data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Domain Lookup Extension

extension StockLogoService {
    /// Check if we have a domain mapping for a ticker
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: True if domain is known
    func hasDomainMapping(for ticker: String) -> Bool {
        tickerToDomain[ticker.uppercased()] != nil
    }
    
    /// Get the company domain for a ticker
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Company domain if known
    func domain(for ticker: String) -> String? {
        tickerToDomain[ticker.uppercased()]
    }
}

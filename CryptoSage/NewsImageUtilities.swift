import Foundation

// MARK: - News Image Utilities
/// Shared utility functions for news image handling - consolidates duplicate logic from multiple files.

enum NewsImageUtilities {
    
    // MARK: - Icon URL Detection
    /// Comprehensive detection of favicon/icon URLs that aren't article hero images
    static func isLikelyIconURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let lastComponent = url.lastPathComponent.lowercased()
        
        // Favicon services
        if host.contains("google.com") && path.contains("/s2/favicons") { return true }
        if host.contains("duckduckgo.com") && path.contains("/ip3") { return true }
        if host.contains("clearbit.com") && path.contains("/logo") { return true }
        if host.contains("icons8.com") || host.contains("iconscout.com") { return true }
        
        // Path-based detection - specific favicon patterns only
        if path.contains("favicon") || path.contains("apple-touch-icon") { return true }
        // Only match explicit icon directories/files, not words containing "icon"
        // e.g., "/icons/" is a logo, but "/bitcoin-icon-analysis" is likely article content
        if path.contains("/icons/") || path.contains("/icon/") { return true }
        if path.contains("site-icon") || path.contains("siteicon") { return true }
        if path.contains("touch-icon") || path.contains("touchicon") { return true }
        
        // File extensions that are always icons
        if ext == "ico" || ext == "svg" { return true }
        
        // Small size indicators in path (common favicon naming patterns)
        let smallSizePatterns = ["16x16", "32x32", "48x48", "64x64", "72x72", "96x96", "120x120", "128x128", "144x144", "152x152"]
        for pattern in smallSizePatterns {
            if path.contains(pattern) { return true }
        }
        
        // Android/iOS icon paths
        if path.contains("android-chrome") { return true }
        if path.contains("mstile-") { return true }
        if lastComponent.hasPrefix("icon-") || lastComponent.hasPrefix("icon_") { return true }
        
        // Common logo file names
        if lastComponent == "logo.png" || lastComponent == "logo.jpg" || lastComponent == "logo.webp" { return true }
        if lastComponent.hasPrefix("logo-") || lastComponent.hasPrefix("logo_") { return true }
        
        // Cryptocurrency coin logo CDNs - these are coin icons, not article images
        if host.contains("coingecko.com") && path.contains("/coins/") { return true }
        if host.contains("coinmarketcap.com") && path.contains("/coins/") { return true }
        if host.contains("coincap.io") && path.contains("/icons") { return true }
        if host.contains("cryptologos.cc") { return true }
        if host.contains("coinicons.io") { return true }
        if host.contains("cryptoicons.org") { return true }
        
        // Coin logo path patterns (e.g., /crypto/xrp.png, /coins/bitcoin-logo.png)
        if path.contains("/crypto/") && (path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".webp")) {
            // Simple coin icons have short filenames
            if lastComponent.count < 20 { return true }
        }
        
        return false
    }
    
    /// More comprehensive check including generic site logos
    static func isLikelySiteIcon(_ url: URL) -> Bool {
        if isLikelyIconURL(url) { return true }
        let path = url.path.lowercased()
        // Check for explicit logo directories only, not words containing "logo"
        // e.g., "/logos/site.png" is a logo, but "/article/bitcoin-logo-history.jpg" is content
        if path.contains("/logos/") || path.contains("/logo/") { return true }
        if path.contains("/brand/") || path.contains("/branding/") { return true }
        return false
    }
    
    // MARK: - Google Favicon
    /// Get Google's favicon service URL for a given base URL
    /// Default size is 256px for sharper thumbnails (Google supports up to 256)
    static func googleFavicon(for baseURL: URL, size: Int = 256) -> URL? {
        guard let host = baseURL.host?.lowercased(), !host.isEmpty else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=\(size)")
    }
    
    // MARK: - URL Sanitization
    /// Sanitize an image URL by upgrading to HTTPS and removing tracking parameters
    static func sanitizeImageURL(_ url: URL?) -> URL? {
        guard let url = url else { return nil }
        
        // Upgrade HTTP to HTTPS
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
        }
        
        // Handle protocol-relative URLs
        if url.absoluteString.hasPrefix("//") {
            let httpsURL = "https:" + url.absoluteString
            return URL(string: httpsURL)
        }
        
        // Remove tracking parameters
        let trackingParams: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "fbclid", "gclid", "igshid", "mc_cid", "mc_eid"
        ]
        
        if let items = components?.queryItems, !items.isEmpty {
            components?.queryItems = items.filter { !trackingParams.contains($0.name.lowercased()) }
            if components?.queryItems?.isEmpty == true {
                components?.queryItems = nil
            }
        }
        
        return components?.url ?? url
    }
    
    /// Sanitize an article URL (strips tracking params, upgrades to HTTPS)
    static func sanitizeArticleURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
        }
        
        let trackingParams: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "fbclid", "gclid", "igshid", "mc_cid", "mc_eid"
        ]
        
        if let items = components?.queryItems, !items.isEmpty {
            components?.queryItems = items.filter { !trackingParams.contains($0.name.lowercased()) }
            if components?.queryItems?.isEmpty == true {
                components?.queryItems = nil
            }
        }
        
        // Normalize host to lowercase
        if let host = components?.host {
            components?.host = host.lowercased()
        }
        
        return components?.url ?? url
    }
    
    // MARK: - Publisher Logo Mapping
    /// High-quality publisher logo URLs for professional fallbacks
    static let publisherLogos: [String: String] = [
        // Major crypto news outlets (Tier 1)
        "coindesk.com": "https://www.coindesk.com/resizer/fiFLGU_GIdTP4pDrcdh2p3E94sw=/144x32/downloads.coindesk.com/arc/failsafe/feeds/coindesk-logo-white.png",
        "cointelegraph.com": "https://images.cointelegraph.com/images/240_aHR0cHM6Ly9zMy5jb2ludGVsZWdyYXBoLmNvbS9zdG9yYWdlL3VwbG9hZHMvdmlldy8wMDAwMDAwMDAwMDAwMDAwMDEuanBn.jpg",
        "decrypt.co": "https://cdn.decrypt.co/wp-content/uploads/2019/10/decrypt-logo-dark.png",
        "theblock.co": "https://www.theblock.co/static/images/theblock-logo-text-only.svg",
        "blockworks.co": "https://blockworks.co/_next/static/media/blockworks-logo-dark.svg",
        "bitcoinmagazine.com": "https://bitcoinmagazine.com/.image/t_share/MTc5Mjk3NzU2NjYxNDM5NTMz/btcm-logo-white-800.png",
        // Crypto news aggregators (Tier 2)
        "cryptoslate.com": "https://cryptoslate.com/wp-content/themes/flavor-flavor/flavor/dist/images/logo-cs.svg",
        "newsbtc.com": "https://www.newsbtc.com/wp-content/uploads/2020/06/newsbtc-logo.svg",
        "beincrypto.com": "https://beincrypto.com/wp-content/uploads/2021/09/bic_logo_white.svg",
        "cryptopotato.com": "https://cryptopotato.com/wp-content/uploads/2021/01/cp_logo_white.png",
        "u.today": "https://u.today/sites/default/files/u-today-logo.svg",
        "dailyhodl.com": "https://dailyhodl.com/wp-content/uploads/2020/04/daily-hodl-logo.png",
        "bitcoinist.com": "https://bitcoinist.com/wp-content/uploads/2021/02/bitcoinist-logo.svg",
        "cryptonews.com": "https://cryptonews.com/assets/images/logos/cn-logo-white.svg",
        // Additional crypto publishers
        "ambcrypto.com": "https://ambcrypto.com/wp-content/uploads/2021/11/cropped-AMBCrypto-logo-2.png",
        "cryptopolitan.com": "https://www.cryptopolitan.com/wp-content/uploads/2022/01/Cryptopolitan-Logo-2.svg",
        "coingape.com": "https://coingape.com/wp-content/uploads/2022/03/CoinGape-Logo-1.svg",
        "finbold.com": "https://finbold.com/wp-content/uploads/2023/03/Finbold-Logo-white.svg",
        // DeFi and NFT focused
        "defipulse.com": "https://defipulse.com/images/defi-pulse-logo.svg",
        "nftevening.com": "https://nftevening.com/wp-content/uploads/2021/12/nft-evening-logo.png",
        // Market data sources
        "coinmarketcap.com": "https://coinmarketcap.com/favicon.ico",
        "coingecko.com": "https://static.coingecko.com/s/coingecko-logo-8903d34ce19ca4be1c81f0db30e924154750d208683fad7ae6f2ce06c76d0a56.png",
        // Traditional finance with crypto coverage
        "reuters.com": "https://www.reuters.com/pf/resources/images/reuters/logo-nav-desktop.svg",
        "bloomberg.com": "https://assets.bwbx.io/s3/fence/assets/images/bloomberg-logo-dark-f6a23f.svg",
        "forbes.com": "https://www.forbes.com/favicon.ico",
        "wsj.com": "https://s.wsj.net/media/wsj_print_icon_180.png",
        // Tech news with crypto coverage
        "techcrunch.com": "https://techcrunch.com/wp-content/uploads/2018/04/tc-logo-2018.png",
        "wired.com": "https://www.wired.com/verso/static/wired/assets/logo-header.svg",
        "theverge.com": "https://www.theverge.com/v-logo.svg"
    ]
    
    /// Get a high-quality publisher logo URL for a given article URL
    static func publisherLogoURL(for articleURL: URL) -> URL? {
        guard let host = articleURL.host?.lowercased() else { return nil }
        for (domain, logoURLString) in publisherLogos {
            if host.contains(domain), let url = URL(string: logoURLString) {
                return url
            }
        }
        return nil
    }
    
    /// Get the best fallback icon for a publisher (logo or Google favicon)
    static func publisherIconURL(for articleURL: URL) -> URL? {
        // Prefer high-res logo
        if let logo = publisherLogoURL(for: articleURL) { return logo }
        // Fall back to Google favicon
        return googleFavicon(for: articleURL, size: 256)
    }
    
    // MARK: - Trusted CDNs
    /// CDNs that reliably serve images without needing HEAD validation
    /// Comprehensive list synced across all image loading code paths
    static let trustedImageCDNs: Set<String> = [
        // Major crypto news image CDNs
        "images.cointelegraph.com", "s3.cointelegraph.com",
        "cdn.decrypt.co", "img.decrypt.co",
        "coindesk-coindesk-prod.cdn.arcpublishing.com",
        "static.coindesk.com", "www.coindesk.com",
        "images.coindeskassets.com",
        "static.theblock.co", "www.theblock.co",
        "blockworks.co",
        "cryptoslate.com", "img.cryptoslate.com",
        "newsbtc.com", "www.newsbtc.com",
        "beincrypto.com", "s32659.pcdn.co",
        "cryptopotato.com", "u.today", "bitcoinmagazine.com",
        "ambcrypto.com", "coingape.com", "cryptonews.com",
        "dailyhodl.com", "bitcoinist.com",
        // Generic CDNs
        "cloudfront.net", "amazonaws.com",
        "wp.com", "i0.wp.com", "i1.wp.com", "i2.wp.com",
        "imgur.com", "i.imgur.com",
        "fastly.net", "akamaized.net",
        "cdninstagram.com", "fbcdn.net",
        // Image optimization services
        "imgix.net", "imagekit.io", "cloudinary.com",
        // Major news outlets
        "static.reuters.com", "assets.bwbx.io",
        "images.wsj.net", "images.axios.com",
        "static01.nyt.com", "i.guim.co.uk",
        "ichef.bbci.co.uk", "media.cnn.com",
        "media.npr.org", "s.yimg.com",
        "media.zenfs.com", "cdn.vox-cdn.com",
        "cdn.arstechnica.net", "static.politico.com",
        "i.ytimg.com", "img.youtube.com",
        // Google services
        "google.com", "gstatic.com",
        "t1.gstatic.com", "t2.gstatic.com", "t3.gstatic.com",
        // Cryptocurrency data providers
        "cryptocompare.com", "resources.cryptocompare.com"
    ]
    
    /// Check if a URL is from a trusted CDN that doesn't need HEAD validation
    static func isTrustedCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return trustedImageCDNs.contains { host.contains($0) }
    }
}

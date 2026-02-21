//
//  NewsQualityFilter.swift
//  CryptoSage
//
//  Centralized news quality filtering - single source of truth for all
//  domain lists, spam patterns, and crypto relevance checking.
//

import Foundation

/// Centralized news quality filter - use this instead of duplicating filtering logic
enum NewsQualityFilter {
    
    // MARK: - Domain Lists (Single Source of Truth)
    
    /// Allowed domains for crypto news (comprehensive list)
    static let allowedDomains: Set<String> = [
        // Tier 1 - Primary crypto news
        "coindesk.com", "cointelegraph.com", "decrypt.co", "theblock.co",
        "blockworks.co", "bitcoinmagazine.com", "thedefiant.io",
        // Tier 2 - Reliable crypto coverage
        "newsbtc.com", "cryptoslate.com", "beincrypto.com", "ambcrypto.com",
        "coingape.com", "cryptobriefing.com", "dailyhodl.com", "cryptopotato.com",
        "u.today", "finbold.com", "coinbureau.com", "bankless.com",
        // Tier 3 - Data/Research
        "messari.io", "coingecko.com", "glassnode.com",
        // Tier 4 - Mainstream finance with crypto coverage
        "reuters.com", "bloomberg.com", "cnbc.com", "forbes.com",
        "wsj.com", "ft.com", "investopedia.com", "nasdaq.com",
        "marketwatch.com", "yahoo.com",
        // Tier 5 - Tech publications with crypto coverage
        "wired.com", "theverge.com", "techcrunch.com", "arstechnica.com"
    ]
    
    /// Excluded domains - never show content from these
    static let excludedDomains: Set<String> = [
        // Developer/package sites
        "pypi.org", "github.com", "npmjs.com", "packagist.org",
        "readthedocs.io", "sourceforge.net", "gitlab.com",
        // Blog platforms (low signal-to-noise)
        "medium.com", "substack.com", "blogspot.com", "wordpress.com",
        // Aggregators (duplicate content)
        "biztoc.com",
        // Social media
        "twitter.com", "x.com", "reddit.com", "facebook.com"
    ]
    
    /// Exchange blog sources that primarily post listing announcements (spam)
    static let exchangeBlogSources: Set<String> = [
        "kraken blog", "binance blog", "coinbase blog", "okx blog",
        "bybit blog", "kucoin blog", "gate.io blog", "huobi blog",
        "bitfinex blog", "crypto.com blog", "gemini blog", "bitstamp blog"
    ]
    
    /// Low-quality aggregator / auto-generated content sources
    /// These sites mass-produce templated articles (e.g. "[COIN] Technical Analysis [DATE]")
    /// and add little editorial value. Block them to keep the feed curated and smart.
    static let lowQualitySources: Set<String> = [
        "coinotag", "coinotag news",
        "bitcoinsistemi", "bitcoin sistemi",
        "koinfinans", "coin-turk", "cointurk",
        "cryptorank", "cryptorank news",
        "thecoinrepublic", "the coin republic",
        "blockonomi", "zycrypto",
        "investorplace",    // mostly clickbait listicles
        "benzinga crypto",  // auto-generated price recaps
    ]
    
    /// Domains associated with low-quality aggregators (matched as host suffixes)
    static let lowQualityDomains: Set<String> = [
        "coinotag.com", "en.coinotag.com",
        "bitcoinsistemi.com",
        "koinfinans.com",
        "coin-turk.com", "cointurk.com",
        "thecoinrepublic.com",
    ]
    
    // MARK: - Pre-compiled Regex Patterns
    
    /// Matches version patterns like "v1.2.3", "0.0.97" (package release spam)
    static let versionRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "(?:\\bv?\\d+\\.\\d+(?:\\.\\d+)?|\\b0\\.0\\.\\d+)",
            options: [.caseInsensitive]
        )
    }()
    
    /// Matches exchange listing announcements like "X is available for trading"
    static let listingSpamRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(is|now)\\s+(available|live|listed)\\s+(for|on)\\s+(trading|trade|exchange)",
            options: [.caseInsensitive]
        )
    }()
    
    /// Matches airdrop/giveaway spam
    static let airdropSpamRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b(free|claim|airdrop)\\s+(crypto|token|coin|nft)s?\\b|\\bwin\\s+\\$?\\d+",
            options: [.caseInsensitive]
        )
    }()
    
    /// Matches auto-generated "Technical Analysis" template articles
    /// Pattern: "[COIN] Technical Analysis [DATE]" or "[COIN] Price Analysis [DATE]"
    /// These are mass-produced, cookie-cutter articles with no editorial value.
    static let templatedAnalysisRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "\\b\\w+\\s+(?:Technical|Price)\\s+Analysis\\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2}",
            options: [.caseInsensitive]
        )
    }()
    
    /// Matches generic templated headlines that follow rigid formats
    /// e.g. "Support and Resistance Levels", "RSI MACD Momentum", "Key Levels to Watch"
    static let genericTemplateRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "(?:Support(?:\\s+(?:and|&))?\\s+Resistance(?:\\s+(?:and|&))?\\s+Price\\s+Targets)|(?:RSI\\s+MACD\\s+Momentum)|(?:Market\\s+Commentary,?\\s+Support\\s+Resistance)",
            options: [.caseInsensitive]
        )
    }()
    
    // MARK: - Crypto Relevance Terms
    
    /// Core crypto terms that MUST appear for an article to be considered crypto-relevant
    static let coreCryptoTerms: Set<String> = [
        // Primary crypto terms
        "crypto", "cryptocurrency", "blockchain", "bitcoin", "btc", "ethereum", "eth",
        "defi", "nft", "web3", "token", "altcoin",
        // Major cryptocurrencies
        "solana", "cardano", "ripple", "xrp", "dogecoin", "doge",
        "polkadot", "avalanche", "avax", "chainlink", "polygon", "matic",
        "litecoin", "ltc", "shiba", "shib", "pepe", "memecoin",
        "tether", "usdt", "usdc", "stablecoin", "bnb", "binance",
        "toncoin", "cosmos", "algorand", "hedera",
        // DeFi protocols
        "uniswap", "aave", "compound", "curve", "sushiswap", "pancakeswap",
        "maker", "lido", "rocket pool",
        // NFT platforms
        "opensea", "blur", "ordinals",
        // Regulatory/institutional crypto
        "bitcoin etf", "crypto etf", "spot etf", "cbdc",
        // Crypto exchanges
        "coinbase", "kraken", "gemini", "ftx", "okx", "bybit"
    ]
    
    /// Secondary crypto terms - used to boost confidence but not required alone
    static let secondaryCryptoTerms: Set<String> = [
        "wallet", "exchange", "dex", "cex", "mining", "miner", "staking", "stake",
        "airdrop", "halving", "hodl", "whale", "bull run", "bear market",
        "smart contract", "layer 2", "l2", "rollup", "gas fee",
        "yield farm", "liquidity pool", "amm", "tvl", "apr", "apy",
        "perpetuals", "perps", "flash loan", "impermanent loss",
        "collectible", "digital art", "inscriptions",
        "crypto regulation", "crypto tax", "crypto ban", "digital currency",
        "crypto trading", "crypto price", "crypto market", "market cap"
    ]
    
    /// Terms that indicate the article is NOT primarily about crypto
    static let nonCryptoExclusionTerms: Set<String> = [
        "chatgpt", "openai", "gpt-4", "gpt-5", "artificial intelligence",
        "teen access", "age verification", "parental controls",
        "climate change", "global warming", "electric vehicle",
        "social media", "tiktok", "instagram", "facebook meta",
        "streaming service", "netflix", "disney",
        "video game", "playstation", "xbox", "nintendo"
    ]
    
    // MARK: - Filter Methods
    
    /// Check if a URL host is allowed
    static func hostIsAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // First check if explicitly excluded
        if excludedDomains.contains(where: { host.hasSuffix($0) }) {
            return false
        }
        // Allow anything not explicitly excluded (broader coverage)
        return true
    }
    
    /// Check if URL is a homepage/section page (not an article)
    static func isPublisherRoot(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return true }
        let lower = path.lowercased()
        // Known section keywords that definitely aren't articles
        let sectionPages: Set<String> = [
            "markets", "news", "latest", "home", "crypto", "technology",
            "cryptocurrency", "feed", "rss", "index", "category", "tag"
        ]
        if sectionPages.contains(lower) { return true }
        // Very shallow paths with no date/number components are likely sections
        let segments = lower.split(separator: "/")
        if segments.count == 1 && lower.rangeOfCharacter(from: .decimalDigits) == nil {
            return true
        }
        return false
    }
    
    /// Check if article title contains spam patterns
    static func isSpamTitle(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        
        // Check version spam
        if let regex = versionRegex, regex.firstMatch(in: title, options: [], range: range) != nil {
            return true
        }
        // Check listing spam
        if let regex = listingSpamRegex, regex.firstMatch(in: title, options: [], range: range) != nil {
            return true
        }
        // Check airdrop spam
        if let regex = airdropSpamRegex, regex.firstMatch(in: title, options: [], range: range) != nil {
            return true
        }
        // Check auto-generated templated technical analysis articles
        if let regex = templatedAnalysisRegex, regex.firstMatch(in: title, options: [], range: range) != nil {
            return true
        }
        // Check generic cookie-cutter headlines
        if let regex = genericTemplateRegex, regex.firstMatch(in: title, options: [], range: range) != nil {
            return true
        }
        return false
    }
    
    /// Check if source is an exchange blog (typically low-quality listing announcements)
    static func isExchangeBlogSource(_ sourceName: String) -> Bool {
        exchangeBlogSources.contains(sourceName.lowercased())
    }
    
    /// Check if source is a known low-quality aggregator that mass-produces templated content
    static func isLowQualitySource(_ sourceName: String) -> Bool {
        let lower = sourceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowQualitySources.contains(lower)
    }
    
    /// Check if a URL's host belongs to a low-quality aggregator domain
    static func isLowQualityDomain(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return lowQualityDomains.contains(where: { host.hasSuffix($0) })
    }
    
    /// Check if an article is crypto-relevant based on title and description
    static func isCryptoRelevant(title: String, description: String?) -> Bool {
        let titleLC = title.lowercased()
        let descLC = (description ?? "").lowercased()
        let fullText = titleLC + " " + descLC
        
        // Check for exclusion signals in the title
        let hasExclusionInTitle = nonCryptoExclusionTerms.contains { term in
            titleLC.contains(term)
        }
        
        // Check for core crypto terms
        let hasCoreTerm = coreCryptoTerms.contains { term in
            fullText.contains(term)
        }
        
        // If the title has strong exclusion signals AND no core crypto term in title, reject
        if hasExclusionInTitle {
            let hasCoreTermInTitle = coreCryptoTerms.contains { term in
                titleLC.contains(term)
            }
            if !hasCoreTermInTitle {
                return false
            }
        }
        
        // Must have at least one core crypto term
        if hasCoreTerm {
            return true
        }
        
        // If no core term, need at least 2 secondary terms to qualify
        var secondaryCount = 0
        for term in secondaryCryptoTerms {
            if fullText.contains(term) {
                secondaryCount += 1
                if secondaryCount >= 2 { return true }
            }
        }
        
        return false
    }
    
    /// Comprehensive quality check for a news article
    /// Returns true if the article passes all quality checks
    static func passesQualityCheck(
        url: URL,
        title: String,
        description: String?,
        sourceName: String
    ) -> Bool {
        // Check host allowlist
        guard hostIsAllowed(url) else { return false }
        
        // Check low-quality aggregator domains (e.g. coinotag.com)
        if isLowQualityDomain(url) { return false }
        
        // Check low-quality aggregator sources by name (e.g. "CoinOtag")
        if isLowQualitySource(sourceName) { return false }
        
        // Check if it's a homepage/section page
        if isPublisherRoot(url) { return false }
        
        // Check for spam patterns in title (includes templated analysis detection)
        if isSpamTitle(title) { return false }
        
        // Check for exchange blog sources
        if isExchangeBlogSource(sourceName) { return false }
        
        // Check crypto relevance
        if !isCryptoRelevant(title: title, description: description) { return false }
        
        return true
    }
}

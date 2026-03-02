//
//  DeFiTokenService.swift
//  CryptoSage
//
//  Service for fetching ERC20, SPL, and other token balances.
//

import Foundation
import Combine

// MARK: - DeFi Token Service

/// Service for fetching token balances across multiple chains
public final class DeFiTokenService: ObservableObject {
    public static let shared = DeFiTokenService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?
    @Published public private(set) var portfolios: [String: WalletPortfolio] = [:] // address -> portfolio
    
    // MARK: - Private Properties
    
    private let session: URLSession
    private let chainRegistry = ChainRegistry.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Rate limiting
    private var lastRequestTime: [String: Date] = [:]
    private let minRequestInterval: TimeInterval = 0.25 // 4 requests per second max
    
    // Cache
    private let cacheManager = CacheManager.shared
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        // SECURITY: Ephemeral session prevents disk caching of DeFi token balances
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Fetch all token balances for an address across specified chains
    public func fetchTokenBalances(
        address: String,
        chains: [Chain]? = nil
    ) async throws -> WalletPortfolio {
        isLoading = true
        defer { isLoading = false }
        
        let targetChains = chains ?? detectChains(for: address)
        
        var portfolio = WalletPortfolio(address: address)
        
        // Fetch balances from each chain in parallel
        await withTaskGroup(of: (Chain, NativeBalance?, [TokenBalance]).self) { group in
            for chain in targetChains {
                group.addTask {
                    do {
                        let (native, tokens) = try await self.fetchChainBalances(address: address, chain: chain)
                        return (chain, native, tokens)
                    } catch {
                        #if DEBUG
                        print("⚠️ Error fetching \(chain.displayName) balances: \(error.localizedDescription)")
                        #endif
                        return (chain, nil, [])
                    }
                }
            }
            
            for await (_, native, tokens) in group {
                if let native = native {
                    portfolio.nativeBalances.append(native)
                }
                portfolio.tokenBalances.append(contentsOf: tokens)
            }
        }
        
        // Calculate total value
        portfolio.recalculateTotalValue()
        portfolio.lastUpdated = Date()
        
        // Cache the portfolio
        portfolios[address.lowercased()] = portfolio
        
        return portfolio
    }
    
    /// Fetch token balances for a specific chain
    public func fetchChainBalances(
        address: String,
        chain: Chain
    ) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        switch chain {
        // EVM-compatible chains
        case .ethereum, .arbitrum, .optimism, .base, .polygon, .bsc, .avalanche, .fantom, .zksync,
             .linea, .scroll, .manta, .mantle, .blast, .mode, .polygonZkEvm, .tron:
            return try await fetchEVMBalances(address: address, chain: chain)
        case .solana:
            return try await fetchSolanaBalances(address: address)
        case .bitcoin:
            let native = try await fetchBitcoinBalance(address: address)
            return (native, [])
        // Non-EVM chains - not yet supported for direct balance fetching
        case .sui, .aptos, .ton, .near, .cosmos, .polkadot, .cardano, .starknet, .osmosis, .injective, .sei:
            // These chains require specialized APIs - return empty for now
            // Users should use DeBank aggregator for these chains
            #if DEBUG
            print("⚠️ Direct balance fetching not yet supported for \(chain.displayName). Use DeBank integration.")
            #endif
            return (nil, [])
        }
    }
    
    /// Detect which chains an address is valid on
    private func detectChains(for address: String) -> [Chain] {
        if let primaryChain = chainRegistry.detectChain(from: address) {
            if primaryChain.isEVM {
                // EVM address is valid on all EVM chains
                return chainRegistry.evmChains
            }
            return [primaryChain]
        }
        return []
    }
    
    // MARK: - EVM Chain Fetching
    
    private func fetchEVMBalances(
        address: String,
        chain: Chain
    ) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        // Try Alchemy first if API key is available
        if let alchemyKey = chainRegistry.apiKey(for: ChainAPIService.alchemy.rawValue) {
            return try await fetchAlchemyBalances(address: address, chain: chain, apiKey: alchemyKey)
        }
        
        // Fallback to explorer API (Etherscan, etc.)
        return try await fetchExplorerBalances(address: address, chain: chain)
    }
    
    /// Fetch balances using Alchemy API
    private func fetchAlchemyBalances(
        address: String,
        chain: Chain,
        apiKey: String
    ) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        let baseURL = alchemyEndpoint(for: chain, apiKey: apiKey)
        guard let url = URL(string: baseURL) else {
            throw DeFiError.invalidURL
        }
        
        // Fetch native balance
        let nativeBalance = try await fetchAlchemyNativeBalance(address: address, url: url, chain: chain)
        
        // Fetch token balances
        let tokenBalances = try await fetchAlchemyTokenBalances(address: address, url: url, chain: chain)
        
        return (nativeBalance, tokenBalances)
    }
    
    private func alchemyEndpoint(for chain: Chain, apiKey: String) -> String {
        switch chain {
        case .ethereum: return "https://eth-mainnet.g.alchemy.com/v2/\(apiKey)"
        case .arbitrum: return "https://arb-mainnet.g.alchemy.com/v2/\(apiKey)"
        case .optimism: return "https://opt-mainnet.g.alchemy.com/v2/\(apiKey)"
        case .base: return "https://base-mainnet.g.alchemy.com/v2/\(apiKey)"
        case .polygon: return "https://polygon-mainnet.g.alchemy.com/v2/\(apiKey)"
        default: return "https://eth-mainnet.g.alchemy.com/v2/\(apiKey)"
        }
    }
    
    private func fetchAlchemyNativeBalance(
        address: String,
        url: URL,
        chain: Chain
    ) async throws -> NativeBalance {
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getBalance",
            "params": [address, "latest"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        
        struct BalanceResponse: Codable {
            let result: String?
        }
        
        let response = try JSONDecoder().decode(BalanceResponse.self, from: data)
        
        // Convert hex to decimal
        let hexBalance = response.result ?? "0x0"
        let weiBalance = hexToDecimal(hexBalance)
        let ethBalance = weiBalance / pow(10, Double(chain.nativeDecimals))
        
        // Get price from LivePriceManager
        let price = await fetchNativePrice(chain: chain)
        
        return NativeBalance(
            chain: chain,
            symbol: chain.nativeSymbol,
            name: chain.nativeName,
            balance: ethBalance,
            rawBalance: hexBalance,
            priceUSD: price,
            valueUSD: price.map { ethBalance * $0 }
        )
    }
    
    private func fetchAlchemyTokenBalances(
        address: String,
        url: URL,
        chain: Chain
    ) async throws -> [TokenBalance] {
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "alchemy_getTokenBalances",
            "params": [address]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(AlchemyTokenBalancesResponse.self, from: data)
        
        guard let result = response.result else { return [] }
        
        var tokens: [TokenBalance] = []
        
        // Filter out zero balances and fetch metadata
        let nonZeroBalances = result.tokenBalances.filter {
            guard let balance = $0.tokenBalance else { return false }
            return balance != "0x0" && balance != "0x" && balance != "0"
        }
        
        // Fetch metadata for each token (in batches to avoid rate limits)
        for balance in nonZeroBalances.prefix(50) { // Limit to 50 tokens
            if let tokenBalance = await fetchTokenWithMetadata(
                contractAddress: balance.contractAddress,
                rawBalance: balance.tokenBalance ?? "0",
                chain: chain,
                alchemyURL: url
            ) {
                tokens.append(tokenBalance)
            }
        }
        
        return tokens
    }
    
    private func fetchTokenWithMetadata(
        contractAddress: String,
        rawBalance: String,
        chain: Chain,
        alchemyURL: URL
    ) async -> TokenBalance? {
        
        var request = URLRequest(url: alchemyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "alchemy_getTokenMetadata",
            "params": [contractAddress]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        guard let response = try? JSONDecoder().decode(AlchemyTokenMetadataResponse.self, from: data) else { return nil }
        guard let metadata = response.result else { return nil }
        
        let decimals = metadata.decimals ?? 18
        let balance = hexToDecimal(rawBalance) / pow(10, Double(decimals))
        
        // Skip dust amounts
        guard balance > 0.000001 else { return nil }
        
        // Get price from CoinGecko by contract
        let price = await fetchTokenPrice(contractAddress: contractAddress, chain: chain)
        
        return TokenBalance(
            contractAddress: contractAddress,
            symbol: metadata.symbol ?? "???",
            name: metadata.name ?? "Unknown Token",
            decimals: decimals,
            balance: balance,
            rawBalance: rawBalance,
            chain: chain,
            logoURL: metadata.logo,
            priceUSD: price,
            valueUSD: price.map { balance * $0 },
            isVerified: metadata.logo != nil
        )
    }
    
    /// Fetch balances using block explorer API (Etherscan, etc.)
    private func fetchExplorerBalances(
        address: String,
        chain: Chain
    ) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        guard let config = chainRegistry.configuration(for: chain),
              let apiURL = config.explorerAPIURL else {
            throw DeFiError.unsupportedChain
        }
        
        let apiKey = config.explorerAPIKey ?? ""
        
        // Fetch native balance
        let nativeBalance = try await fetchExplorerNativeBalance(
            address: address,
            apiURL: apiURL,
            apiKey: apiKey,
            chain: chain
        )
        
        // Fetch token balances
        let tokenBalances = try await fetchExplorerTokenBalances(
            address: address,
            apiURL: apiURL,
            apiKey: apiKey,
            chain: chain
        )
        
        return (nativeBalance, tokenBalances)
    }
    
    private func fetchExplorerNativeBalance(
        address: String,
        apiURL: String,
        apiKey: String,
        chain: Chain
    ) async throws -> NativeBalance {
        
        var components = URLComponents(string: apiURL)!
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "balance"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "tag", value: "latest")
        ]
        if !apiKey.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else {
            throw DeFiError.invalidURL
        }
        
        try await respectRateLimit(for: apiURL)
        
        let (data, _) = try await session.data(from: url)
        
        struct BalanceResponse: Codable {
            let status: String
            let result: String
        }
        
        let response = try JSONDecoder().decode(BalanceResponse.self, from: data)
        
        let weiBalance = Double(response.result) ?? 0
        let balance = weiBalance / pow(10, Double(chain.nativeDecimals))
        
        let price = await fetchNativePrice(chain: chain)
        
        return NativeBalance(
            chain: chain,
            symbol: chain.nativeSymbol,
            name: chain.nativeName,
            balance: balance,
            rawBalance: response.result,
            priceUSD: price,
            valueUSD: price.map { balance * $0 }
        )
    }
    
    private func fetchExplorerTokenBalances(
        address: String,
        apiURL: String,
        apiKey: String,
        chain: Chain
    ) async throws -> [TokenBalance] {
        
        var components = URLComponents(string: apiURL)!
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokentx"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "startblock", value: "0"),
            URLQueryItem(name: "endblock", value: "99999999"),
            URLQueryItem(name: "sort", value: "desc")
        ]
        if !apiKey.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else {
            throw DeFiError.invalidURL
        }
        
        try await respectRateLimit(for: apiURL)
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(EtherscanTokenTxResponse.self, from: data)
        
        guard let transfers = response.result else { return [] }
        
        // Aggregate balances by contract
        var balancesByContract: [String: (symbol: String, name: String, decimals: Int, balance: Double)] = [:]
        
        for tx in transfers {
            let contract = tx.contractAddress.lowercased()
            let decimals = Int(tx.tokenDecimal) ?? 18
            let value = (Double(tx.value) ?? 0) / pow(10, Double(decimals))
            
            let isIncoming = tx.to.lowercased() == address.lowercased()
            let delta = isIncoming ? value : -value
            
            if var existing = balancesByContract[contract] {
                existing.balance += delta
                balancesByContract[contract] = existing
            } else {
                balancesByContract[contract] = (tx.tokenSymbol, tx.tokenName, decimals, delta)
            }
        }
        
        // Convert to TokenBalance objects
        var tokens: [TokenBalance] = []
        for (contract, info) in balancesByContract {
            guard info.balance > 0.000001 else { continue }
            
            let price = await fetchTokenPrice(contractAddress: contract, chain: chain)
            
            tokens.append(TokenBalance(
                contractAddress: contract,
                symbol: info.symbol,
                name: info.name,
                decimals: info.decimals,
                balance: info.balance,
                rawBalance: String(Int(info.balance * pow(10, Double(info.decimals)))),
                chain: chain,
                priceUSD: price,
                valueUSD: price.map { info.balance * $0 }
            ))
        }
        
        return tokens.sorted { ($0.valueUSD ?? 0) > ($1.valueUSD ?? 0) }
    }
    
    // MARK: - Solana Fetching
    
    private func fetchSolanaBalances(address: String) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        // Try Helius if API key is available
        if let heliusKey = chainRegistry.apiKey(for: ChainAPIService.helius.rawValue) {
            return try await fetchHeliusBalances(address: address, apiKey: heliusKey)
        }
        
        // Fallback to basic RPC
        return try await fetchSolanaRPCBalances(address: address)
    }
    
    private func fetchHeliusBalances(
        address: String,
        apiKey: String
    ) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        let urlString = "https://api.helius.xyz/v0/addresses/\(address)/balances?api-key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(HeliusBalanceResponse.self, from: data)
        
        // Native SOL balance
        var nativeBalance: NativeBalance?
        if let native = response.nativeBalance {
            let solBalance = Double(native.lamports) / 1_000_000_000
            nativeBalance = NativeBalance(
                chain: .solana,
                symbol: "SOL",
                name: "Solana",
                balance: solBalance,
                rawBalance: String(native.lamports),
                priceUSD: native.price_per_sol,
                valueUSD: native.total_price
            )
        }
        
        // SPL tokens
        var tokens: [TokenBalance] = []
        if let tokenList = response.tokens {
            for token in tokenList {
                let balance = Double(token.amount) / pow(10, Double(token.decimals))
                guard balance > 0.000001 else { continue }
                
                tokens.append(TokenBalance(
                    contractAddress: token.mint,
                    symbol: token.symbol ?? "???",
                    name: token.name ?? "Unknown Token",
                    decimals: token.decimals,
                    balance: balance,
                    rawBalance: String(token.amount),
                    chain: .solana,
                    logoURL: token.logo,
                    priceUSD: token.price_info?.price_per_token,
                    valueUSD: token.price_info?.total_price
                ))
            }
        }
        
        return (nativeBalance, tokens)
    }
    
    private func fetchSolanaRPCBalances(address: String) async throws -> (native: NativeBalance?, tokens: [TokenBalance]) {
        
        guard let config = chainRegistry.configuration(for: .solana),
              let rpcURL = config.primaryRPC,
              let url = URL(string: rpcURL) else {
            throw DeFiError.unsupportedChain
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        
        struct SolanaBalance: Codable {
            struct Result: Codable {
                let value: Int64
            }
            let result: Result?
        }
        
        let response = try JSONDecoder().decode(SolanaBalance.self, from: data)
        let lamports = response.result?.value ?? 0
        let solBalance = Double(lamports) / 1_000_000_000
        
        let price = await fetchNativePrice(chain: .solana)
        
        let nativeBalance = NativeBalance(
            chain: .solana,
            symbol: "SOL",
            name: "Solana",
            balance: solBalance,
            rawBalance: String(lamports),
            priceUSD: price,
            valueUSD: price.map { solBalance * $0 }
        )
        
        // Basic RPC doesn't include tokens - would need additional calls
        return (nativeBalance, [])
    }
    
    // MARK: - Bitcoin Fetching
    
    private func fetchBitcoinBalance(address: String) async throws -> NativeBalance {
        
        let urlString = "https://blockchain.info/rawaddr/\(address)"
        guard let url = URL(string: urlString) else {
            throw DeFiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            // Address not found - return zero balance
            return NativeBalance(
                chain: .bitcoin,
                symbol: "BTC",
                name: "Bitcoin",
                balance: 0,
                rawBalance: "0"
            )
        }
        
        struct BitcoinAddress: Codable {
            let final_balance: Int64
        }
        
        let btcAddress = try JSONDecoder().decode(BitcoinAddress.self, from: data)
        let btcBalance = Double(btcAddress.final_balance) / 100_000_000
        
        let price = await fetchNativePrice(chain: .bitcoin)
        
        return NativeBalance(
            chain: .bitcoin,
            symbol: "BTC",
            name: "Bitcoin",
            balance: btcBalance,
            rawBalance: String(btcAddress.final_balance),
            priceUSD: price,
            valueUSD: price.map { btcBalance * $0 }
        )
    }
    
    // MARK: - Price Fetching
    
    private func fetchNativePrice(chain: Chain) async -> Double? {
        // Use LivePriceManager if available
        await MainActor.run {
            let coins = LivePriceManager.shared.currentCoinsList
            let symbol = chain.nativeSymbol.uppercased()
            return coins.first { $0.symbol.uppercased() == symbol }?.priceUsd
        }
    }
    
    private func fetchTokenPrice(contractAddress: String, chain: Chain) async -> Double? {
        guard let platform = chain.coingeckoPlatform else { return nil }
        
        let curr = CurrencyManager.apiValue
        let urlString = "https://api.coingecko.com/api/v3/simple/token_price/\(platform)?contract_addresses=\(contractAddress)&vs_currencies=\(curr)"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            try await respectRateLimit(for: "coingecko")
            let req = APIConfig.coinGeckoRequest(url: url)
            let (data, _) = try await session.data(for: req)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
               let tokenData = json[contractAddress.lowercased()],
               let price = tokenData[curr] ?? tokenData["usd"] {
                return price
            }
        } catch {
            // Silently fail for price lookup
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func hexToDecimal(_ hex: String) -> Double {
        var hexString = hex
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        guard let value = UInt64(hexString, radix: 16) else { return 0 }
        return Double(value)
    }
    
    private func respectRateLimit(for endpoint: String) async throws {
        let now = Date()
        if let lastRequest = lastRequestTime[endpoint] {
            let elapsed = now.timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                try await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime[endpoint] = Date()
    }
}

// MARK: - DeFi Errors

public enum DeFiError: LocalizedError {
    case invalidURL
    case unsupportedChain
    case rateLimited
    case invalidResponse
    case networkError(Error)
    case invalidAddress
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .unsupportedChain:
            return "This blockchain is not yet supported"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidAddress:
            return "Invalid wallet address"
        }
    }
}

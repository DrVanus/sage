//
//  BlockchainConnectionProvider.swift
//  CryptoSage
//
//  Blockchain API connection provider for wallet address tracking.
//  No API keys needed - uses public blockchain data.
//  Supports Ethereum (Etherscan), Bitcoin (Blockchain.com), and Solana (Solscan).
//

import Foundation

// MARK: - Blockchain Configuration

/// Configuration for blockchain API providers
struct BlockchainAPIConfig {
    let id: String
    let name: String
    let chain: String
    let symbol: String
    let baseURL: URL
    let addressPattern: String // Regex pattern for address validation
    let apiKeyRequired: Bool
    let apiKey: String? // Optional API key for higher rate limits
    
    /// Ethereum via Etherscan
    static let ethereum = BlockchainAPIConfig(
        id: "ethereum_wallet",
        name: "Ethereum Wallet",
        chain: "ETH",
        symbol: "ETH",
        baseURL: URL(string: "https://api.etherscan.io/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil // Set via environment or config for higher rate limits
    )
    
    /// Bitcoin via Blockchain.com
    static let bitcoin = BlockchainAPIConfig(
        id: "bitcoin_wallet",
        name: "Bitcoin Wallet",
        chain: "BTC",
        symbol: "BTC",
        baseURL: URL(string: "https://blockchain.info")!,
        addressPattern: "^(bc1|[13])[a-zA-HJ-NP-Z0-9]{25,39}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// Solana via public RPC
    static let solana = BlockchainAPIConfig(
        id: "solana_wallet",
        name: "Solana Wallet",
        chain: "SOL",
        symbol: "SOL",
        baseURL: URL(string: "https://api.mainnet-beta.solana.com")!,
        addressPattern: "^[1-9A-HJ-NP-Za-km-z]{32,44}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// Polygon via Polygonscan
    static let polygon = BlockchainAPIConfig(
        id: "polygon_wallet",
        name: "Polygon Wallet",
        chain: "MATIC",
        symbol: "MATIC",
        baseURL: URL(string: "https://api.polygonscan.com/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// Arbitrum via Arbiscan
    static let arbitrum = BlockchainAPIConfig(
        id: "arbitrum_wallet",
        name: "Arbitrum Wallet",
        chain: "ARB",
        symbol: "ETH", // Native token is ETH on Arbitrum
        baseURL: URL(string: "https://api.arbiscan.io/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// Base via Basescan
    static let base = BlockchainAPIConfig(
        id: "base_wallet",
        name: "Base Wallet",
        chain: "BASE",
        symbol: "ETH", // Native token is ETH on Base
        baseURL: URL(string: "https://api.basescan.org/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// Avalanche via Snowtrace
    static let avalanche = BlockchainAPIConfig(
        id: "avalanche_wallet",
        name: "Avalanche Wallet",
        chain: "AVAX",
        symbol: "AVAX",
        baseURL: URL(string: "https://api.snowtrace.io/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// BNB Chain via BscScan
    static let bnbchain = BlockchainAPIConfig(
        id: "bnb_wallet",
        name: "BNB Chain Wallet",
        chain: "BNB",
        symbol: "BNB",
        baseURL: URL(string: "https://api.bscscan.com/api")!,
        addressPattern: "^0x[a-fA-F0-9]{40}$",
        apiKeyRequired: false,
        apiKey: nil
    )
    
    /// All configurations
    static let all: [String: BlockchainAPIConfig] = [
        "ethereum_wallet": ethereum,
        "eth": ethereum,
        "bitcoin_wallet": bitcoin,
        "btc": bitcoin,
        "solana_wallet": solana,
        "sol": solana,
        "polygon_wallet": polygon,
        "polygon": polygon,
        "matic": polygon,
        "arbitrum_wallet": arbitrum,
        "arbitrum": arbitrum,
        "arb": arbitrum,
        "base_wallet": base,
        "base": base,
        "avalanche_wallet": avalanche,
        "avalanche": avalanche,
        "avax": avalanche,
        "bnb_wallet": bnbchain,
        "bnb": bnbchain,
        "bsc": bnbchain
    ]
    
    static func get(_ id: String) -> BlockchainAPIConfig? {
        all[id.lowercased()]
    }
    
    /// Detect chain from wallet address format
    static func detectChain(from address: String) -> BlockchainAPIConfig? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ethereum - starts with 0x and 40 hex chars
        if trimmed.hasPrefix("0x") && trimmed.count == 42 {
            return ethereum
        }
        
        // Bitcoin - starts with 1, 3, or bc1
        if trimmed.hasPrefix("bc1") || trimmed.hasPrefix("1") || trimmed.hasPrefix("3") {
            return bitcoin
        }
        
        // Solana - Base58, 32-44 chars, no 0, O, I, l
        if trimmed.count >= 32 && trimmed.count <= 44 &&
           !trimmed.contains("0") && !trimmed.contains("O") &&
           !trimmed.contains("I") && !trimmed.contains("l") {
            return solana
        }
        
        return nil
    }
}

// MARK: - Stored Wallet Address

struct StoredWalletAddress: Codable, Identifiable {
    let id: String
    let address: String
    let chain: String
    let label: String?
    let createdAt: Date
    
    init(address: String, chain: String, label: String? = nil) {
        self.id = UUID().uuidString
        self.address = address
        self.chain = chain
        self.label = label
        self.createdAt = Date()
    }
}

// MARK: - Blockchain Connection Provider Implementation

final class BlockchainConnectionProviderImpl: ConnectionProvider {
    static let shared = BlockchainConnectionProviderImpl()
    
    var connectionType: ConnectionType { .walletAddress }
    var supportedExchanges: [String] { 
        ["ethereum_wallet", "bitcoin_wallet", "solana_wallet", 
         "polygon_wallet", "arbitrum_wallet", "base_wallet", 
         "avalanche_wallet", "bnb_wallet"]
    }
    
    // MARK: - Session
    
    private lazy var session: URLSession = {
        // SECURITY: Ephemeral session prevents disk caching of wallet balances
        // and token holdings fetched from blockchain RPCs.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()
    
    // MARK: - ConnectionProvider Protocol
    
    func supports(exchangeId: String) -> Bool {
        supportedExchanges.contains(exchangeId.lowercased())
    }
    
    func connect(exchangeId: String, credentials: ConnectionCredentials) async throws -> ConnectionResult {
        guard case .walletAddress(let address, let chain) = credentials else {
            throw ConnectionError.invalidCredentials
        }
        
        // Validate address format
        guard validateAddressFormat(address: address, chain: chain) else {
            throw ConnectionError.invalidAddress
        }
        
        // Generate account ID
        let accountId = "\(chain.lowercased())-\(address.prefix(8))-\(address.suffix(4))"
        
        // Store wallet address
        let stored = StoredWalletAddress(address: address, chain: chain, label: nil)
        saveWalletAddress(stored)
        
        // Fetch initial balances from real blockchain APIs
        let balances = try await fetchBalances(for: address, chain: chain)
        
        return ConnectionResult(
            success: true,
            accountId: accountId,
            accountName: "\(chain) Wallet (...\(address.suffix(6)))",
            error: nil,
            balances: balances
        )
    }
    
    func disconnect(accountId: String) async throws {
        // Account ID format: "chain-addressPrefix-addressSuffix"
        // StoredWalletAddress.id is a UUID — match by address prefix/suffix instead
        let parts = accountId.split(separator: "-")
        guard parts.count >= 3 else { return }

        let chain = String(parts[0])
        let addrPrefix = String(parts[1])
        let addrSuffix = String(parts[2])

        let addresses = getStoredAddresses()
        if let toRemove = addresses.first(where: {
            $0.chain.lowercased() == chain.lowercased() &&
            $0.address.hasPrefix(addrPrefix) &&
            $0.address.hasSuffix(addrSuffix)
        }) {
            removeWalletAddress(toRemove.id)
        }
    }
    
    func fetchBalances(accountId: String) async throws -> [PortfolioBalance] {
        // Find stored address
        let addresses = getStoredAddresses()
        
        // Try to match by account ID pattern
        let parts = accountId.split(separator: "-")
        guard parts.count >= 1 else {
            throw ConnectionError.unknown("Invalid account ID")
        }
        
        let chain = String(parts[0]).uppercased()
        
        // Find address with matching prefix/suffix
        guard let stored = addresses.first(where: {
            $0.chain.uppercased() == chain &&
            accountId.contains(String($0.address.prefix(8))) &&
            accountId.contains(String($0.address.suffix(4)))
        }) else {
            throw ConnectionError.invalidCredentials
        }
        
        return try await fetchBalances(for: stored.address, chain: stored.chain)
    }
    
    func validateCredentials(exchangeId: String, credentials: ConnectionCredentials) async throws -> Bool {
        guard case .walletAddress(let address, let chain) = credentials else {
            return false
        }
        return validateAddressFormat(address: address, chain: chain)
    }
    
    // MARK: - Address Validation
    
    private func validateAddressFormat(address: String, chain: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get config for chain
        let config = BlockchainAPIConfig.get(chain) ?? BlockchainAPIConfig.get("\(chain)_wallet")
        
        guard let pattern = config?.addressPattern else {
            // Try auto-detection
            return BlockchainAPIConfig.detectChain(from: trimmed) != nil
        }
        
        // Validate against regex
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }
    
    // MARK: - Balance Fetching (Real APIs Only)
    
    private func fetchBalances(for address: String, chain: String) async throws -> [PortfolioBalance] {
        switch chain.uppercased() {
        case "ETH", "ETHEREUM":
            return try await fetchEthereumBalances(address: address)
        case "BTC", "BITCOIN":
            return try await fetchBitcoinBalances(address: address)
        case "SOL", "SOLANA":
            return try await fetchSolanaBalances(address: address)
        case "MATIC", "POLYGON":
            return try await fetchEVMChainBalances(address: address, config: BlockchainAPIConfig.polygon)
        case "ARB", "ARBITRUM":
            return try await fetchEVMChainBalances(address: address, config: BlockchainAPIConfig.arbitrum)
        case "BASE":
            return try await fetchEVMChainBalances(address: address, config: BlockchainAPIConfig.base)
        case "AVAX", "AVALANCHE":
            return try await fetchEVMChainBalances(address: address, config: BlockchainAPIConfig.avalanche)
        case "BNB", "BSC":
            return try await fetchEVMChainBalances(address: address, config: BlockchainAPIConfig.bnbchain)
        default:
            throw ConnectionError.unsupportedExchange
        }
    }
    
    // MARK: - Ethereum via Etherscan
    
    /// Popular ERC-20 tokens with their contract addresses and decimals
    private static let popularERC20Tokens: [(symbol: String, name: String, contract: String, decimals: Int)] = [
        ("USDT", "Tether USD", "0xdac17f958d2ee523a2206206994597c13d831ec7", 6),
        ("USDC", "USD Coin", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", 6),
        ("WETH", "Wrapped Ether", "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", 18),
        ("WBTC", "Wrapped Bitcoin", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", 8),
        ("DAI", "Dai Stablecoin", "0x6b175474e89094c44da98b954eedeac495271d0f", 18),
        ("LINK", "Chainlink", "0x514910771af9ca656af840dff83e8264ecf986ca", 18),
        ("UNI", "Uniswap", "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", 18),
        ("AAVE", "Aave", "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9", 18),
        ("SHIB", "Shiba Inu", "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce", 18),
        ("MATIC", "Polygon", "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", 18),
        ("MKR", "Maker", "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2", 18),
        ("CRO", "Cronos", "0xa0b73e1ff0b80914ab6fe0444e65848c4c34450b", 8),
        ("APE", "ApeCoin", "0x4d224452801aced8b2f0aebe155379bb5d594381", 18),
        ("LDO", "Lido DAO", "0x5a98fcbea516cf06857215779fd812ca3bef1b32", 18),
        ("SAND", "The Sandbox", "0x3845badade8e6dff049820680d1f14bd3903a5d0", 18),
        ("MANA", "Decentraland", "0x0f5d2fb29fb7d3cfee444a200298f468908cc942", 18),
        ("GRT", "The Graph", "0xc944e90c64b2c07662a292be6244bdf05cda44a7", 18),
        ("SNX", "Synthetix", "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f", 18),
        ("COMP", "Compound", "0xc00e94cb662c3520282e6f5717214004a7f26888", 18),
        ("PEPE", "Pepe", "0x6982508145454ce325ddbe47a25d4ec3d2311933", 18),
        ("ARB", "Arbitrum", "0xb50721bcf8d664c30412cfbc6cf7a15145234ad1", 18),
        ("OP", "Optimism", "0x4200000000000000000000000000000000000042", 18),
        ("BLUR", "Blur", "0x5283d291dbcf85356a21ba090e6db59121208b44", 18),
        ("FET", "Fetch.ai", "0xaea46a60368a7bd060eec7df8cba43b7ef41ad85", 18),
        ("RNDR", "Render Token", "0x6de037ef9ad2725eb40118bb1702ebb27e4aeb24", 18)
    ]
    
    private func fetchEthereumBalances(address: String) async throws -> [PortfolioBalance] {
        var balances: [PortfolioBalance] = []
        
        // Fetch ETH balance
        let ethBalance = try await fetchEthBalance(address: address)
        if let eth = ethBalance {
            balances.append(eth)
        }
        
        // Fetch ERC-20 token balances for popular tokens
        let tokenBalances = await fetchERC20Balances(address: address)
        balances.append(contentsOf: tokenBalances)
        
        return balances
    }
    
    private func fetchEthBalance(address: String) async throws -> PortfolioBalance? {
        guard var components = URLComponents(url: BlockchainAPIConfig.ethereum.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "balance"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "tag", value: "latest")
        ]
        
        // Add API key if available for higher rate limits
        if let apiKey = BlockchainAPIConfig.ethereum.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else {
            throw ConnectionError.unknown("Failed to construct URL")
        }
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct EtherscanResponse: Codable {
            let status: String
            let message: String?
            let result: String
        }
        
        let etherscanResponse = try JSONDecoder().decode(EtherscanResponse.self, from: data)
        
        if etherscanResponse.status == "1" {
            // Result is in wei, convert to ETH
            if let weiBalance = Double(etherscanResponse.result) {
                let ethBalance = weiBalance / 1_000_000_000_000_000_000 // 10^18
                if ethBalance > 0.0001 {
                    return PortfolioBalance(
                        symbol: "ETH",
                        name: "Ethereum",
                        balance: ethBalance,
                        chain: "ETH"
                    )
                }
            }
        } else if etherscanResponse.status == "0" {
            // Check for rate limiting or other errors
            if etherscanResponse.message?.contains("rate") == true {
                throw ConnectionError.rateLimited
            }
        }
        
        return nil
    }
    
    /// Fetch ERC-20 token balances using Etherscan tokentx API
    private func fetchERC20Balances(address: String) async -> [PortfolioBalance] {
        var balances: [PortfolioBalance] = []
        
        // Use the tokentx API to get ERC-20 transfer history, then calculate balances
        // This approach is more reliable than checking individual token contracts
        guard var components = URLComponents(url: BlockchainAPIConfig.ethereum.baseURL, resolvingAgainstBaseURL: false) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokentx"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "offset", value: "100"), // Last 100 token transfers
            URLQueryItem(name: "sort", value: "desc")
        ]
        
        if let apiKey = BlockchainAPIConfig.ethereum.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else { return balances }
        
        do {
            let request = URLRequest(url: url)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return balances
            }
            
            struct TokenTransfer: Codable {
                let contractAddress: String
                let tokenSymbol: String
                let tokenName: String
                let tokenDecimal: String
            }
            
            struct TokenTxResponse: Codable {
                let status: String
                let result: [TokenTransfer]?
            }
            
            let txResponse = try JSONDecoder().decode(TokenTxResponse.self, from: data)
            
            guard txResponse.status == "1", let transfers = txResponse.result else {
                return balances
            }
            
            // Get unique tokens the address has interacted with
            var seenTokens = Set<String>()
            var tokenInfo: [(contract: String, symbol: String, name: String, decimals: Int)] = []
            
            for transfer in transfers {
                let contract = transfer.contractAddress.lowercased()
                guard !seenTokens.contains(contract) else { continue }
                seenTokens.insert(contract)
                
                let decimals = Int(transfer.tokenDecimal) ?? 18
                tokenInfo.append((contract, transfer.tokenSymbol, transfer.tokenName, decimals))
            }
            
            // Also check popular tokens even if no transfers
            for token in Self.popularERC20Tokens {
                let contract = token.contract.lowercased()
                if !seenTokens.contains(contract) {
                    seenTokens.insert(contract)
                    tokenInfo.append((token.contract, token.symbol, token.name, token.decimals))
                }
            }
            
            // Limit to 20 tokens to avoid rate limiting
            let tokensToCheck = Array(tokenInfo.prefix(20))
            
            // Fetch balances for each token (with some delay to avoid rate limits)
            for (index, token) in tokensToCheck.enumerated() {
                // Add small delay every 5 requests to avoid rate limiting
                if index > 0 && index % 5 == 0 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                
                if let balance = await fetchSingleERC20Balance(
                    address: address,
                    contractAddress: token.contract,
                    symbol: token.symbol,
                    name: token.name,
                    decimals: token.decimals
                ) {
                    balances.append(balance)
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Error fetching ERC-20 balances: \(error.localizedDescription)")
            #endif
        }
        
        return balances
    }
    
    /// Fetch balance for a single ERC-20 token
    private func fetchSingleERC20Balance(
        address: String,
        contractAddress: String,
        symbol: String,
        name: String,
        decimals: Int
    ) async -> PortfolioBalance? {
        guard var components = URLComponents(url: BlockchainAPIConfig.ethereum.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokenbalance"),
            URLQueryItem(name: "contractaddress", value: contractAddress),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "tag", value: "latest")
        ]
        
        if let apiKey = BlockchainAPIConfig.ethereum.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else { return nil }
        
        do {
            let request = URLRequest(url: url)
            let (data, _) = try await session.data(for: request)
            
            struct TokenBalanceResponse: Codable {
                let status: String
                let result: String
            }
            
            let response = try JSONDecoder().decode(TokenBalanceResponse.self, from: data)
            
            guard response.status == "1",
                  let rawBalance = Double(response.result),
                  rawBalance > 0 else {
                return nil
            }
            
            // Convert based on decimals
            let divisor = pow(10.0, Double(decimals))
            let balance = rawBalance / divisor
            
            // Filter out dust (less than $0.01 worth assuming ~$1 per token for filtering)
            guard balance > 0.001 else { return nil }
            
            return PortfolioBalance(
                symbol: symbol,
                name: name,
                balance: balance,
                chain: "ETH"
            )
        } catch {
            #if DEBUG
            print("[BlockchainConnectionProvider] error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Bitcoin via Blockchain.com
    
    private func fetchBitcoinBalances(address: String) async throws -> [PortfolioBalance] {
        let url = BlockchainAPIConfig.bitcoin.baseURL
            .appendingPathComponent("rawaddr")
            .appendingPathComponent(address)
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.networkError(URLError(.badServerResponse))
        }
        
        // Handle 404 for invalid/empty addresses
        if httpResponse.statusCode == 404 {
            return [] // Address exists but has no transactions
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        
        struct BitcoinAddress: Codable {
            let final_balance: Int64 // In satoshis
        }
        
        let btcAddress = try JSONDecoder().decode(BitcoinAddress.self, from: data)
        
        // Convert satoshis to BTC
        let btcBalance = Double(btcAddress.final_balance) / 100_000_000.0
        
        if btcBalance > 0.00001 {
            return [PortfolioBalance(
                symbol: "BTC",
                name: "Bitcoin",
                balance: btcBalance,
                chain: "BTC"
            )]
        }
        
        return []
    }
    
    // MARK: - Solana via RPC
    
    private func fetchSolanaBalances(address: String) async throws -> [PortfolioBalance] {
        var balances: [PortfolioBalance] = []
        
        // Fetch SOL balance using JSON-RPC
        var request = URLRequest(url: BlockchainAPIConfig.solana.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        struct SolanaRPCResponse: Codable {
            struct Result: Codable {
                let value: Int64 // In lamports
            }
            struct Error: Codable {
                let code: Int
                let message: String
            }
            let result: Result?
            let error: Error?
        }
        
        let solanaResponse = try JSONDecoder().decode(SolanaRPCResponse.self, from: data)
        
        // Check for RPC errors
        if let error = solanaResponse.error {
            throw ConnectionError.unknown("Solana RPC error: \(error.message)")
        }
        
        if let lamports = solanaResponse.result?.value {
            let solBalance = Double(lamports) / 1_000_000_000.0 // 10^9
            if solBalance > 0.001 {
                balances.append(PortfolioBalance(
                    symbol: "SOL",
                    name: "Solana",
                    balance: solBalance,
                    chain: "SOL"
                ))
            }
        }
        
        return balances
    }
    
    // MARK: - Generic EVM Chain via Etherscan-compatible APIs
    
    /// Fetch balances for any EVM-compatible chain using Etherscan-compatible API
    private func fetchEVMChainBalances(address: String, config: BlockchainAPIConfig) async throws -> [PortfolioBalance] {
        var balances: [PortfolioBalance] = []

        // Fetch native token balance
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "balance"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "tag", value: "latest")
        ]
        
        if let apiKey = config.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else {
            throw ConnectionError.unknown("Failed to construct URL")
        }
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct EVMScanResponse: Codable {
            let status: String
            let message: String?
            let result: String
        }
        
        let evmResponse = try JSONDecoder().decode(EVMScanResponse.self, from: data)
        
        if evmResponse.status == "1" {
            // Result is in wei, convert based on decimals (18 for most chains)
            if let weiBalance = Double(evmResponse.result) {
                let balance = weiBalance / 1_000_000_000_000_000_000 // 10^18
                if balance > 0.0001 {
                    balances.append(PortfolioBalance(
                        symbol: config.symbol,
                        name: getChainNativeName(config.chain),
                        balance: balance,
                        chain: config.chain
                    ))
                }
            }
        } else if evmResponse.status == "0" {
            if evmResponse.message?.lowercased().contains("rate") == true {
                throw ConnectionError.rateLimited
            }
        }
        
        // Also fetch token balances for this chain
        let tokenBalances = await fetchEVMTokenBalances(address: address, config: config)
        balances.append(contentsOf: tokenBalances)
        
        return balances
    }
    
    /// Get the native token name for a chain
    private func getChainNativeName(_ chain: String) -> String {
        switch chain.uppercased() {
        case "MATIC": return "Polygon"
        case "ARB": return "Ethereum (Arbitrum)"
        case "BASE": return "Ethereum (Base)"
        case "AVAX": return "Avalanche"
        case "BNB": return "BNB"
        default: return chain
        }
    }
    
    /// Fetch ERC-20/token balances for EVM chains
    private func fetchEVMTokenBalances(address: String, config: BlockchainAPIConfig) async -> [PortfolioBalance] {
        var balances: [PortfolioBalance] = []

        // Fetch token transfer history to discover tokens
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokentx"),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "offset", value: "50"),
            URLQueryItem(name: "sort", value: "desc")
        ]
        
        if let apiKey = config.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else { return balances }
        
        do {
            let request = URLRequest(url: url)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return balances
            }
            
            struct TokenTransfer: Codable {
                let contractAddress: String
                let tokenSymbol: String
                let tokenName: String
                let tokenDecimal: String
            }
            
            struct TokenTxResponse: Codable {
                let status: String
                let result: [TokenTransfer]?
            }
            
            let txResponse = try JSONDecoder().decode(TokenTxResponse.self, from: data)
            
            guard txResponse.status == "1", let transfers = txResponse.result else {
                return balances
            }
            
            // Get unique tokens
            var seenTokens = Set<String>()
            var tokenInfo: [(contract: String, symbol: String, name: String, decimals: Int)] = []
            
            for transfer in transfers {
                let contract = transfer.contractAddress.lowercased()
                guard !seenTokens.contains(contract) else { continue }
                seenTokens.insert(contract)
                
                let decimals = Int(transfer.tokenDecimal) ?? 18
                tokenInfo.append((contract, transfer.tokenSymbol, transfer.tokenName, decimals))
                
                // Limit to 10 tokens per chain to avoid rate limiting
                if tokenInfo.count >= 10 { break }
            }
            
            // Fetch balances for discovered tokens
            for (index, token) in tokenInfo.enumerated() {
                if index > 0 && index % 3 == 0 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                
                if let balance = await fetchSingleEVMTokenBalance(
                    address: address,
                    contractAddress: token.contract,
                    symbol: token.symbol,
                    name: token.name,
                    decimals: token.decimals,
                    config: config
                ) {
                    balances.append(balance)
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Error fetching \(config.chain) token balances: \(error.localizedDescription)")
            #endif
        }
        
        return balances
    }
    
    /// Fetch balance for a single token on EVM chain
    private func fetchSingleEVMTokenBalance(
        address: String,
        contractAddress: String,
        symbol: String,
        name: String,
        decimals: Int,
        config: BlockchainAPIConfig
    ) async -> PortfolioBalance? {
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokenbalance"),
            URLQueryItem(name: "contractaddress", value: contractAddress),
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "tag", value: "latest")
        ]
        
        if let apiKey = config.apiKey {
            components.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        
        guard let url = components.url else { return nil }
        
        do {
            let request = URLRequest(url: url)
            let (data, _) = try await session.data(for: request)
            
            struct TokenBalanceResponse: Codable {
                let status: String
                let result: String
            }
            
            let response = try JSONDecoder().decode(TokenBalanceResponse.self, from: data)
            
            guard response.status == "1",
                  let rawBalance = Double(response.result),
                  rawBalance > 0 else {
                return nil
            }
            
            let divisor = pow(10.0, Double(decimals))
            let balance = rawBalance / divisor
            
            guard balance > 0.001 else { return nil }
            
            return PortfolioBalance(
                symbol: symbol,
                name: name,
                balance: balance,
                chain: config.chain
            )
        } catch {
            #if DEBUG
            print("[BlockchainConnectionProvider] error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Storage
    
    private let storageKey = "CryptoSage.WalletAddresses"
    
    private func saveWalletAddress(_ address: StoredWalletAddress) {
        var addresses = getStoredAddresses()
        
        // Don't duplicate
        if !addresses.contains(where: { $0.address == address.address }) {
            addresses.append(address)
        }
        
        saveAddresses(addresses)
    }
    
    private func getStoredAddresses() -> [StoredWalletAddress] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let addresses = try? JSONDecoder().decode([StoredWalletAddress].self, from: data) else {
            return []
        }
        return addresses
    }
    
    private func saveAddresses(_ addresses: [StoredWalletAddress]) {
        if let data = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func removeWalletAddress(_ id: String) {
        var addresses = getStoredAddresses()
        addresses.removeAll { $0.id == id }
        saveAddresses(addresses)
    }
    
    // MARK: - Public Helpers
    
    /// Auto-detect chain from address and connect
    func connectWithAutoDetect(address: String) async throws -> ConnectionResult {
        guard let config = BlockchainAPIConfig.detectChain(from: address) else {
            throw ConnectionError.invalidAddress
        }
        
        return try await connect(
            exchangeId: config.id,
            credentials: .walletAddress(address: address, chain: config.chain)
        )
    }
}

// MARK: - Replace Stub with Implementation

extension BlockchainConnectionProvider {
    /// Override the stub methods to use the real implementation
    static var implementation: BlockchainConnectionProviderImpl {
        BlockchainConnectionProviderImpl.shared
    }
}

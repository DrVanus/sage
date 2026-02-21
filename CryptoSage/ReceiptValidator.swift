//
//  ReceiptValidator.swift
//  CryptoSage
//
//  Handles App Store receipt validation for subscription verification.
//  Supports both local StoreKit 2 verification and optional server-side validation.
//

import Foundation
import StoreKit

// MARK: - Receipt Validation Configuration

/// Configuration for receipt validation
public enum ReceiptValidationConfig {
    /// Your backend server URL for receipt validation (optional but recommended for security)
    /// Example: "https://api.cryptosage.ai/validate-receipt"
    static let serverValidationURL: String? = nil // Set this to your backend URL
    
    /// Whether to require server validation (if false, will use local StoreKit 2 validation as fallback)
    static let requireServerValidation: Bool = false
    
    /// Timeout for server validation requests
    static let validationTimeout: TimeInterval = 30
}

// MARK: - Validation Result

/// Result of receipt validation
public struct ReceiptValidationResult {
    public let isValid: Bool
    public let productID: String?
    public let expirationDate: Date?
    public let originalTransactionID: String?
    public let environment: ReceiptEnvironment
    public let errorMessage: String?
    
    public enum ReceiptEnvironment: String {
        case production = "Production"
        case sandbox = "Sandbox"
        case unknown = "Unknown"
    }
    
    /// Create a successful validation result
    public static func success(
        productID: String,
        expirationDate: Date?,
        originalTransactionID: String?,
        environment: ReceiptEnvironment = .production
    ) -> ReceiptValidationResult {
        ReceiptValidationResult(
            isValid: true,
            productID: productID,
            expirationDate: expirationDate,
            originalTransactionID: originalTransactionID,
            environment: environment,
            errorMessage: nil
        )
    }
    
    /// Create a failed validation result
    public static func failure(_ message: String) -> ReceiptValidationResult {
        ReceiptValidationResult(
            isValid: false,
            productID: nil,
            expirationDate: nil,
            originalTransactionID: nil,
            environment: .unknown,
            errorMessage: message
        )
    }
}

// MARK: - Receipt Validator

/// Handles receipt validation for subscription verification
@MainActor
public final class ReceiptValidator: ObservableObject {
    public static let shared = ReceiptValidator()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isValidating: Bool = false
    @Published public private(set) var lastValidationResult: ReceiptValidationResult?
    @Published public private(set) var lastValidationDate: Date?
    
    // MARK: - Private Properties
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = ReceiptValidationConfig.validationTimeout
        config.timeoutIntervalForResource = ReceiptValidationConfig.validationTimeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Validate the current subscription status
    /// Uses StoreKit 2 local verification by default, with optional server-side validation
    public func validateSubscription() async -> ReceiptValidationResult {
        isValidating = true
        defer { isValidating = false }
        
        // Try server validation first if configured
        if let serverURL = ReceiptValidationConfig.serverValidationURL {
            let serverResult = await validateWithServer(url: serverURL)
            if serverResult.isValid {
                lastValidationResult = serverResult
                lastValidationDate = Date()
                return serverResult
            } else if ReceiptValidationConfig.requireServerValidation {
                // Server validation required but failed
                lastValidationResult = serverResult
                lastValidationDate = Date()
                return serverResult
            }
            // Fall through to local validation if server validation failed and not required
        }
        
        // Use StoreKit 2 local verification
        let localResult = await validateLocally()
        lastValidationResult = localResult
        lastValidationDate = Date()
        return localResult
    }
    
    /// Validate a specific transaction
    func validateTransaction(_ transaction: StoreKit.Transaction) async -> ReceiptValidationResult {
        isValidating = true
        defer { isValidating = false }
        
        // With StoreKit 2, transactions are already verified by the system
        // We just need to check if the transaction is still valid
        
        guard transaction.revocationDate == nil else {
            return .failure("Transaction has been revoked")
        }
        
        // Check expiration for subscriptions
        if let expirationDate = transaction.expirationDate {
            if expirationDate < Date() {
                return .failure("Subscription has expired")
            }
        }
        
        // Determine environment
        let environment: ReceiptValidationResult.ReceiptEnvironment
        if transaction.environment == .production {
            environment = .production
        } else if transaction.environment == .sandbox || transaction.environment == .xcode {
            environment = .sandbox
        } else {
            environment = .unknown
        }
        
        return .success(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            originalTransactionID: String(transaction.originalID),
            environment: environment
        )
    }
    
    // MARK: - Local Validation (StoreKit 2)
    
    /// Validate subscription using StoreKit 2 local verification
    private func validateLocally() async -> ReceiptValidationResult {
        #if DEBUG
        print("[Receipt] Starting local StoreKit 2 validation...")
        #endif
        
        // Check current entitlements
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Check if this is one of our subscription products
                if SubscriptionProductID.allIDs.contains(transaction.productID) {
                    // Validate the transaction
                    let validationResult = await validateTransaction(transaction)
                    if validationResult.isValid {
                        #if DEBUG
                        print("[Receipt] Valid subscription found: \(transaction.productID)")
                        #endif
                        return validationResult
                    }
                }
                
            case .unverified(_, let error):
                #if DEBUG
                print("[Receipt] Unverified transaction: \(error.localizedDescription)")
                #endif
                continue
            }
        }
        
        #if DEBUG
        print("[Receipt] No valid subscription found locally")
        #endif
        
        return .failure("No active subscription found")
    }
    
    // MARK: - Server Validation
    
    /// Validate receipt with your backend server
    /// Server should verify with Apple's servers and return validation result
    private func validateWithServer(url: String) async -> ReceiptValidationResult {
        #if DEBUG
        print("[Receipt] Starting server validation...")
        #endif
        
        guard let serverURL = URL(string: url) else {
            return .failure("Invalid server URL")
        }
        
        // Get the app receipt data
        guard let receiptData = getAppReceiptData() else {
            return .failure("Could not retrieve app receipt")
        }
        
        // Prepare the request
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body with receipt data
        let body: [String: Any] = [
            "receipt_data": receiptData.base64EncodedString(),
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure("Failed to encode request: \(error.localizedDescription)")
        }
        
        // Send the request
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Invalid server response")
            }
            
            guard httpResponse.statusCode == 200 else {
                return .failure("Server returned status code: \(httpResponse.statusCode)")
            }
            
            // Parse the response
            return parseServerResponse(data)
            
        } catch {
            #if DEBUG
            print("[Receipt] Server validation error: \(error.localizedDescription)")
            #endif
            return .failure("Server validation failed: \(error.localizedDescription)")
        }
    }
    
    /// Get the app receipt data from the bundle
    private func getAppReceiptData() -> Data? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            #if DEBUG
            print("[Receipt] No receipt URL found")
            #endif
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            #if DEBUG
            print("[Receipt] Receipt file does not exist at: \(receiptURL.path)")
            #endif
            return nil
        }
        
        do {
            let receiptData = try Data(contentsOf: receiptURL)
            return receiptData
        } catch {
            #if DEBUG
            print("[Receipt] Failed to read receipt: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Parse the server validation response
    private func parseServerResponse(_ data: Data) -> ReceiptValidationResult {
        // Expected response format from your server:
        // {
        //   "valid": true,
        //   "product_id": "com.cryptosage.pro.monthly",
        //   "expiration_date": "2024-01-15T00:00:00Z",
        //   "original_transaction_id": "1000000123456789",
        //   "environment": "Production"
        // }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure("Invalid JSON response")
            }
            
            guard let isValid = json["valid"] as? Bool else {
                return .failure("Missing 'valid' field in response")
            }
            
            if !isValid {
                let message = json["error"] as? String ?? "Receipt validation failed"
                return .failure(message)
            }
            
            let productID = json["product_id"] as? String
            let originalTransactionID = json["original_transaction_id"] as? String
            
            var expirationDate: Date?
            if let expirationString = json["expiration_date"] as? String {
                let formatter = ISO8601DateFormatter()
                expirationDate = formatter.date(from: expirationString)
            }
            
            var environment: ReceiptValidationResult.ReceiptEnvironment = .unknown
            if let envString = json["environment"] as? String {
                environment = ReceiptValidationResult.ReceiptEnvironment(rawValue: envString) ?? .unknown
            }
            
            return .success(
                productID: productID ?? "",
                expirationDate: expirationDate,
                originalTransactionID: originalTransactionID,
                environment: environment
            )
            
        } catch {
            return .failure("Failed to parse server response: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Subscription Sync
    
    /// Sync subscription status with validation
    /// Call this on app launch and periodically to ensure subscription status is accurate
    public func syncSubscriptionStatus() async {
        let result = await validateSubscription()
        
        await MainActor.run {
            if result.isValid,
               let productID = result.productID,
               let subscriptionProduct = SubscriptionProductID(rawValue: productID) {
                // Update subscription tier based on validated product
                SubscriptionManager.shared.setTier(subscriptionProduct.tier)
                
                #if DEBUG
                print("[Receipt] Subscription synced: \(subscriptionProduct.tier.displayName)")
                if let expiry = result.expirationDate {
                    print("[Receipt] Expires: \(expiry)")
                }
                #endif
            } else if !SubscriptionManager.shared.isDeveloperMode {
                // No valid subscription and not in developer mode - reset to free
                SubscriptionManager.shared.setTier(.free)
                
                #if DEBUG
                print("[Receipt] No valid subscription, reset to Free tier")
                #endif
            }
        }
    }
}

// MARK: - App Launch Integration

extension ReceiptValidator {
    /// Call this from your App's init or AppDelegate to validate on launch
    public func validateOnLaunch() {
        Task {
            await syncSubscriptionStatus()
        }
    }
}

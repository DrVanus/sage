//
//  CrashReportingService.swift
//  CryptoSage
//
//  Crash reporting and error tracking service.
//  Uses Sentry for production crash reporting when SDK is installed.
//

import Foundation
import os.log

// MARK: - Crash Reporting Service

/// Service for crash reporting and error tracking.
/// Wraps Sentry SDK for production use.
public final class CrashReportingService: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = CrashReportingService()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "ai.cryptosage", category: "Crashes")
    private var isInitialized = false
    
    /// User defaults key for crash reporting opt-in
    private let crashReportingEnabledKey = "CrashReporting.Enabled"
    
    /// Whether crash reporting is enabled by user
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: crashReportingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: crashReportingEnabledKey) }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Default to enabled for new users
        if UserDefaults.standard.object(forKey: crashReportingEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: crashReportingEnabledKey)
        }
    }
    
    // MARK: - Setup
    
    /// Initialize crash reporting. Call this early in app startup.
    public func setup() {
        guard !isInitialized else { return }
        guard isEnabled else {
            logger.info("Crash reporting disabled by user")
            return
        }
        
        #if canImport(Sentry)
        configureSentry()
        #else
        logger.info("Sentry SDK not available - crash reporting will log locally only")
        #endif
        
        isInitialized = true
        logger.info("Crash reporting initialized")
    }
    
    // MARK: - Sentry Configuration
    
    private func configureSentry() {
        #if canImport(Sentry)
        import Sentry
        
        SentrySDK.start { options in
            // Replace with your Sentry DSN from sentry.io
            options.dsn = "YOUR_SENTRY_DSN_HERE"
            
            // Enable performance monitoring
            options.tracesSampleRate = 0.2  // 20% of transactions
            
            // Attach screenshots to errors (optional)
            options.attachScreenshot = true
            
            // Enable profiling for performance analysis
            options.profilesSampleRate = 0.1  // 10% of transactions
            
            // Environment
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            
            // Release version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                options.releaseName = "ai.cryptosage@\(version)+\(build)"
            }
            
            // Don't send PII
            options.sendDefaultPii = false
        }
        #endif
    }
    
    // MARK: - Error Capture
    
    /// Capture a non-fatal error
    /// - Parameters:
    ///   - error: The error to report
    ///   - context: Additional context about where the error occurred
    public func captureError(_ error: Error, context: String? = nil) {
        guard isEnabled else { return }
        
        var extras: [String: Any] = [:]
        if let context = context {
            extras["context"] = context
        }
        
        #if DEBUG
        logger.error("Captured error: \(error.localizedDescription) context: \(context ?? "none")")
        #endif
        
        #if canImport(Sentry)
        import Sentry
        
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                scope.setContext(value: ["location": context], key: "app_context")
            }
        }
        #endif
    }
    
    /// Capture a message (for non-exception issues)
    /// - Parameters:
    ///   - message: The message to report
    ///   - level: Severity level
    public func captureMessage(_ message: String, level: CrashSeverity = .info) {
        guard isEnabled else { return }
        
        #if DEBUG
        logger.log(level: level.osLogLevel, "\(message)")
        #endif
        
        #if canImport(Sentry)
        import Sentry
        
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level.sentryLevel)
        }
        #endif
    }
    
    // MARK: - Breadcrumbs
    
    /// Add a breadcrumb for debugging crash reports
    /// - Parameters:
    ///   - category: Category of the breadcrumb (e.g., "navigation", "user_action")
    ///   - message: Description of what happened
    ///   - data: Additional data
    public func addBreadcrumb(category: String, message: String, data: [String: Any]? = nil) {
        guard isEnabled else { return }
        
        #if DEBUG
        let dataStr = data?.description ?? ""
        logger.debug("Breadcrumb [\(category)]: \(message) \(dataStr)")
        #endif
        
        #if canImport(Sentry)
        import Sentry
        
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category
        breadcrumb.message = message
        breadcrumb.level = .info
        if let data = data {
            breadcrumb.data = data
        }
        SentrySDK.addBreadcrumb(breadcrumb)
        #endif
    }
    
    // MARK: - User Context
    
    /// Set anonymous user ID for crash correlation (no PII)
    /// - Parameter userID: Anonymous user identifier
    public func setAnonymousUserID(_ userID: String) {
        guard isEnabled else { return }
        
        #if canImport(Sentry)
        import Sentry
        
        let user = User()
        user.userId = userID
        SentrySDK.setUser(user)
        #endif
    }
    
    /// Clear user context (e.g., on sign out)
    public func clearUserContext() {
        #if canImport(Sentry)
        import Sentry
        
        SentrySDK.setUser(nil)
        #endif
    }
    
    // MARK: - Performance Monitoring
    
    /// Start a performance transaction
    /// - Parameters:
    ///   - name: Transaction name (e.g., "LoadMarketData")
    ///   - operation: Operation type (e.g., "http.request", "ui.load")
    /// - Returns: A transaction handle to finish later
    public func startTransaction(name: String, operation: String) -> Any? {
        guard isEnabled else { return nil }
        
        #if canImport(Sentry)
        import Sentry
        
        return SentrySDK.startTransaction(name: name, operation: operation)
        #else
        return nil
        #endif
    }
    
    /// Finish a performance transaction
    /// - Parameter transaction: The transaction handle from startTransaction
    public func finishTransaction(_ transaction: Any?) {
        #if canImport(Sentry)
        import Sentry
        
        if let span = transaction as? Span {
            span.finish()
        }
        #endif
    }
}

// MARK: - Crash Severity

public enum CrashSeverity {
    case debug
    case info
    case warning
    case error
    case fatal
    
    var osLogLevel: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
    
    #if canImport(Sentry)
    var sentryLevel: SentryLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        }
    }
    #endif
}

// MARK: - Convenience Extensions

extension Error {
    /// Report this error to crash reporting
    public func report(context: String? = nil) {
        CrashReportingService.shared.captureError(self, context: context)
    }
}

// MARK: - Sentry Stubs (for compilation without package)

#if !canImport(Sentry)
/// Stub types for compilation without Sentry SDK
private enum SentrySDK {
    static func start(configureOptions: (SentryOptions) -> Void) {}
    static func capture(error: Error, block: ((SentryScope) -> Void)? = nil) {}
    static func capture(message: String, block: ((SentryScope) -> Void)? = nil) {}
    static func addBreadcrumb(_ breadcrumb: Breadcrumb) {}
    static func setUser(_ user: User?) {}
    static func startTransaction(name: String, operation: String) -> Any? { nil }
}

private class SentryOptions {
    var dsn: String = ""
    var tracesSampleRate: NSNumber = 0
    var attachScreenshot: Bool = false
    var profilesSampleRate: NSNumber = 0
    var environment: String = ""
    var releaseName: String = ""
    var sendDefaultPii: Bool = false
}

private class SentryScope {
    func setContext(value: [String: Any], key: String) {}
    func setLevel(_ level: SentryLevel) {}
}

private enum SentryLevel {
    case debug, info, warning, error, fatal
}

private class Breadcrumb {
    var category: String = ""
    var message: String = ""
    var level: SentryLevel = .info
    var data: [String: Any]?
}

private class User {
    var userId: String = ""
}

private protocol Span {
    func finish()
}
#endif

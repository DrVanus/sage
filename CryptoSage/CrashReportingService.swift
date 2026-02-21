//
//  CrashReportingService.swift
//  CryptoSage
//
//  Crash reporting and error tracking service.
//  Uses Sentry for production crash reporting when SDK is installed.
//

import Foundation
import os.log

// Conditionally import Sentry if available
#if canImport(Sentry)
import Sentry
private let sentryAvailable = true
#else
private let sentryAvailable = false
#endif

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
    
    /// Sentry DSN - Configure this with your project's DSN from https://sentry.io
    /// Leave empty or as placeholder to disable Sentry (local logging will still work)
    private let sentryDSN: String? = {
        // SETUP: Replace with your Sentry DSN from https://sentry.io
        // 1. Create a project at sentry.io
        // 2. Get the DSN from Project Settings -> Client Keys (DSN)
        // 3. Add Swift Package: https://github.com/getsentry/sentry-cocoa
        // 4. Replace the placeholder below with your DSN
        let dsn = ""  // ⚠️ PRODUCTION: Set your Sentry DSN here before App Store release (https://sentry.io)
        return dsn.isEmpty || dsn.contains("YOUR_") ? nil : dsn
    }()
    
    private func configureSentry() {
        #if canImport(Sentry)
        // Skip Sentry initialization if DSN is not configured
        guard let dsn = sentryDSN else {
            logger.info("Sentry DSN not configured - using local crash logging only")
            return
        }
        
        SentrySDK.start { options in
            options.dsn = dsn
            
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
        logger.info("Sentry crash reporting configured")
        #endif
    }
    
    // MARK: - Error Capture
    
    /// Capture a non-fatal error
    /// - Parameters:
    ///   - error: The error to report
    ///   - context: Additional context about where the error occurred
    public func captureError(_ error: Error, context: String? = nil) {
        guard isEnabled else { return }
        
        #if DEBUG
        logger.error("Captured error: \(error.localizedDescription) context: \(context ?? "none")")
        #endif
        
        #if canImport(Sentry)
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
        let user = User()
        user.userId = userID
        SentrySDK.setUser(user)
        #endif
    }
    
    /// Clear user context (e.g., on sign out)
    public func clearUserContext() {
        #if canImport(Sentry)
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
        return SentrySDK.startTransaction(name: name, operation: operation)
        #else
        return nil
        #endif
    }
    
    /// Finish a performance transaction
    /// - Parameter transaction: The transaction handle from startTransaction
    public func finishTransaction(_ transaction: Any?) {
        #if canImport(Sentry)
        if let span = transaction as? Span {
            span.finish()
        }
        #endif
    }
    
    // MARK: - Non-Fatal Event Logging
    
    /// Log a non-fatal event for telemetry and diagnostics
    /// Use this for tracking issues that don't crash the app but indicate problems
    /// - Parameters:
    ///   - name: Event name (e.g., "LayoutAnomalyRecovery", "CacheCorruption")
    ///   - attributes: Additional data about the event
    public func logNonFatalEvent(name: String, attributes: [String: String] = [:]) {
        guard isEnabled else { return }
        
        #if DEBUG
        let attrStr = attributes.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        logger.info("📊 Non-fatal event: \(name) [\(attrStr)]")
        #endif
        
        // Add as breadcrumb for crash correlation
        addBreadcrumb(category: "event", message: name, data: attributes)
        
        #if canImport(Sentry)
        // Capture as an informational message with context
        SentrySDK.capture(message: "Event: \(name)") { scope in
            scope.setLevel(.info)
            scope.setContext(value: attributes, key: "event_attributes")
            scope.setTag(value: name, key: "event_type")
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

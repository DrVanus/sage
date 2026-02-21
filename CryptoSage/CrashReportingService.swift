//
//  CrashReportingService.swift
//  CryptoSage
//
//  Crash reporting and error tracking service.
//  Uses Firebase Crashlytics for production crash reporting.
//

import Foundation
import os.log
import FirebaseCrashlytics

// MARK: - Crash Reporting Service

/// Service for crash reporting and error tracking.
/// Wraps Firebase Crashlytics for production use.
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
        set {
            UserDefaults.standard.set(newValue, forKey: crashReportingEnabledKey)
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(newValue)
        }
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
    /// Firebase must already be configured via FirebaseApp.configure() before calling this.
    public func setup() {
        guard !isInitialized else { return }
        guard isEnabled else {
            logger.info("Crash reporting disabled by user")
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            return
        }

        // Crashlytics is automatically initialized when Firebase is configured.
        // Ensure collection is enabled based on user preference.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        isInitialized = true
        logger.info("Firebase Crashlytics initialized")
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

        if let context = context {
            Crashlytics.crashlytics().log("Context: \(context)")
        }
        Crashlytics.crashlytics().record(error: error)
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

        Crashlytics.crashlytics().log("[\(level)] \(message)")
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

        let dataStr = data?.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
        Crashlytics.crashlytics().log("[\(category)] \(message) \(dataStr)")
    }

    // MARK: - User Context

    /// Set anonymous user ID for crash correlation (no PII)
    /// - Parameter userID: Anonymous user identifier
    public func setAnonymousUserID(_ userID: String) {
        guard isEnabled else { return }
        Crashlytics.crashlytics().setUserID(userID)
    }

    /// Clear user context (e.g., on sign out)
    public func clearUserContext() {
        Crashlytics.crashlytics().setUserID("")
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

        // Record as a custom non-fatal error
        let userInfo = attributes.isEmpty ? [String: String]() : attributes
        let error = NSError(
            domain: "ai.cryptosage.event",
            code: 0,
            userInfo: userInfo.merging(
                [NSLocalizedDescriptionKey: name],
                uniquingKeysWith: { _, new in new }
            )
        )
        Crashlytics.crashlytics().record(error: error)
    }
}

// MARK: - Crash Severity

public enum CrashSeverity: CustomStringConvertible {
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

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }
}

// MARK: - Convenience Extensions

extension Error {
    /// Report this error to crash reporting
    public func report(context: String? = nil) {
        CrashReportingService.shared.captureError(self, context: context)
    }
}

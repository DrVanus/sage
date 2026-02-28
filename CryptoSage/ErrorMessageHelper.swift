//
//  ErrorMessageHelper.swift
//  CryptoSage
//
//  User-friendly error message conversion for common API and network errors
//  App Store polish: Better error messages improve user experience
//

import Foundation

/// Converts technical errors into user-friendly messages with actionable guidance
enum ErrorMessageHelper {

    /// Convert any error into a user-friendly message with recovery suggestion
    static func userFriendlyMessage(for error: Error) -> (message: String, suggestion: String?) {
        // Check for specific error types
        if let cryptoError = error as? CryptoAPIError {
            return cryptoAPIMessage(for: cryptoError)
        }

        // Check for URL/Network errors
        if let urlError = error as? URLError {
            return urlErrorMessage(for: urlError)
        }

        // Check for decoding errors
        if error is DecodingError {
            return (
                message: "Unable to process server data",
                suggestion: "This may be a temporary issue. Please try refreshing."
            )
        }

        // Generic fallback
        let localizedMessage = error.localizedDescription

        // Provide context-specific suggestions based on error message keywords
        if localizedMessage.localizedCaseInsensitiveContains("network") ||
           localizedMessage.localizedCaseInsensitiveContains("connection") {
            return (
                message: "Network connection issue",
                suggestion: "Please check your internet connection and try again."
            )
        }

        if localizedMessage.localizedCaseInsensitiveContains("timeout") {
            return (
                message: "Request timed out",
                suggestion: "The server is taking too long to respond. Please try again."
            )
        }

        // Return the localized error message
        return (
            message: localizedMessage,
            suggestion: "Please try again in a moment."
        )
    }

    /// Convert CryptoAPIError to user-friendly message
    private static func cryptoAPIMessage(for error: CryptoAPIError) -> (message: String, suggestion: String?) {
        return (
            message: error.errorDescription ?? "API error occurred",
            suggestion: error.recoverySuggestion
        )
    }

    /// Convert URLError to user-friendly message with specific guidance
    private static func urlErrorMessage(for error: URLError) -> (message: String, suggestion: String?) {
        switch error.code {
        case .notConnectedToInternet:
            return (
                message: "No internet connection",
                suggestion: "Please connect to WiFi or cellular data and try again."
            )

        case .timedOut:
            return (
                message: "Request timed out",
                suggestion: "The server is taking too long to respond. Please try again."
            )

        case .cannotFindHost, .cannotConnectToHost:
            return (
                message: "Cannot reach server",
                suggestion: "Please check your internet connection or try again later."
            )

        case .networkConnectionLost:
            return (
                message: "Connection was lost",
                suggestion: "Your network connection was interrupted. Please try again."
            )

        case .badURL, .unsupportedURL:
            return (
                message: "Invalid request",
                suggestion: "There's a problem with the request. Please contact support if this persists."
            )

        case .badServerResponse:
            return (
                message: "Server error",
                suggestion: "The server returned an invalid response. Please try again later."
            )

        case .dataNotAllowed:
            return (
                message: "Data not allowed",
                suggestion: "Check your device settings to allow data usage for this app."
            )

        default:
            return (
                message: "Network error occurred",
                suggestion: "Please check your connection and try again."
            )
        }
    }

    /// Format error for display in UI with emoji and proper spacing
    static func formatForDisplay(message: String, suggestion: String?) -> String {
        var display = "⚠️ \(message)"
        if let suggestion = suggestion {
            display += "\n\n💡 \(suggestion)"
        }
        return display
    }

    /// Quick check if error is network-related
    static func isNetworkError(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let cryptoError = error as? CryptoAPIError {
            switch cryptoError {
            case .networkUnavailable, .badServerResponse:
                return true
            default:
                return false
            }
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("network") ||
               message.contains("connection") ||
               message.contains("internet")
    }

    /// Quick check if error is likely temporary and user should retry
    static func shouldSuggestRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }

        if let cryptoError = error as? CryptoAPIError {
            switch cryptoError {
            case .rateLimited, .badServerResponse, .networkUnavailable:
                return true
            default:
                return false
            }
        }

        return false
    }
}

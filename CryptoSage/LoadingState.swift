//
//  LoadingState.swift
//  CryptoSage
//
//  Created by DM on 6/3/25.
//


// LoadingState.swift
import Foundation

enum LoadingState<Success> {
    case idle
    case loading
    case success(Success)
    case failure(String)

    // MARK: - Convenience Properties

    /// Returns true if the state is currently loading
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Returns the success value if available, nil otherwise
    var value: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// Returns the error message if in failure state, nil otherwise
    var errorMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }

    /// Returns true if state is success
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Returns true if state is failure
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    /// Returns true if state is idle
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

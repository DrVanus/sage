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
}
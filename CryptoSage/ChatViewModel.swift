//
//  ChatViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/30/25.
//

import Foundation

/// Lightweight shared state for AI chat input.
///
/// Multiple views across the app (HomeView, PremiumNewsSection, AllCryptoNewsView,
/// BookmarksView) set `inputText` to pre-fill the AI chat when navigating to the
/// AI tab. The actual conversation management, message history, and AI service
/// calls are handled by `AITabView` directly.
final class ChatViewModel: ObservableObject {
    /// The current user input text bound to the chat text field.
    /// Other views can set this to pre-fill the AI chat input before switching tabs.
    @Published var inputText: String = ""
}

//
//  ChatViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/30/25.
//


import Foundation
import Combine

/// ViewModel for managing AI chat interactions
final class ChatViewModel: ObservableObject {
    /// The current user input text bound to the chat text field
    @Published var inputText: String = ""

    /// The list of chat messages exchanged
    @Published var messages: [ChatMessage] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        // TODO: Load previous conversation history if needed
    }

    /// Send the current inputText as a new message
    func sendMessage() {
        let userMessage = ChatMessage(
            id: UUID(),
            sender: "user",
            text: inputText,
            timestamp: Date(),
            isError: false
        )
        messages.append(userMessage)
        let prompt = userMessage.text
        inputText = ""

        // TODO: Call your AI/chat service with `prompt`, then append response
        // Example mock response:
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            let aiResponse = ChatMessage(
                id: UUID(),
                sender: "ai",
                text: "AI response to: \(prompt)",
                timestamp: Date(),
                isError: false
            )
            self.messages.append(aiResponse)
        })
    }
}

//
//  UtilityViews.swift
//  CSAI1
//
//  Reusable UI components only (no ChatMessage/ChatBubble).
//

import SwiftUI

// MARK: - Generic Card View
struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(UIColor.secondarySystemBackground))
            .overlay(content)
            .padding()
    }
}

// MARK: - Simple Trending Card
struct TrendingCard: View {
    var coin: String
    
    var body: some View {
        CardView {
            Text("Trending: \(coin)")
                .font(.headline)
        }
    }
}

// ---------- NO ChatMessage or ChatBubble here! ----------

// MARK: - State Deferral Helper

/// Safely defers a state modification to the next run loop iteration.
/// Use this in SwiftUI view modifiers (onChange, onReceive, onAppear) to avoid
/// "Modifying state during view update" warnings.
///
/// Unlike `DispatchQueue.main.async { }`, `DispatchQueue.main.async` guarantees
/// execution on the next run loop when already on the main thread.
@MainActor
func deferredStateUpdate(_ action: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
        action()
    }
}

/// Safely defers a state modification with animation to the next run loop iteration.
@MainActor
func deferredAnimatedStateUpdate(animation: Animation? = .default, _ action: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
        if let animation = animation {
            withAnimation(animation) {
                action()
            }
        } else {
            action()
        }
    }
}

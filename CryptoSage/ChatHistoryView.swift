//
//  ChatHistoryView.swift
//  CSAI1
//
//  A custom sheet-based history view with a bubble layout
//  and a pull-to-dismiss style (iOS 16+).
//

import SwiftUI

struct ChatHistoryView: View {
    let messages: [ChatMessage]
    
    // Allows us to dismiss this sheet programmatically
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Adaptive background gradient
    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.97),
                    Color(red: 0.94, green: 0.95, blue: 0.96)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // Adaptive AI bubble gradient
    private var aiBubbleGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.5, green: 0.5, blue: 0.5, opacity: 0.4),
                    Color(red: 0.6, green: 0.6, blue: 0.6, opacity: 0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.94, green: 0.94, blue: 0.94),
                    Color(red: 0.88, green: 0.88, blue: 0.88)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient - adaptive to color scheme
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom top bar with a grab indicator + title + close button
                topBar()
                
                // Scrollable bubble layout
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            messageRow(for: msg)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.top)
                }
            }
        }
    }
    
    // MARK: - Custom Top Bar
    private func topBar() -> some View {
        VStack(spacing: 6) {
            // A small grab indicator at top center
            RoundedRectangle(cornerRadius: 2)
                .fill(DS.Adaptive.textSecondary)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            
            HStack {
                Text("Chat History")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(DS.Adaptive.background.opacity(0.5))
    }
    
    // MARK: - Each Message Row
    private func messageRow(for msg: ChatMessage) -> some View {
        HStack {
            if msg.sender == "ai" {
                bubbleView(msg)
                Spacer(minLength: 10)
            } else {
                Spacer(minLength: 10)
                bubbleView(msg)
            }
        }
    }
    
    // MARK: - Bubble Style
    private func bubbleView(_ msg: ChatMessage) -> some View {
        let isAI = (msg.sender == "ai")
        // AI text adapts to color scheme, user text is always black on gold
        let textColor: Color = isAI ? DS.Adaptive.textPrimary : Color.black.opacity(0.9)
        
        return VStack(alignment: .leading, spacing: 6) {
            // The main message text
            Text(msg.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(textColor)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    Group {
                        if msg.isError {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(errorBubbleGradient)
                        } else if isAI {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(aiBubbleGradient)
                        } else {
                            // Premium user bubble with gloss
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(BrandColors.goldVertical)
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.28), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            msg.isError ? Color.red.opacity(0.5) : (isAI ? DS.Adaptive.stroke : BrandColors.goldLight.opacity(0.6)),
                            lineWidth: isAI ? 1 : 0.8
                        )
                )
            
            // Optional timestamp
            Text("\(formattedDate(msg.timestamp))")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.leading, 4)
        }
    }
    
    // MARK: - Helper: Format Date
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - Bubble Gradients
    private let errorBubbleGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.red.opacity(0.4),
            Color.red.opacity(0.8)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

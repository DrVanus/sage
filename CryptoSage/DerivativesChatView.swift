//
//  DerivativesChatView.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI
import UIKit

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

// Custom shape to round specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct DerivativesChatView: View {
    @ObservedObject var viewModel: DerivativesBotViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var messageText = ""

    @State private var didInitialScroll: Bool = false
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.chatMessages) { msg in
                        DerivativesChatBubble(message: msg)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                    
                    // Typing indicator with smooth transition
                    if viewModel.isTyping {
                        DerivativesTypingIndicator()
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }
                    
                    // Bottom anchor
                    Color.clear.frame(height: 8)
                        .id("chat_bottom")
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .animation(.easeOut(duration: 0.2), value: viewModel.isTyping)
                .animation(.easeOut(duration: 0.15), value: viewModel.chatMessages.count)
            }
            .defaultScrollAnchor(.bottom) // iOS 17+ - Start scroll position at bottom for chat UX
            .background(DS.Adaptive.background)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // Dismiss keyboard when tapping on the scroll area
                UIApplication.shared.dismissKeyboard()
            }
            .onAppear {
                // Only perform initial scroll if not already done
                guard !didInitialScroll else { return }
                
                // Two-stage scroll for reliable initial positioning
                // Stage 1: Immediate scroll
                if let lastMessage = viewModel.chatMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
                
                // Stage 2: Short delay for content layout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let lastMessage = viewModel.chatMessages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
                
                // Stage 3: Fallback for complex layouts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let lastMessage = viewModel.chatMessages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                    didInitialScroll = true
                }
            }
            .onChange(of: viewModel.chatMessages.count) { _, _ in
                // Only animate scroll for new messages after initial load
                guard didInitialScroll else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    if let lastMessage = viewModel.chatMessages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // Generate Config button
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    UIApplication.shared.dismissKeyboard()
                    viewModel.generateDerivativesConfig()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Generate Bot Config")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    // LIGHT MODE FIX: Adaptive text color
                    .foregroundColor(colorScheme == .dark ? .black : .white.opacity(0.95))
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Input bar
                DerivativesChatInputBar(text: $messageText) { text in
                    viewModel.sendChatMessage(text)
                }
            }
            .background(DS.Adaptive.background)
            // Prevent bouncy keyboard animation - use smooth linear animation
            .animation(.linear(duration: 0.25), value: messageText.isEmpty)
        }
        // Critical: Disable implicit animations on the safeAreaInset container to prevent overshoot
        .transaction { transaction in
            transaction.animation = .easeOut(duration: 0.25)
        }
    }
}

// MARK: - Derivatives Chat Bubble (Aligned with main AI chat styling)
struct DerivativesChatBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer(minLength: 50)
                userBubble
            } else {
                aiBubble
                Spacer(minLength: 50)
            }
        }
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(message.text)
                .font(.system(size: 15))
                // LIGHT MODE FIX: Adaptive text color on gold bubble
                .foregroundColor(isDark ? Color.black.opacity(0.9) : Color(red: 0.30, green: 0.22, blue: 0.02))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(timeFormatter.string(from: message.timestamp))
                .font(.system(size: 10))
                .foregroundColor(isDark ? Color.black.opacity(0.6) : Color(red: 0.45, green: 0.35, blue: 0.10).opacity(0.7))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            ZStack {
                // Base gold gradient - LIGHT MODE FIX: Warm amber in light mode
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isDark
                            ? BrandColors.goldVertical
                            : LinearGradient(
                                colors: [Color(red: 0.96, green: 0.88, blue: 0.65), Color(red: 0.92, green: 0.82, blue: 0.52)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                // Top gloss highlight for premium feel
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.28 : 0.40), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isDark ? BrandColors.goldLight.opacity(0.6) : Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.35),
                    lineWidth: isDark ? 0.8 : 0.5
                )
        )
    }
    
    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI Avatar - LIGHT MODE FIX: Adaptive gold tones
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.1)]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15), Color(red: 0.65, green: 0.48, blue: 0.06).opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Typing Indicator (Gold dots matching AI chat styling)
struct DerivativesTypingIndicator: View {
    @State private var dotPhase: Int = 0
    @State private var animationTimer: Timer? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI Avatar (same as bubble) - LIGHT MODE FIX: Adaptive
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.1)]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15), Color(red: 0.65, green: 0.48, blue: 0.06).opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            }
            
            // Animated dots - LIGHT MODE FIX: Deeper amber dots
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            isDark
                                ? BrandColors.goldLight.opacity(dotPhase == index ? 1.0 : 0.35)
                                : Color(red: 0.78, green: 0.60, blue: 0.10).opacity(dotPhase == index ? 1.0 : 0.30)
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPhase == index ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.35), value: dotPhase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isDark ? BrandColors.goldLight.opacity(0.25) : Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15),
                                lineWidth: isDark ? 1 : 0.5
                            )
                    )
            )
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            DispatchQueue.main.async {
                dotPhase = (dotPhase + 1) % 3
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Chat Input Bar (Aligned with main AI chat styling)
struct DerivativesChatInputBar: View {
    @Binding var text: String
    var placeholder: String = "Ask about derivatives..."
    var onSend: (String) -> Void
    @State private var isEditing: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Text field - using UIKit-backed ChatTextField for reliable keyboard
            ChatTextField(text: $text, placeholder: placeholder)
                .onSubmit {
                    submitMessage()
                }
                .onEditingChanged { editing in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isEditing = editing
                    }
                }
                .frame(height: 42)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(
                            isEditing ? BrandColors.goldLight.opacity(0.6) : DS.Adaptive.stroke,
                            lineWidth: isEditing ? 1.5 : 1
                        )
                )
                .animation(.easeOut(duration: 0.15), value: isEditing)
            
            // Circular send button matching main AI chat
            Button {
                submitMessage()
            } label: {
                ZStack {
                    // LIGHT MODE FIX: Deeper amber send button in light mode
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? BrandColors.goldVertical
                                : LinearGradient(
                                    colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .frame(width: 36, height: 36)
                    
                    // Glass highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.3 : 0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        // LIGHT MODE FIX: White icon on darker gold
                        .foregroundColor(colorScheme == .dark ? .black.opacity(0.9) : .white.opacity(0.95))
                }
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .scaleEffect(canSend ? 1.0 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            DS.Adaptive.background
                .overlay(
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }
    
    private func submitMessage() {
        guard canSend else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        onSend(text)
        text = ""
        UIApplication.shared.dismissKeyboard()
    }
}

struct DerivativesChatView_Previews: PreviewProvider {
    static var previews: some View {
        DerivativesChatView(viewModel: DerivativesBotViewModel())
    }
}

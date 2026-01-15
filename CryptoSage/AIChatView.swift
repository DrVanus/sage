//
//  AIChatView.swift
//  CryptoSage
//
//  Main AI Chat tab with conversations, quick replies, and input bar.
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Brand Gold Palette (single source of truth for AI tab)
private enum BrandGold {
    // Unified to centralized BrandColors (Classic Gold)
    static let light = BrandColors.goldLight
    static let dark  = BrandColors.goldBase
    static var horizontalGradient: LinearGradient { BrandColors.goldDiagonalGradient }
    static var verticalGradient: LinearGradient { BrandColors.goldVertical }
}

struct AITabView: View {
    // All stored conversations
    @State private var conversations: [Conversation] = []
    // Which conversation is currently active
    @State private var activeConversationID: UUID? = nil
    
    // Controls whether the history sheet is shown
    @State private var showHistory = false
    
    // Use shared ChatViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    // Portfolio data for AI context
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    // Whether the AI is "thinking" (processing a request)
    @State private var isThinking: Bool = false
    
    // Subscription management for prompt limits
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPromptLimitView: Bool = false
    
    @AppStorage("csai_show_prompt_bar") private var showPromptBar: Bool = true
    @AppStorage("csai_use_personalized_prompts") private var usePersonalizedPrompts: Bool = false
    @State private var isFetchingPersonalized: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showScrollHint: Bool = true
    @State private var isUserDragging: Bool = false
    @Namespace private var promptBarNamespace
    @FocusState private var inputFocused: Bool
    @State private var restorePromptBarAfterKeyboard: Bool = false

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingImages: [Data] = []
    @State private var topSafeInset: CGFloat = 0
    @State private var bottomSafeInset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    private let headerBarHeight: CGFloat = 52
    private let tabBarHeight: CGFloat = 64
    private let headerDrop: CGFloat = 16 // how far below the very top the header sits
    private var headerHeight: CGFloat { topSafeInset + headerBarHeight }
    
    // Track if this tab is active (visible)
    @State private var isActiveTab: Bool = true
    @EnvironmentObject private var appState: AppState
    
    // Reuse a single ephemeral session for all OpenAI calls (reduces connection churn)
    private static let openAISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // A list of quick prompts for the chat
    private let masterPrompts: [String] = [
        // Portfolio-Connected (showcases live data integration)
        "How is my portfolio performing today?",
        "Is my portfolio well diversified?",
        "What's my biggest winner this week?",
        "Should I rebalance my portfolio?",
        "Which of my holdings has the best momentum?",
        // Market Intelligence
        "What's the current price of BTC?",
        "Give me the top gainers and losers today",
        "What are the top 10 coins by market cap?",
        "What's the Fear & Greed Index saying?",
        "Any major crypto news I should know?",
        // Trading/Action-Oriented
        "Should I buy or sell right now?",
        "What's the best time to buy crypto?",
        "How to minimize fees when trading?",
        "What's the difference between a limit and market order?",
        // Educational
        "Compare Ethereum and Bitcoin",
        "What is staking and how does it work?",
        "What is a stablecoin?",
        "Explain yield farming",
        "What's the best exchange for altcoins?"
    ]
    
    // Currently displayed quick replies
    @State private var quickReplies: [String] = []
    
    private let knownTickers: Set<String> = ["BTC","ETH","SOL","LTC","DOGE","RLC","ADA","XRP","BNB","AVAX","DOT","LINK","MATIC","ARB","OP","ATOM","NEAR","FTM","SUI","APT"]
    
    // The TabView already inserts our CustomTabBar using safeAreaInset at the app level.
    // Do not add an extra lift here, or we get a visible gap above the tab bar.
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var bottomLift: CGFloat { 0 }
    private let promptCount: Int = 3

    private let bottomAnchorID = "chat_bottom_anchor"
    
    // Heights for bottom components
    private let inputBarHeight: CGFloat = 54
    private let promptBarHeightExpanded: CGFloat = 42
    private let promptHandleHeight: CGFloat = 14  // Reduced for tighter collapsed state
    // Visual gap between the AI input bar and the app's custom tab bar
    private let bottomChatToTabBarGap: CGFloat = 8
    // Total height of the input bar container (prompt bar + input bar + padding)
    private var inputBarContainerHeight: CGFloat {
        let promptHeight = showPromptBar ? promptBarHeightExpanded : promptHandleHeight
        return 2 + promptHeight + inputBarHeight + 12 // top padding + prompt + input + bottom padding
    }
    // Dynamic bottom padding - enough to clear the input bar overlay
    private var bottomScrollPadding: CGFloat {
        inputBarContainerHeight + 8
    }
    
    // Computed: returns messages for the active conversation.
    private var currentMessages: [ChatMessage] {
        guard let activeID = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == activeID }) else {
            return []
        }
        return conversations[index].messages
    }
    
    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()
            chatBodyView
        }
        .accentColor(.white)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TopSafeKey.self, value: proxy.safeAreaInsets.top)
                    .preference(key: BottomSafeKey.self, value: proxy.safeAreaInsets.bottom)
            }
        )
        .onPreferenceChange(TopSafeKey.self) { value in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                self.topSafeInset = value
            }
        }
        .onPreferenceChange(BottomSafeKey.self) { value in
            DispatchQueue.main.async {
                self.bottomSafeInset = value
            }
        }
        .safeAreaInset(edge: .top) {
            ZStack(alignment: .bottomLeading) {
                // Black bar that also paints behind the status bar
                Color.black
                    .ignoresSafeArea(edges: .top)

                HStack(alignment: .center) {
                    // Left control
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showHistory.toggle()
                    } label: {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.92))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            .contentShape(Capsule())
                            .accessibilityLabel("Open Conversations")
                    }

                    Spacer(minLength: 8)

                    // Center title – gets its own column so it won't overlap controls
                    Text(activeConversationTitle())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.95))
                        .lineLimit(2)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 8)

                    // Invisible ghost button to balance width on the right
                    Button(action: {}) {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.92))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            .contentShape(Capsule())
                    }
                    .opacity(0)
                    .disabled(true)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(height: headerBarHeight + headerDrop)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerBarHeight + headerDrop)
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView(
                conversations: conversations,
                onSelectConversation: { convo in
                    activeConversationID = convo.id
                    showHistory = false
                    saveConversations()
                },
                onNewChat: {
                    let newConvo = Conversation(title: "Untitled Chat")
                    conversations.append(newConvo)
                    activeConversationID = newConvo.id
                    showHistory = false
                    saveConversations()
                },
                onDeleteConversation: { convo in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        conversations.remove(at: idx)
                        if convo.id == activeConversationID {
                            let fallback = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) })?.id
                            activeConversationID = fallback
                        }
                        saveConversations()
                    }
                },
                onRenameConversation: { convo, newTitle in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        conversations[idx].title = newTitle.isEmpty ? "Untitled Chat" : newTitle
                        saveConversations()
                    }
                },
                onTogglePin: { convo in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        conversations[idx].pinned.toggle()
                        saveConversations()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPromptLimitView) {
            AIPromptLimitView()
        }
        .onAppear {
            // Defer all state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                isActiveTab = (appState.selectedTab == .ai)
                loadConversations()
                // Restore last active conversation if available
                if let idString = UserDefaults.standard.string(forKey: lastActiveKey),
                   let uuid = UUID(uuidString: idString),
                   conversations.contains(where: { $0.id == uuid }) {
                    activeConversationID = uuid
                } else if activeConversationID == nil {
                    // Fallback: pick the most recently active conversation by last message or creation date
                    if let mostRecent = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) }) {
                        activeConversationID = mostRecent.id
                    }
                }
                randomizePrompts()
            }
            
            // Keyboard observers for tracking keyboard height (used for UI adjustments)
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
        }
        .onDisappear {
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                isActiveTab = false  // view is off-screen; stop local activity
            }
        }
        .onChange(of: activeConversationID) { _ in
            // The scroll launching is now managed in the scroll view .onChange itself
        }
        .onChange(of: inputFocused) { focused in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if focused && showPromptBar {
                    restorePromptBarAfterKeyboard = true
                    smoothTogglePromptBar(show: false)
                } else if !focused && restorePromptBarAfterKeyboard {
                    restorePromptBarAfterKeyboard = false
                    smoothTogglePromptBar(show: true)
                }
            }
        }
        .onChange(of: appState.selectedTab) { tab in
            DispatchQueue.main.async { isActiveTab = (tab == .ai) }
        }
    }
}

// MARK: - Subviews & Helpers
extension AITabView {
    private var chatBodyView: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Ensure content never peeks under the header
                            Color.clear.frame(height: 12)
                            ForEach(currentMessages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            // Show thinking indicator while AI is processing
                            if isThinking {
                                ThinkingBubble()
                                    .id("thinking_indicator")
                            }
                            // Bottom anchor - minimal padding
                            Color.clear
                                .frame(height: bottomScrollPadding)
                                .id(bottomAnchorID)
                        }
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .onTapGesture {
                        // Tap anywhere on chat area to dismiss keyboard (like iMessage)
                        inputFocused = false
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { _ in isUserDragging = true }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isUserDragging = false
                                }
                            }
                    )
                    .onAppear {
                        // Single consolidated scroll on initial load
                        DispatchQueue.main.async {
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                    .onChange(of: currentMessages.count) { _ in
                        // Only scroll to bottom for user messages (while thinking)
                        // AI responses are handled by onChange(of: isThinking)
                        DispatchQueue.main.async {
                            if !isUserDragging && isThinking {
                                scrollToBottom(proxy, animated: true)
                            }
                        }
                    }
                    .onChange(of: activeConversationID) { _ in
                        // Scroll when switching conversations
                        DispatchQueue.main.async {
                            if !isUserDragging { scrollToBottom(proxy, animated: false) }
                        }
                    }
                    .onChange(of: isThinking) { thinking in
                        DispatchQueue.main.async {
                            if !isUserDragging {
                                if thinking {
                                    // Scroll to show the thinking indicator
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        proxy.scrollTo("thinking_indicator", anchor: .bottom)
                                    }
                                } else {
                                    // AI response received - scroll to TOP of last message
                                    if let lastMsg = currentMessages.last {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            proxy.scrollTo(lastMsg.id, anchor: .top)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: showPromptBar) { _ in
                        DispatchQueue.main.async {
                            if !isUserDragging { scrollToBottom(proxy, animated: true) }
                        }
                    }
                }
            }
            
            if let toast = toastMessage {
                toastView(toast)
            }
            
            // Input bar at the bottom of the ZStack
            inputBarOverlay
        }
    }
    
    // MARK: - Input Bar Overlay
    private var inputBarOverlay: some View {
        VStack(spacing: 4) {
            // Remaining prompts indicator (only show for non-elite tiers)
            if subscriptionManager.currentTier != .elite && !subscriptionManager.isDeveloperMode {
                remainingPromptsIndicator
            }
            
            ZStack {
                quickReplyBar()
                    .opacity(showPromptBar ? 1 : 0)
                    .scaleEffect(showPromptBar ? 1 : 0.95, anchor: .bottom)
                    .allowsHitTesting(showPromptBar)
                collapsedPromptHandle()
                    .opacity(showPromptBar ? 0 : 1)
                    .scaleEffect(showPromptBar ? 0.95 : 1, anchor: .bottom)
                    .allowsHitTesting(!showPromptBar)
            }
            .frame(height: showPromptBar ? promptBarHeightExpanded : promptHandleHeight)
            .animation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0), value: showPromptBar)

            inputBar()
                .frame(height: inputBarHeight)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .overlay(alignment: .top) {
            // Subtle top separator line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, BrandGold.light.opacity(0.12), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            // Bottom separator above tab bar (only when keyboard hidden)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .opacity(keyboardHeight > 0 ? 0 : 1)
        }
        // Move input bar above keyboard when visible
        .offset(y: keyboardHeight > 0 ? -(keyboardHeight - tabBarHeight - 34) : 0)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }
    
    // MARK: - Remaining Prompts Indicator
    private var remainingPromptsIndicator: some View {
        let remaining = subscriptionManager.remainingAIPrompts
        let total = subscriptionManager.currentTier.aiPromptsPerDay
        let isLow = remaining <= 1 && remaining > 0
        let isEmpty = remaining == 0
        
        return HStack(spacing: 6) {
            Image(systemName: isEmpty ? "exclamationmark.circle.fill" : "message.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(isEmpty ? .orange : (isLow ? .yellow : BrandGold.light))
            
            Text(subscriptionManager.remainingPromptsDisplay)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isEmpty ? .orange : (isLow ? .yellow : .white.opacity(0.7)))
            
            if subscriptionManager.currentTier == .free {
                Button {
                    showPromptLimitView = true
                } label: {
                    Text("Upgrade")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(BrandGold.horizontalGradient)
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(isEmpty ? Color.orange.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func activeConversationTitle() -> String {
        guard let activeID = activeConversationID,
              let convo = conversations.first(where: { $0.id == activeID }) else {
            return "AI Chat"
        }
        return convo.title
    }
    
    private func thinkingIndicator() -> some View { GoldThinkingIndicator(active: (appState.selectedTab == .ai) && isThinking) }
    
    private func quickReplyBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Suggestion chips
                ForEach(Array(quickReplies.enumerated()), id: \.offset) { (_, reply) in
                    Button(reply) { handleQuickReply(reply) }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 15).fill(BrandGold.horizontalGradient).opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(BrandGold.light.opacity(0.55), lineWidth: 1))
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .disabled(isThinking)
                        .opacity(isThinking ? 0.5 : 1)
                }

                // Trailing controls - refresh and hide
                HStack(spacing: 6) {
                    // Refresh button
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        randomizePrompts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(BrandGold.horizontalGradient)
                                    .opacity(0.3)
                            )
                            .overlay(
                                Circle()
                                    .stroke(BrandGold.light.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Refresh suggestions")
                    
                    // Hide button
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        smoothTogglePromptBar(show: false)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(BrandGold.horizontalGradient)
                                    .opacity(0.3)
                            )
                            .overlay(
                                Circle()
                                    .stroke(BrandGold.light.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Hide suggestions bar")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .matchedGeometryEffect(id: "promptBG", in: promptBarNamespace, isSource: showPromptBar)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 36)
                .opacity(showScrollHint ? 1 : 0)
                .allowsHitTesting(false)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .animation(.spring(response: 0.35, dampingFraction: 0.88, blendDuration: 0.2), value: quickReplies)
        // Double-tap to refresh
        .onTapGesture(count: 2) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            randomizePrompts()
        }
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    if horizontal > vertical + 2 {
                        withAnimation(.easeInOut(duration: 0.2)) { showScrollHint = false }
                    }
                    if vertical > 10 && vertical > horizontal + 4 {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        #endif
                        smoothTogglePromptBar(show: false)
                    }
                }
        )
        // Long-press context menu
        .contextMenu {
            Button {
                randomizePrompts()
            } label: { Label("Refresh Suggestions", systemImage: "arrow.clockwise") }

            Button {
                smoothTogglePromptBar(show: false)
            } label: { Label("Hide Suggestions", systemImage: "chevron.down") }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if showPromptBar { scheduleScrollHintAutoHide() }
            }
        }
        .onChange(of: quickReplies) { _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if showPromptBar { scheduleScrollHintAutoHide() }
            }
        }
    }
    
    private func collapsedPromptHandle() -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            smoothTogglePromptBar(show: true)
        } label: {
            // Minimal thin gold bar indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [BrandGold.light.opacity(0.4), BrandGold.dark.opacity(0.6), BrandGold.light.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 36, height: 4)
                .shadow(color: BrandGold.light.opacity(0.25), radius: 4, x: 0, y: 0)
                .matchedGeometryEffect(id: "promptBG", in: promptBarNamespace, isSource: !showPromptBar)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        // Long-press for context menu
        .contextMenu {
            Button {
                smoothTogglePromptBar(show: true)
            } label: { Label("Show Suggestions", systemImage: "chevron.up") }
        }
        // Swipe up to expand
        .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local).onEnded { value in
            if value.translation.height < -12 {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                smoothTogglePromptBar(show: true)
            }
        })
    }
    
    private func smoothTogglePromptBar(show: Bool) {
        let delay = 0.05 // let the context menu dismiss first for a smoother morph
        // Use slightly bouncier animation when expanding for delight
        let anim: Animation = show
            ? .spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0)
            : .spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(anim) {
                self.showPromptBar = show
            }
        }
    }
    
    private func downscaleImageData(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled
    }
    
    private func inputBar() -> some View {
        HStack(spacing: 10) {
            // Photos picker - refined design
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "photo.on.rectangle.angled")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().stroke(BrandGold.light.opacity(0.25), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(BrandGold.horizontalGradient)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        )
                        .offset(x: 2, y: 2)
                }
                .contentShape(Circle())
            }
            .accessibilityLabel("Attach image")

            // If exactly one image is attached, show a compact chip next to the button
            if pendingImages.count == 1, let ui = UIImage(data: pendingImages[0]) {
                AttachmentChip(image: ui) {
                    pendingImages.removeAll()
                }
            }

            // If more than one image, show the horizontal strip
            if pendingImages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, data in
                            if let ui = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 34, height: 34)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BrandGold.light.opacity(0.3), lineWidth: 1))
                                    Button {
                                        pendingImages.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.black)
                                            .background(Circle().fill(Color.white))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                    }
                }
                .frame(height: 36)
            }

            // Text field - refined styling
            TextField("Ask your AI...", text: $chatVM.inputText)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(.white)                 // Cursor and selection color
                .accentColor(.white)          // Fallback for older iOS
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))  // Increased for better visibility
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            inputFocused
                                ? BrandGold.light.opacity(0.5)   // Gold highlight when focused
                                : (isThinking ? BrandGold.light.opacity(0.4) : Color.white.opacity(0.15)),
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isThinking)
                .animation(.easeInOut(duration: 0.15), value: inputFocused)
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit {
                    guard !isThinking else { return }
                    let trimmed = chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    self.sendMessage()
                }

            // Send button - refined styling
            let canSend = !isThinking && (!chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
            Button {
                guard canSend else { return }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                self.sendMessage()
            } label: {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandGold.verticalGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(BrandGold.light.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .onChange(of: selectedPhotoItem) { newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let processed = downscaleImageData(data) ?? data
                    await MainActor.run {
                        DispatchQueue.main.async {
                            self.pendingImages.append(processed)
                            self.showToast("Added photo. Tap Send to submit.")
                        }
                    }
                }
                await MainActor.run {
                    DispatchQueue.main.async { self.selectedPhotoItem = nil }
                }
            }
        }
    }
    
    private func maybeAugmentUserInput(_ input: String) async -> String {
        let lowercased = input.lowercased()
        
        // Detect trading advice questions - these need portfolio + sentiment context
        let tradingKeywords = ["buy", "sell", "should i", "invest", "trade", "hold", "rebalance", "allocation", "diversif"]
        let isTradingQuery = tradingKeywords.contains { lowercased.contains($0) }
        
        if isTradingQuery {
            // Inject portfolio summary for personalized advice
            let portfolioSummary = await buildQuickPortfolioContext()
            let marketSummary = await AIContextBuilder.shared.getMarketSummary()
            let sentimentSummary = await buildQuickSentimentContext()
            
            var context = "[YOUR PORTFOLIO: \(portfolioSummary)]"
            if !sentimentSummary.isEmpty {
                context += "\n[SENTIMENT: \(sentimentSummary)]"
            }
            if !marketSummary.isEmpty {
                context += "\n[MARKET: \(marketSummary)]"
            }
            return "\(input)\n\n\(context)\n\nIMPORTANT: Base your advice on MY specific portfolio and current market sentiment above. Reference my actual holdings, allocations, P/L, and factor in the Fear/Greed index."
        }
        
        // Add brief market context for queries about prices or market
        let marketKeywords = ["price", "worth", "value", "market", "btc", "eth", "bitcoin", "ethereum", "coin"]
        let isMarketQuery = marketKeywords.contains { lowercased.contains($0) }
        
        if isMarketQuery {
            let marketSummary = await AIContextBuilder.shared.getMarketSummary()
            if !marketSummary.isEmpty {
                return "\(input)\n\n[Current Market: \(marketSummary)]"
            }
        }
        
        return input
    }
    
    /// Build a quick sentiment summary for augmenting trading queries
    private func buildQuickSentimentContext() async -> String {
        let sentimentVM = await MainActor.run { ExtendedFearGreedViewModel.shared }
        
        guard let currentValue = await MainActor.run(body: { sentimentVM.currentValue }) else {
            return ""
        }
        
        let classification = await MainActor.run { sentimentVM.currentClassificationKey?.capitalized ?? "Unknown" }
        let delta1d = await MainActor.run { sentimentVM.delta1d }
        let bias = await MainActor.run { sentimentVM.bias }
        
        var parts: [String] = []
        parts.append("Fear/Greed: \(currentValue)/100 (\(classification))")
        
        if let d1d = delta1d {
            let sign = d1d >= 0 ? "+" : ""
            parts.append("24h: \(sign)\(d1d)")
        }
        
        let biasStr: String
        switch bias {
        case .bullish: biasStr = "Bullish"
        case .bearish: biasStr = "Bearish"
        case .neutral: biasStr = "Neutral"
        }
        parts.append("Bias: \(biasStr)")
        
        return parts.joined(separator: " | ")
    }
    
    /// Build a quick portfolio summary for augmenting trading queries
    private func buildQuickPortfolioContext() async -> String {
        let holdings = await MainActor.run { portfolioVM.holdings }
        let totalValue = await MainActor.run { portfolioVM.totalValue }
        
        guard !holdings.isEmpty else {
            return "Empty portfolio - no holdings yet"
        }
        
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        var parts: [String] = []
        
        // Total value
        parts.append("Total: $\(formatCompact(totalValue))")
        
        // Top holdings with allocation
        for holding in sortedHoldings.prefix(5) {
            let allocation = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
            let plPercent = holding.costBasis > 0 ? ((holding.currentPrice - holding.costBasis) / holding.costBasis) * 100 : 0
            let plSign = plPercent >= 0 ? "+" : ""
            parts.append("\(holding.coinSymbol): \(String(format: "%.1f", allocation))% (\(plSign)\(String(format: "%.1f", plPercent))% P/L)")
        }
        
        if holdings.count > 5 {
            parts.append("+\(holdings.count - 5) more")
        }
        
        return parts.joined(separator: " | ")
    }
    
    private func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func uploadImageToOpenAI(_ data: Data, filename: String = "image.jpg") async throws -> String {
        let session = AITabView.openAISession

        guard let url = URL(string: "https://api.openai.com/v1/files") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("assistants\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (respData, resp) = try await session.data(for: request)
        logResponse(respData, resp)

        struct UploadResponse: Codable { let id: String }
        let res = try JSONDecoder().decode(UploadResponse.self, from: respData)
        return res.id
    }
    
    private func withTimeout<T>(_ seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func sendMessage() {
        // Prevent multiple submissions while AI is processing
        guard !isThinking else { return }
        
        // Check AI prompt limit
        if !subscriptionManager.canSendAIPrompt {
            showPromptLimitView = true
            return
        }
        
        // Check if API key is configured
        if !APIConfig.hasValidOpenAIKey {
            showToast("Please configure your OpenAI API key in Settings")
            // Add a helpful message to the chat
            let ensuredIndex = ensureActiveConversation()
            var convo = conversations[ensuredIndex]
            let helpMsg = ChatMessage(
                sender: "ai",
                text: "To use CryptoSage AI, please add your OpenAI API key in Settings. You can get an API key from platform.openai.com.",
                isError: true
            )
            convo.messages.append(helpMsg)
            conversations[ensuredIndex] = convo
            saveConversations()
            return
        }
        
        // Ensure we have an active conversation index; create one if needed
        let ensuredIndex = ensureActiveConversation()

        let trimmed = chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingImages.isEmpty else { return }
        
        // Analytics: Track AI chat message sent
        AnalyticsService.shared.track(.aiChatMessageSent)

        var convo = conversations[ensuredIndex]

        if pendingImages.isEmpty {
            let userMsg = ChatMessage(sender: "user", text: trimmed)
            convo.messages.append(userMsg)
        } else {
            for (i, data) in pendingImages.enumerated() {
                let caption = (i == 0) ? trimmed : ""
                let userMsg = ChatMessage(sender: "user", text: caption, imageData: data)
                convo.messages.append(userMsg)
            }
        }

        if convo.title == "Untitled Chat" && convo.messages.count == 1 {
            let base = trimmed.isEmpty ? "Image" : trimmed
            convo.title = String(base.prefix(50))
        }

        conversations[ensuredIndex] = convo
        persistMessageImagesIfNeeded()
        chatVM.inputText = ""
        saveConversations()

        isThinking = true

        Task {
            do {
                let augmentedInput = (try? await withTimeout(2, operation: { await maybeAugmentUserInput(trimmed) })) ?? trimmed

                if pendingImages.isEmpty {
                    // Get the full AI response (thinking indicator shows during this)
                    let aiText = try await fetchAIResponse(for: augmentedInput)
                    
                    // Add the complete response to conversation and record prompt usage
                    await MainActor.run {
                        guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                        var updatedConvo = self.conversations[idx]
                        let aiMsg = ChatMessage(sender: "ai", text: aiText)
                        updatedConvo.messages.append(aiMsg)
                        self.conversations[idx] = updatedConvo
                        self.isThinking = false
                        self.saveConversations()
                        
                        // Record successful prompt usage
                        self.subscriptionManager.recordAIPromptUsage()
                    }
                } else {
                    // For images, use the legacy method with Assistants API for now
                    var fileIds: [String] = []
                    for data in pendingImages { fileIds.append(try await uploadImageToOpenAI(data, filename: "image.jpg")) }
                    let finalPrompt = augmentedInput.isEmpty ? "Analyze the attached image(s). If relevant to crypto/finance, call it out; otherwise describe them succinctly." : augmentedInput
                    let aiText = try await fetchAIResponseLegacy(for: finalPrompt, imageFileIds: fileIds)
                    await MainActor.run {
                        DispatchQueue.main.async {
                            guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                            var updatedConvo = self.conversations[idx]
                            let aiMsg = ChatMessage(sender: "ai", text: aiText)
                            updatedConvo.messages.append(aiMsg)
                            self.conversations[idx] = updatedConvo
                            self.isThinking = false
                            self.pendingImages.removeAll()
                            self.saveConversations()
                            
                            // Record successful prompt usage
                            self.subscriptionManager.recordAIPromptUsage()
                        }
                    }
                }
            } catch let error as AIServiceError {
                await MainActor.run {
                    guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                    var updatedConvo = self.conversations[idx]
                    let errMsg = ChatMessage(sender: "ai", text: error.errorDescription ?? "AI request failed", isError: true)
                    updatedConvo.messages.append(errMsg)
                    self.conversations[idx] = updatedConvo
                    self.isThinking = false
                    self.pendingImages.removeAll()
                    self.saveConversations()
                }
            } catch {
                await MainActor.run {
                    guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                    var updatedConvo = self.conversations[idx]
                    let errMsg = ChatMessage(sender: "ai", text: "AI request failed: \(error.localizedDescription)", isError: true)
                    updatedConvo.messages.append(errMsg)
                    self.conversations[idx] = updatedConvo
                    self.isThinking = false
                    self.pendingImages.removeAll()
                    self.saveConversations()
                }
            }
        }
    }
    
    /// Helper to ensure we have an active conversation
    private func ensureActiveConversation() -> Int {
        if let activeID = activeConversationID,
           let idx = conversations.firstIndex(where: { $0.id == activeID }) {
            return idx
        } else {
            let newConvo = Conversation(title: "Untitled Chat")
            conversations.append(newConvo)
            activeConversationID = newConvo.id
            saveConversations()
            return conversations.count - 1
        }
    }
    
    private func fetchAIResponse(for userInput: String, imageFileIds: [String] = []) async throws -> String {
        // Use the new AIService with Chat Completions API
        let aiService = AIService.shared
        
        // Inject current portfolio data into function tools
        await MainActor.run {
            AIFunctionTools.shared.updatePortfolio(
                holdings: portfolioVM.holdings,
                totalValue: portfolioVM.totalValue
            )
        }
        
        // Sync conversation history with AIService
        if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }) {
            let convoMessages = conversations[currentConvoIndex].messages
            aiService.setHistory(from: convoMessages)
        }
        
        // Build system prompt with portfolio context
        let systemPrompt = await AIContextBuilder.shared.buildSystemPrompt(portfolio: portfolioVM)
        
        // Detect if this is a trading advice query that needs the premium model
        // Premium model (gpt-4o) follows complex instructions better for personalized advice
        let lowercasedInput = userInput.lowercased()
        let tradingAdviceKeywords = ["should i buy", "should i sell", "should i hold", "should i invest", "what should i do", "buy or sell", "rebalance", "is it time to"]
        let isTradingAdviceQuery = tradingAdviceKeywords.contains { lowercasedInput.contains($0) }
        
        // If we have images, we need to handle them differently
        // For now, images are described in the prompt (Vision API integration can be added later)
        var finalInput = userInput
        if !imageFileIds.isEmpty {
            finalInput = "\(userInput)\n\n[Note: \(imageFileIds.count) image(s) attached - please describe what you'd like to know about them]"
        }
        
        // Use AIService to get response with function calling
        // Use premium model for trading advice to get better personalized responses
        let response = try await aiService.sendMessage(
            finalInput,
            systemPrompt: systemPrompt,
            usePremiumModel: isTradingAdviceQuery, // Premium model for trading advice, mini for everything else
            includeTools: true
        )
        
        return response
    }
    
    
    /// Legacy method for Assistants API (kept for image analysis fallback)
    private func fetchAIResponseLegacy(for userInput: String, imageFileIds: [String] = []) async throws -> String {
        let session = AITabView.openAISession
        
        var threadId: String
        if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }),
           let existingThreadId = conversations[currentConvoIndex].threadId {
            threadId = existingThreadId
        } else {
            guard let threadURL = URL(string: "https://api.openai.com/v1/threads") else { throw URLError(.badURL) }
            var threadRequest = URLRequest(url: threadURL)
            threadRequest.httpMethod = "POST"
            threadRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            threadRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
            threadRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
            threadRequest.httpBody = "{}".data(using: .utf8)
            let (threadData, threadResponse) = try await session.data(for: threadRequest)
            logResponse(threadData, threadResponse)
            struct ThreadResponse: Codable { let id: String }
            let threadRes = try JSONDecoder().decode(ThreadResponse.self, from: threadData)
            threadId = threadRes.id
            if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }) {
                conversations[currentConvoIndex].threadId = threadId
                saveConversations()
            }
        }
        
        // POST user message
        guard let messageURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages") else { throw URLError(.badURL) }
        var messageRequest = URLRequest(url: messageURL)
        messageRequest.httpMethod = "POST"
        messageRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        messageRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
        messageRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        let messagePayload: [String: Any]
        if !imageFileIds.isEmpty {
            var blocks: [[String: Any]] = []
            if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(["type": "input_text", "text": userInput])
            }
            for fid in imageFileIds {
                blocks.append(["type": "input_image", "image_file": ["file_id": fid]])
            }
            messagePayload = ["role": "user", "content": blocks]
        } else {
            messagePayload = ["role": "user", "content": userInput]
        }
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messagePayload)
        let (msgData, msgResponse) = try await session.data(for: messageRequest)
        logResponse(msgData, msgResponse)
        
        // POST run assistant
        guard let runURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs") else { throw URLError(.badURL) }
        var runRequest = URLRequest(url: runURL)
        runRequest.httpMethod = "POST"
        runRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        runRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
        runRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        let runPayload: [String: Any] = ["assistant_id": "asst_YlcZqIfjPmhCl44bUO77SYaJ"]
        runRequest.httpBody = try JSONSerialization.data(withJSONObject: runPayload)
        let (runData, runResponseVal) = try await session.data(for: runRequest)
        logResponse(runData, runResponseVal)
        
        struct RunResponse: Codable { let id: String }
        let runRes = try JSONDecoder().decode(RunResponse.self, from: runData)
        let runId = runRes.id
        
        // Poll for run completion – up to 60 iterations (30 seconds total)
        var assistantReply: String? = nil
        for _ in 1...60 {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let statusURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)") else { throw URLError(.badURL) }
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.httpMethod = "GET"
            statusRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
            statusRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
            do {
                let (statusData, statusResp) = try await session.data(for: statusRequest)
                logResponse(statusData, statusResp)
                
                struct RunStatus: Codable { let status: String }
                let statusRes = try JSONDecoder().decode(RunStatus.self, from: statusData)
                if statusRes.status.lowercased() == "succeeded" || statusRes.status.lowercased() == "completed" {
                    // Fetch messages
                    guard let msgsURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages") else { throw URLError(.badURL) }
                    var msgsRequest = URLRequest(url: msgsURL)
                    msgsRequest.httpMethod = "GET"
                    msgsRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
                    msgsRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
                    do {
                        let (msgsData, msgsResp) = try await session.data(for: msgsRequest)
                        logResponse(msgsData, msgsResp)
                        
                        struct ThreadMessagesResponse: Codable {
                            let object: String
                            let data: [AssistantMessage]
                            let first_id: String?
                            let last_id: String?
                            let has_more: Bool?
                        }
                        struct AssistantMessage: Codable { let id: String; let role: String; let content: [ContentBlock] }
                        struct ContentBlock: Codable { let type: String; let text: ContentText? }
                        struct ContentText: Codable { let value: String; let annotations: [String]? }
                        
                        let msgsRes = try JSONDecoder().decode(ThreadMessagesResponse.self, from: msgsData)
                        if let lastMsg = msgsRes.data.last, lastMsg.role == "assistant" {
                            let combinedText = lastMsg.content.compactMap { $0.text?.value }.joined(separator: "\n\n")
                            assistantReply = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } catch {
                        print("Error decoding thread messages:", error)
                    }
                    if assistantReply != nil { break }
                }
            } catch {
                print("Error polling run status:", error)
            }
        }
        
        guard let reply = assistantReply, !reply.isEmpty else { throw URLError(.timedOut) }
        return reply
    }
    
    private func logResponse(_ data: Data, _ response: URLResponse) {
        #if DEBUG
        if let httpRes = response as? HTTPURLResponse {
            print("Status code: \(httpRes.statusCode)")
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("Response body: \(body)")
        }
        #endif
    }
    
    private func handleQuickReply(_ reply: String) {
        chatVM.inputText = reply
        self.sendMessage()
    }
    
    private func randomizePrompts() {
        let shuffled = masterPrompts.shuffled()
        quickReplies = Array(shuffled.prefix(promptCount))
    }
    
    private func refreshPersonalizedPrompts() {
        isFetchingPersonalized = true
        Task {
            let prompts = await buildPersonalizedPrompts()
            await MainActor.run {
                DispatchQueue.main.async {
                    self.quickReplies = prompts.isEmpty ? Array(self.masterPrompts.shuffled().prefix(self.promptCount)) : prompts
                    self.isFetchingPersonalized = false
                }
            }
        }
    }

    private func buildPersonalizedPrompts() async -> [String] {
        // Use recent conversation to derive context (local, no network)
        let recentText = currentMessages.suffix(20).map { $0.text }.joined(separator: " ")
        let tickers = extractTickers(from: recentText)
        var prompts: [String] = []

        if let t = tickers.first {
            prompts.append("Show me a 24h price chart for \(t)")
        }
        if tickers.count >= 2 {
            prompts.append("Compare \(tickers[0]) and \(tickers[1])")
        }
        if let t = tickers.first {
            prompts.append("Should I buy or sell \(t) right now?")
        }
        if !tickers.isEmpty {
            prompts.append("What are key on-chain or news drivers for \(tickers[0]) this week?")
        }

        // Fill to promptCount with master prompts
        var filler = masterPrompts.shuffled()
        while prompts.count < promptCount, let next = filler.popLast() {
            if !prompts.contains(next) { prompts.append(next) }
        }
        return Array(prompts.prefix(promptCount))
    }

    private func extractTickers(from text: String) -> [String] {
        // Simple regex for ALL-CAPS 2–6 character tokens, filtered by knownTickers
        let pattern = "\\b[A-Z]{2,6}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var set = Set<String>()
        for m in matches {
            if let r = Range(m.range, in: text) {
                let token = String(text[r])
                if knownTickers.contains(token) { set.insert(token) }
            }
        }
        return Array(set).sorted()
    }
    
    private func scheduleScrollHintAutoHide() {
        showScrollHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showScrollHint = false
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }
    
    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(BrandGold.verticalGradient))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BrandGold.light.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
            .padding(.bottom, 48)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func clearActiveConversation() {
        guard let activeID = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        var convo = conversations[index]
        convo.messages.removeAll()
        conversations[index] = convo
        saveConversations()
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        scrollToBottom(proxy, animated: true)
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}

// MARK: - Persistence
extension AITabView {
    private var conversationsFile: String { "csai_conversations.json" }
    private var lastActiveKey: String { "csai_last_active_conversation_id" }

    private func saveConversations() {
        // Cap messages per conversation to avoid bloating storage
        let capped: [Conversation] = conversations.map { convo in
            var trimmed = convo
            if trimmed.messages.count > 200 {
                trimmed.messages = Array(trimmed.messages.suffix(200))
            }
            return trimmed
        }
        persistMessageImagesIfNeeded()
        CacheManager.shared.save(capped, to: conversationsFile)
        if let activeID = activeConversationID {
            UserDefaults.standard.set(activeID.uuidString, forKey: lastActiveKey)
        }
    }

    private func loadConversations() {
        if let loaded: [Conversation] = CacheManager.shared.load([Conversation].self, from: conversationsFile) {
            conversations = loaded
            normalizeConversationTitles()
        }
    }
    
    private func normalizeConversationTitles() {
        // Ensure all conversations have a reasonable, non-empty title
        for index in conversations.indices {
            let current = conversations[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                if let firstText = conversations[index].messages.first?.text {
                    let trimmed = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        conversations[index].title = String(trimmed.prefix(60))
                        continue
                    }
                }
                conversations[index].title = "Untitled Chat"
            }
        }
    }

    private func persistMessageImagesIfNeeded() {
        // Walk through conversations and move any in-memory imageData to file paths
        for cIndex in conversations.indices {
            for mIndex in conversations[cIndex].messages.indices {
                var msg = conversations[cIndex].messages[mIndex]
                // If we already have a path or no data, continue
                if msg.imagePath != nil || msg.imageData == nil { continue }
                if let data = msg.imageData, let path = saveImageDataToDisk(data, suggestedName: msg.id.uuidString + ".jpg") {
                    msg.imagePath = path
                    msg.imageData = nil
                    conversations[cIndex].messages[mIndex] = msg
                }
            }
        }
    }

    private func saveImageDataToDisk(_ data: Data, suggestedName: String) -> String? {
        let fm = FileManager.default
        let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = doc.appendingPathComponent("ChatImages", isDirectory: true)
        do { try fm.createDirectory(at: url, withIntermediateDirectories: true) } catch { }
        let fileURL = url.appendingPathComponent(suggestedName)
        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL.lastPathComponent // store only the filename; we reconstruct full path when loading
        } catch {
            print("[AIChat] Failed to write image: \(error)")
            return nil
        }
    }

    private func imageURL(for fileName: String) -> URL {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent("ChatImages").appendingPathComponent(fileName)
    }
}

private struct TopSafeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct BottomSafeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Micro Interactions
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Helpers (Attachments & Disk Image Loading)
struct DiskImageView: View {
    let url: URL
    @State private var uiImage: UIImage? = nil

    var body: some View {
        Group {
            if let ui = uiImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        do {
            let data = try Data(contentsOf: url)
            if let img = UIImage(data: data) {
                self.uiImage = img
            }
        } catch {
            // Silent fail; show placeholder
        }
    }
}

struct AttachmentChip: View {
    let image: UIImage
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.black)
                    .background(Circle().fill(Color.white))
            }
            .offset(x: 6, y: -6)
        }
    }
}

struct AnimatedTypingIndicator: View {
    var dotColor: Color = .white
    var dotSize: CGFloat = 6
    @State private var step: Int = 0
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 0 ? 1 : 0.35)
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 1 ? 1 : 0.35)
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 2 ? 1 : 0.35)
        }
        .task {
            while true {
                try? await Task.sleep(nanoseconds: 450_000_000)
                step = (step + 1) % 3
            }
        }
    }
}

struct GoldThinkingIndicator: View {
    var active: Bool = true
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // Pulsing gold rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(AngularGradient(
                            gradient: Gradient(colors: [
                                BrandGold.light.opacity(0.95),
                                BrandGold.dark.opacity(0.6),
                                BrandGold.light.opacity(0.95)
                            ]),
                            center: .center
                        ), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                        .scaleEffect(animate ? 1.0 + CGFloat(i) * 0.35 : 0.6)
                        .opacity(animate ? 0.15 - Double(i) * 0.03 : 0.0)
                }

                // Typing dots in the middle
                AnimatedTypingIndicator(dotColor: .white, dotSize: 6)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BrandGold.light.opacity(0.35), lineWidth: 1))
                    .shadow(color: BrandGold.light.opacity(0.25), radius: 8, x: 0, y: 0)
            }

            Text("CryptoSage is thinking…")
                .foregroundColor(.white)
                .font(.caption)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if reduceMotion { animate = false } else if active {
                    withAnimation(Animation.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            }
        }
    }
}

struct GoldGlowRingsView: View {
    var isActive: Bool
    var cornerRadius: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle: CGFloat = 1.8
            let base = CGFloat((t.truncatingRemainder(dividingBy: cycle)) / cycle)
            GeometryReader { geo in
                let maxDim = min(geo.size.width, 520)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let phase = CGFloat((base + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1))
                        Circle()
                            .stroke(BrandGold.light.opacity(0.75), lineWidth: 2)
                            .frame(width: maxDim * (0.5 + phase * 0.9), height: maxDim * (0.5 + phase * 0.9))
                            .opacity(Double(1 - phase) * 0.22)
                            .blur(radius: 10)
                            .shadow(color: BrandGold.light.opacity(0.35), radius: 10, x: 0, y: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .compositingGroup()            // isolate blend
                .blendMode(BlendMode.plusLighter)
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .padding(2)
                )
                .opacity(isActive ? 1 : 0)
            }
            .opacity(reduceMotion ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .allowsHitTesting(false)
    }
}

struct GoldSweepBorder: View {
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = 0
    private let seg: CGFloat = 0.28
    var body: some View {
        ZStack {
            // Base soft glow
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(BrandGold.light.opacity(0.45), lineWidth: 1.25)
                .shadow(color: BrandGold.light.opacity(0.28), radius: 6, x: 0, y: 0)
            // Moving highlight segment (handles wrap-around)
            let end1 = min(phase + seg, 1)
            let overflow = max(phase + seg - 1, 0)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: phase, to: end1)
                .stroke(
                    LinearGradient(colors: [
                        BrandGold.light.opacity(0.0),
                        BrandGold.light,
                        BrandGold.dark,
                        BrandGold.light.opacity(0.0)
                    ], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .compositingGroup()
                .blendMode(BlendMode.plusLighter)
            if overflow > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: 0, to: overflow)
                    .stroke(
                        LinearGradient(colors: [
                            BrandGold.light.opacity(0.0),
                            BrandGold.light,
                            BrandGold.dark,
                            BrandGold.light.opacity(0.0)
                        ], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .compositingGroup()
                    .blendMode(BlendMode.plusLighter)
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - ThinkingBubble (AI typing indicator)
struct ThinkingBubble: View {
    @State private var dotPhase: Int = 0
    
    var body: some View {
        HStack(alignment: .center) {
            // Animated dots only - clean and minimal
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(BrandGold.light.opacity(dotPhase == index ? 1.0 : 0.35))
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPhase == index ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.35), value: dotPhase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(BrandGold.light.opacity(0.25), lineWidth: 1)
                    )
            )
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            dotPhase = (dotPhase + 1) % 3
        }
    }
}

// MARK: - ChatBubble
struct ChatBubble: View {
    let message: ChatMessage
    @State private var showTimestamp: Bool = false
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top) {
            if message.sender == "ai" {
                aiView
                Spacer()
            } else {
                Spacer()
                userView
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .drawingGroup()
    }
    
    private var aiView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = message.imagePath {
                let url = imageURL(for: path)
                DiskImageView(url: url)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            } else if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            Text(formattedTime(message.timestamp))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var userView: some View {
        // let bubbleColor: Color = message.isError ? Color.red.opacity(0.8) : Color.yellow.opacity(0.8)
        let textColor: Color = message.isError ? Color.white : Color.black

        return VStack(alignment: .trailing, spacing: 6) {
            if let path = message.imagePath {
                let url = imageURL(for: path)
                DiskImageView(url: url)
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            } else if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(textColor)
            }
            if showTimestamp {
                Text("Sent at \(formattedTime(message.timestamp))")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            Group {
                if message.isError {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.8))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandGold.verticalGradient)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandGold.light.opacity(0.5), lineWidth: 0.8))
                }
            }
        )
        //.cornerRadius(16)  // removed because RoundedRectangle shape is used above
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onLongPressGesture { showTimestamp.toggle() }
    }
    
    private func formattedTime(_ date: Date) -> String {
        ChatBubble.timeFormatter.string(from: date)
    }
    
    private func imageURL(for fileName: String) -> URL {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent("ChatImages").appendingPathComponent(fileName)
    }
}

// MARK: - Preview
struct AITabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { AITabView() }
            .preferredColorScheme(.dark)
            .environmentObject(ChatViewModel())
            .environmentObject(PortfolioViewModel.sample)
            .environmentObject(AppState())
    }
}


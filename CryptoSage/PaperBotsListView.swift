//
//  PaperBotsListView.swift
//  CryptoSage
//
//  A view to display and manage all paper trading bots.
//  Shows bot status, allows start/stop/delete operations.
//

import SwiftUI

// MARK: - Paper Bots List View

struct PaperBotsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @State private var showDeleteConfirmation: Bool = false
    @State private var botToDelete: PaperBot?
    @State private var selectedFilter: BotFilterOption = .all
    @State private var showCreateBotSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var botToShare: PaperBot?
    
    private var isDark: Bool { colorScheme == .dark }
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    enum BotFilterOption: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Filter Pills
                filterSection
                
                // Stats Summary
                if !paperBotManager.paperBots.isEmpty {
                    statsSummary
                }
                
                // Bot List or Empty State
                if paperBotManager.paperBots.isEmpty {
                    emptyState
                } else {
                    botList
                }
            }
            
            // Floating Action Button (only show when there are bots)
            if !paperBotManager.paperBots.isEmpty {
                createBotFAB
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("My Bots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: TradingBotView(
                    side: .buy,
                    orderType: .market,
                    quantity: 0,
                    slippage: 0.5
                )) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [paperSecondary, paperPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        .confirmationDialog(
            "Delete Bot",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let bot = botToDelete {
                    withAnimation {
                        paperBotManager.deleteBot(id: bot.id)
                    }
                }
                botToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                botToDelete = nil
            }
        } message: {
            if let bot = botToDelete {
                Text("Are you sure you want to delete \"\(bot.name)\"? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Floating Action Button
    
    private var createBotFAB: some View {
        NavigationLink(destination: TradingBotView(
            side: .buy,
            orderType: .market,
            quantity: 0,
            slippage: 0.5
        )) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("New Bot")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [paperSecondary, paperPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(paperPrimary.opacity(isDark ? 0.5 : 0.35), lineWidth: 1)
            )
        }
        .padding(.trailing, 20)
        .padding(.bottom, 100)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BotFilterOption.allCases, id: \.self) { option in
                    filterPill(option)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DS.Adaptive.background)
    }
    
    private func filterPill(_ option: BotFilterOption) -> some View {
        let isSelected = selectedFilter == option
        let count = filteredCount(for: option)
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedFilter = option
            }
        } label: {
            HStack(spacing: 6) {
                Text(option.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected 
                                    ? (isDark ? Color.white.opacity(0.15) : Color.white.opacity(0.9))
                                    : DS.Adaptive.background.opacity(0.8))
                        )
                }
            }
            .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? paperPrimary.opacity(isDark ? 0.88 : 0.83) : DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? paperPrimary.opacity(isDark ? 0.55 : 0.45) : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
    
    private func filteredCount(for option: BotFilterOption) -> Int {
        switch option {
        case .all: return paperBotManager.paperBots.count
        case .running: return paperBotManager.paperBots.filter { $0.status == .running }.count
        case .stopped: return paperBotManager.paperBots.filter { $0.status == .stopped || $0.status == .idle }.count
        }
    }
    
    // MARK: - Stats Summary
    
    private var statsSummary: some View {
        HStack(spacing: 0) {
            statItem(
                icon: "cpu.fill",
                label: "Total Bots",
                value: "\(paperBotManager.totalBotCount)",
                color: paperPrimary
            )
            
            Rectangle()
                .fill(DS.Adaptive.stroke.opacity(0.5))
                .frame(width: 0.5, height: 36)
            
            statItem(
                icon: "play.circle.fill",
                label: "Running",
                value: "\(paperBotManager.runningBotCount)",
                color: .green
            )
            
            Rectangle()
                .fill(DS.Adaptive.stroke.opacity(0.5))
                .frame(width: 0.5, height: 36)
            
            statItem(
                icon: "chart.line.uptrend.xyaxis",
                label: "Total Trades",
                value: "\(paperBotManager.totalTrades)",
                color: .cyan
            )
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bot List
    
    private var botList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredBots) { bot in
                    PaperBotRowView(
                        bot: bot,
                        onToggle: {
                            paperBotManager.toggleBot(id: bot.id)
                        },
                        onDelete: {
                            botToDelete = bot
                            showDeleteConfirmation = true
                        },
                        onShare: {
                            botToShare = bot
                            showShareSheet = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showShareSheet) {
            if let bot = botToShare {
                ShareBotSheet(bot: bot) {
                    showShareSheet = false
                }
            }
        }
    }
    
    private var filteredBots: [PaperBot] {
        switch selectedFilter {
        case .all:
            return paperBotManager.paperBots
        case .running:
            return paperBotManager.paperBots.filter { $0.status == .running }
        case .stopped:
            return paperBotManager.paperBots.filter { $0.status == .stopped || $0.status == .idle }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(paperPrimary.opacity(isDark ? 0.22 : 0.16))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(paperPrimary.opacity(isDark ? 0.5 : 0.35), lineWidth: 1)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "cpu.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [paperSecondary, paperPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("No Paper Bots Yet")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Create your first paper trading bot to practice automated trading strategies risk-free.")
                .font(.body)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if !paperTradingManager.isPaperTradingEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("Enable Paper Trading mode first")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .padding(.top, 8)
            }
            
            // Create First Bot CTA Button - paper accent style
            NavigationLink(destination: TradingBotView(
                side: .buy,
                orderType: .market,
                quantity: 0,
                slippage: 0.5
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text("Create Your First Bot")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [paperSecondary, paperPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(paperPrimary.opacity(isDark ? 0.55 : 0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Paper Bot Row View

struct PaperBotRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let bot: PaperBot
    let onToggle: () -> Void
    let onDelete: () -> Void
    var onShare: (() -> Void)? = nil
    
    @State private var showDetails: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var paperPrimary: Color { AppTradingMode.paper.color }
    
    private var isRunning: Bool {
        bot.status == .running
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainRowContent
            expandedDetailsContent
        }
        .background(rowBackground)
        .overlay(rowOverlay)
    }
    
    // MARK: - Main Row - Redesigned for better space utilization
    
    private var mainRowContent: some View {
        VStack(spacing: 10) {
            // Top row: Icon, Name, Status, Expand
            HStack(spacing: 12) {
                botIconView
                
                VStack(alignment: .leading, spacing: 2) {
                    // Bot name - full width
                    Text(bot.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    // Bot details on second line
                    HStack(spacing: 4) {
                        Text(bot.type.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(bot.type.color)
                        
                        Text("·")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(bot.tradingPair.replacingOccurrences(of: "_", with: "/"))
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        Text("·")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(bot.exchange)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                Spacer()
                
                statusBadge
                
                expandButton
            }
            
            // Bottom row: P/L and Action buttons
            HStack(spacing: 12) {
                // P/L Section
                profitLossView
                
                Spacer()
                
                // Action buttons
                actionButtonsView
            }
        }
        .padding(14)
    }
    
    private var botIconView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bot.type.color.opacity(0.25), bot.type.color.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
            
            Circle()
                .stroke(bot.type.color.opacity(0.3), lineWidth: 1)
                .frame(width: 48, height: 48)
            
            Image(systemName: bot.type.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [bot.type.color, bot.type.color.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(bot.status.color)
                .frame(width: 6, height: 6)
            Text(bot.status.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(bot.status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(bot.status.color.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(bot.status.color.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - P/L Summary
    
    private var profitLossView: some View {
        HStack(spacing: 12) {
            // Profit/Loss
            VStack(alignment: .leading, spacing: 2) {
                Text("P/L")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .textCase(.uppercase)
                
                Text(formatProfit(bot.totalProfit))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
            }
            
            // Trades count
            VStack(alignment: .leading, spacing: 2) {
                Text("Trades")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .textCase(.uppercase)
                
                Text("\(bot.totalTrades)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 10) {
            if let shareAction = onShare {
                // Share button - subtle outline style (secondary action)
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    shareAction()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.background.opacity(0.8))
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        )
                }
            }
            
            // Toggle (Play/Stop) button - red for stop, paper accent for play
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onToggle()
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(
                                isRunning
                                    ? Color.red
                                    : paperPrimary.opacity(isDark ? 0.88 : 0.83)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(isRunning ? Color.red.opacity(0.5) : paperPrimary.opacity(isDark ? 0.55 : 0.45), lineWidth: 1)
                    )
            }
        }
    }
    
    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetails.toggle()
            }
        } label: {
            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(DS.Adaptive.background.opacity(0.8))
                        .overlay(
                            Circle()
                                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                        )
                )
        }
    }
    
    // MARK: - Expanded Details
    
    @ViewBuilder
    private var expandedDetailsContent: some View {
        if showDetails {
            Rectangle()
                .fill(DS.Adaptive.stroke.opacity(0.5))
                .frame(height: 0.5)
            
            VStack(spacing: 14) {
                // Configuration details in a grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if let direction = bot.direction {
                        detailItem(label: "Direction", value: direction, icon: "arrow.up.arrow.down")
                    }
                    if let tp = bot.takeProfit {
                        detailItem(label: "Take Profit", value: "\(tp)%", icon: "target", color: .green)
                    }
                    if let sl = bot.stopLoss {
                        detailItem(label: "Stop Loss", value: "\(sl)%", icon: "shield.fill", color: .red)
                    }
                    if let leverage = bot.leverage {
                        detailItem(label: "Leverage", value: "\(leverage)x", icon: "bolt.fill", color: .orange)
                    }
                    detailItem(label: "Created", value: formatDate(bot.createdAt), icon: "calendar")
                }
                
                // Delete button
                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                        Text("Delete Bot")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Background & Overlay
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.Adaptive.cardBackground)
    }
    
    private var rowOverlay: some View {
        let strokeColor = isRunning ? bot.status.color.opacity(0.4) : DS.Adaptive.stroke
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(strokeColor, lineWidth: isRunning ? 1.5 : 0.5)
    }
    
    // MARK: - Helpers
    
    private func detailItem(label: String, value: String, icon: String, color: Color = AppTradingMode.paper.color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Adaptive.background.opacity(0.5))
        )
    }
    
    private func formatProfit(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Paper Bots Section (For Settings View)

struct PaperBotsSection: View {
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - using GoldHeaderGlyphCompact for consistency
            HStack {
                HStack(spacing: 8) {
                    GoldHeaderGlyphCompact(systemName: "cpu.fill")
                    Text("Paper Bots")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                if paperBotManager.runningBotCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(paperBotManager.runningBotCount) running")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Content
            if paperBotManager.paperBots.isEmpty {
                // Empty state with improved styling
                VStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("No paper bots created yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Create bots to automate your paper trading")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Bot preview list (show first 3)
                VStack(spacing: 0) {
                    ForEach(Array(paperBotManager.paperBots.prefix(3).enumerated()), id: \.element.id) { index, bot in
                        HStack(spacing: 10) {
                            // Bot type icon with gradient background
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [bot.type.color.opacity(0.2), bot.type.color.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 28, height: 28)
                                Image(systemName: bot.type.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(bot.type.color)
                            }
                            
                            Text(bot.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(bot.status.color)
                                    .frame(width: 6, height: 6)
                                Text(bot.status.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(bot.status.color)
                            }
                        }
                        .padding(.vertical, 10)
                        
                        // Divider between rows
                        if index < min(paperBotManager.paperBots.count, 3) - 1 {
                            Rectangle()
                                .fill(DS.Adaptive.stroke.opacity(0.5))
                                .frame(height: 0.5)
                                .padding(.leading, 38)
                        }
                    }
                }
            }
            
            // Navigate to full list
            NavigationLink(destination: PaperBotsListView()) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14, weight: .medium))
                    Text("Manage All Bots")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.background.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Share Bot Sheet

struct ShareBotSheet: View {
    let bot: PaperBot
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var socialService = SocialService.shared
    @State private var botName: String = ""
    @State private var botDescription: String = ""
    @State private var selectedTags: [String] = []
    @State private var selectedRisk: RiskLevel = .medium
    @State private var isSharing = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?
    
    private var isDark: Bool { colorScheme == .dark }
    private var paperPrimary: Color { AppTradingMode.paper.color }
    private var paperSecondary: Color { AppTradingMode.paper.secondaryColor }
    
    private let commonTags = ["btc", "eth", "dca", "grid", "scalping", "longterm", "swing", "lowrisk", "highrisk"]
    
    private var canShare: Bool {
        !isSharing && !botName.isEmpty && socialService.currentProfile != nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Bot Preview Header
                    botPreviewHeader
                    
                    // Form Fields
                    formFieldsSection
                    
                    // Tags
                    tagsSection
                    
                    // Risk Level
                    riskSection
                    
                    // Profile Requirement
                    profileRequirementSection
                    
                    // Error Message
                    errorSection
                    
                    // Share Button (at bottom)
                    if socialService.currentProfile != nil {
                        shareButtonSection
                    }
                }
                .padding(16)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Share Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Bot Shared!", isPresented: $showingSuccess) {
                Button("OK") { onDismiss() }
            } message: {
                Text("Your bot configuration is now available in the marketplace.")
            }
            .onAppear {
                botName = bot.name
            }
        }
    }
    
    // MARK: - Bot Preview Header
    
    private var botPreviewHeader: some View {
        HStack(spacing: 14) {
            // Bot icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [bot.type.color.opacity(0.25), bot.type.color.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Circle()
                    .stroke(bot.type.color.opacity(0.3), lineWidth: 1)
                    .frame(width: 56, height: 56)
                
                Image(systemName: bot.type.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [bot.type.color, bot.type.color.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bot.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                HStack(spacing: 6) {
                    Text(bot.type.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(bot.type.color)
                    
                    Text("·")
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(bot.tradingPair.replacingOccurrences(of: "_", with: "/"))
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Form Fields Section
    
    private var formFieldsSection: some View {
        VStack(spacing: 16) {
            // Bot Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Bot Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                TextField("", text: $botName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                    )
            }
            
            // Description Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                TextField("Optional - describe your strategy", text: $botDescription, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(3...5)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                    )
            }
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            FlowLayout(spacing: 8) {
                ForEach(commonTags, id: \.self) { tag in
                    tagChip(for: tag)
                }
            }
        }
    }
    
    private func tagChip(for tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if isSelected {
                    selectedTags.removeAll { $0 == tag }
                } else {
                    selectedTags.append(tag)
                }
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text("#\(tag)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? paperPrimary.opacity(isDark ? 0.88 : 0.83)
                              : DS.Adaptive.cardBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected
                                ? paperPrimary.opacity(isDark ? 0.55 : 0.45)
                                : DS.Adaptive.stroke,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
    }
    
    // MARK: - Risk Section
    
    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Risk Level")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            // Custom segmented picker
            HStack(spacing: 0) {
                ForEach(RiskLevel.allCases, id: \.self) { risk in
                    riskSegment(risk)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
    
    private func riskSegment(_ risk: RiskLevel) -> some View {
        let isSelected = selectedRisk == risk
        let riskColor: Color = {
            switch risk {
            case .low: return .green
            case .medium: return .orange
            case .high: return .red
            }
        }()
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedRisk = risk
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(risk.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? (risk == .low ? .black : .white) : DS.Adaptive.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? riskColor : Color.clear)
                        .padding(4)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Profile Requirement Section
    
    @ViewBuilder
    private var profileRequirementSection: some View {
        if socialService.currentProfile == nil {
            VStack(spacing: 14) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Circle()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                Text("Create a profile to share bots")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("A profile lets others discover and copy your bot configurations")
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                
                // CTA Button
                Button {
                    // Navigate to profile creation
                } label: {
                    Text("Create Profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [paperSecondary, paperPrimary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Error Section
    
    @ViewBuilder
    private var errorSection: some View {
        if let error = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                Text(error)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Share Button Section
    
    private var shareButtonSection: some View {
        Button {
            shareBot()
        } label: {
            HStack(spacing: 8) {
                if isSharing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Share to Marketplace")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(canShare ? .white : DS.Adaptive.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        canShare
                            ? LinearGradient(colors: [paperSecondary, paperPrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [DS.Adaptive.cardBackground, DS.Adaptive.cardBackground], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(canShare ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .disabled(!canShare)
        .padding(.top, 8)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
    
    // MARK: - Share Action
    
    private func shareBot() {
        isSharing = true
        errorMessage = nil
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        Task {
            do {
                _ = try await socialService.shareBot(
                    from: bot,
                    name: botName,
                    description: botDescription.isEmpty ? nil : botDescription,
                    tags: selectedTags,
                    riskLevel: selectedRisk
                )
                await MainActor.run {
                    isSharing = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

struct PaperBotsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PaperBotsListView()
        }
        .preferredColorScheme(.dark)
    }
}

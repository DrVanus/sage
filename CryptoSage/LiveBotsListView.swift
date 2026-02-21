//
//  LiveBotsListView.swift
//  CryptoSage
//
//  A view to display and manage live 3Commas trading bots.
//  Shows bot status, allows start/stop operations.
//

import SwiftUI

// MARK: - Live Bots List View

struct LiveBotsListView: View {
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @State private var selectedFilter: BotFilterOption = .all
    @State private var isRefreshing: Bool = false
    
    enum BotFilterOption: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Pills
            filterSection
            
            // Content
            if liveBotManager.isLoading && liveBotManager.bots.isEmpty {
                loadingState
            } else if !liveBotManager.isConfigured {
                notConfiguredState
            } else if liveBotManager.bots.isEmpty {
                emptyState
            } else {
                // Stats Summary
                statsSummary
                
                // Bot List
                botList
            }
        }
        .background(Color.black)
        .navigationTitle("Live Bots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        isRefreshing = true
                        await liveBotManager.refreshBots()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing || liveBotManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.goldBase))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .disabled(isRefreshing || liveBotManager.isLoading)
            }
        }
        .onAppear {
            Task {
                await liveBotManager.refreshBots()
            }
        }
        .refreshable {
            await liveBotManager.refreshBots()
        }
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
        .background(Color.black)
    }
    
    private func filterPill(_ option: BotFilterOption) -> some View {
        let isSelected = selectedFilter == option
        let count = filteredCount(for: option)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = option
            }
        } label: {
            HStack(spacing: 6) {
                Text(option.rawValue)
                    .font(.system(size: 14, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.black.opacity(0.2) : Color.white.opacity(0.1))
                        )
                }
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected
                          ? LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
    
    private func filteredCount(for option: BotFilterOption) -> Int {
        switch option {
        case .all: return liveBotManager.bots.count
        case .running: return liveBotManager.enabledBotCount
        case .stopped: return liveBotManager.disabledBotCount
        }
    }
    
    // MARK: - Stats Summary
    
    private var statsSummary: some View {
        HStack(spacing: 16) {
            statItem(
                icon: "cpu",
                label: "Total Bots",
                value: "\(liveBotManager.totalBotCount)"
            )
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.2))
            
            statItem(
                icon: "play.circle.fill",
                label: "Running",
                value: "\(liveBotManager.enabledBotCount)",
                color: .green
            )
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.2))
            
            statItem(
                icon: "dollarsign.circle.fill",
                label: "Total Profit",
                value: formatProfit(liveBotManager.totalProfitUsd),
                color: liveBotManager.totalProfitUsd >= 0 ? .green : .red
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private func statItem(icon: String, label: String, value: String, color: Color = BrandColors.goldBase) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Bot List
    
    private var botList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Error banner if present
                if let error = liveBotManager.errorMessage {
                    errorBanner(message: error)
                }
                
                ForEach(filteredBots) { bot in
                    LiveBotRowView(
                        bot: bot,
                        isToggling: liveBotManager.isToggling(id: bot.id),
                        onToggle: {
                            Task {
                                await liveBotManager.toggleBot(id: bot.id)
                            }
                        }
                    )
                }
                
                // Last updated footer
                if let lastFetch = liveBotManager.lastFetchTime {
                    HStack {
                        Spacer()
                        Text("Last updated: \(formatTime(lastFetch))")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }
    
    private var filteredBots: [ThreeCommasBot] {
        switch selectedFilter {
        case .all:
            return liveBotManager.bots
        case .running:
            return liveBotManager.bots.filter { $0.isEnabled }
        case .stopped:
            return liveBotManager.bots.filter { !$0.isEnabled }
        }
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.goldBase))
                .scaleEffect(1.5)
            
            Text("Loading bots...")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notConfiguredState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }
            
            Text("3Commas Not Connected")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            
            Text("Connect your 3Commas account to view and manage your live trading bots.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            NavigationLink(destination: Link3CommasView()) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                    Text("Connect 3Commas")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "cpu")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("No Live Bots Yet")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            
            Text("You don't have any bots on 3Commas yet. Create bots on 3Commas or use paper trading to practice first.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                Task {
                    await liveBotManager.refreshBots()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BrandColors.goldBase)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(BrandColors.goldBase, lineWidth: 1)
                )
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Button {
                liveBotManager.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func formatProfit(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        if abs(value) >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Live Bot Row View

struct LiveBotRowView: View {
    let bot: ThreeCommasBot
    let isToggling: Bool
    let onToggle: () -> Void
    
    @State private var showDetails: Bool = false
    
    private var isRunning: Bool {
        bot.isEnabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainRowContent
            expandedDetailsContent
        }
        .background(rowBackground)
        .overlay(rowOverlay)
    }
    
    // MARK: - Main Row
    
    private var mainRowContent: some View {
        HStack(spacing: 12) {
            botIconView
            botInfoView
            Spacer()
            profitLossView
            actionButtonsView
        }
        .padding(14)
    }
    
    private var botIconView: some View {
        ZStack {
            Circle()
                .fill(bot.strategy.color.opacity(0.15))
                .frame(width: 44, height: 44)
            
            Image(systemName: bot.strategy.icon)
                .font(.system(size: 18))
                .foregroundColor(bot.strategy.color)
        }
    }
    
    private var botInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            botNameRow
            botDetailsRow
        }
        .layoutPriority(1)
    }
    
    private var botNameRow: some View {
        HStack(spacing: 6) {
            Text(bot.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            statusBadge
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(bot.status.color)
                .frame(width: 6, height: 6)
            Text(bot.status.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(bot.status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(bot.status.color.opacity(0.15)))
        .fixedSize()
    }
    
    private var botDetailsRow: some View {
        HStack(spacing: 6) {
            Text(bot.strategy.displayName)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
            
            Text("•")
                .foregroundColor(.gray.opacity(0.5))
            
            Text(formatPair(bot.primaryPair))
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
            
            if let accountName = bot.accountName {
                Text("•")
                    .foregroundColor(.gray.opacity(0.5))
                
                Text(accountName)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
    }
    
    // MARK: - P/L Summary (visible without expanding)
    
    private var profitLossView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatProfit(bot.totalProfitUsd))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(bot.totalProfitUsd >= 0 ? .green : .red)
                .lineLimit(1)
            
            let deals = (bot.closedDealsCount ?? 0)
            Text("\(deals) trades")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            toggleButton
            expandButton
        }
    }
    
    private var toggleButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onToggle()
        } label: {
            toggleButtonLabel
        }
        .disabled(isToggling)
    }
    
    @ViewBuilder
    private var toggleButtonLabel: some View {
        if isToggling {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.7)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.gray))
        } else {
            let icon = isRunning ? "stop.fill" : "play.fill"
            let fgColor: Color = isRunning ? .white : .black
            
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(fgColor)
                .frame(width: 36, height: 36)
                .background(toggleButtonBackground)
        }
    }
    
    @ViewBuilder
    private var toggleButtonBackground: some View {
        if isRunning {
            Circle().fill(Color.red)
        } else {
            Circle().fill(LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase], startPoint: .top, endPoint: .bottom))
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
                .foregroundColor(.gray)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }
    
    // MARK: - Expanded Details
    
    @ViewBuilder
    private var expandedDetailsContent: some View {
        if showDetails {
            Divider()
                .background(Color.white.opacity(0.1))
            
            VStack(spacing: 12) {
                configDetailsRow
                statsRow
            }
            .padding(14)
            .padding(.top, 2)
        }
    }
    
    private var configDetailsRow: some View {
        HStack(spacing: 20) {
            if let baseOrder = bot.baseOrderVolume {
                detailItem(label: "Base Order", value: "$\(String(format: "%.0f", baseOrder))")
            }
            if let tp = bot.takeProfit {
                detailItem(label: "Take Profit", value: "\(String(format: "%.1f", tp))%")
            }
            if let maxDeals = bot.maxActiveDeals {
                detailItem(label: "Max Deals", value: "\(maxDeals)")
            }
            if let safetyOrders = bot.maxSafetyOrders {
                detailItem(label: "Safety Orders", value: "\(safetyOrders)")
            }
        }
    }
    
    private var statsRow: some View {
        HStack(spacing: 20) {
            detailItem(label: "Active Deals", value: "\(bot.activeDealsCount ?? 0)")
            detailItem(
                label: "Profit",
                value: formatProfit(bot.totalProfitUsd),
                color: bot.totalProfitUsd >= 0 ? .green : .red
            )
            if let finishedDeals = bot.finishedDealsCount {
                detailItem(label: "Completed", value: "\(finishedDeals)")
            }
            if let createdAt = bot.createdAt {
                detailItem(label: "Created", value: formatDate(createdAt))
            }
        }
    }
    
    // MARK: - Background & Overlay
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
    }
    
    private var rowOverlay: some View {
        let strokeColor = isRunning ? bot.status.color.opacity(0.3) : Color.white.opacity(0.08)
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(strokeColor, lineWidth: 1)
    }
    
    // MARK: - Helpers
    
    private func detailItem(label: String, value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
        }
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
    
    private func formatPair(_ pair: String) -> String {
        pair.replacingOccurrences(of: "_", with: "/")
    }
}

// MARK: - Live Bots Section (For Settings View)

struct LiveBotsSection: View {
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("LIVE BOTS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .tracking(0.5)
                }
                
                Spacer()
                
                if liveBotManager.enabledBotCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(liveBotManager.enabledBotCount) running")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Content
            if !liveBotManager.isConfigured {
                // Not configured state
                HStack {
                    Text("Connect 3Commas to manage live bots")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if liveBotManager.bots.isEmpty {
                // Empty state
                HStack {
                    Text("No live bots on 3Commas")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                // Bot preview list (show first 3)
                VStack(spacing: 8) {
                    ForEach(liveBotManager.bots.prefix(3)) { bot in
                        HStack(spacing: 10) {
                            Image(systemName: bot.strategy.icon)
                                .font(.system(size: 14))
                                .foregroundColor(bot.strategy.color)
                                .frame(width: 24)
                            
                            Text(bot.name)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(bot.status.color)
                                    .frame(width: 6, height: 6)
                                Text(bot.status.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(bot.status.color)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    
                    // View All link
                    if liveBotManager.bots.count > 3 {
                        NavigationLink(destination: LiveBotsListView()) {
                            HStack {
                                Text("View all \(liveBotManager.bots.count) bots")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        }
                    }
                }
            }
            
            // Navigate to full list
            NavigationLink(destination: LiveBotsListView()) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14))
                    Text("Manage Live Bots")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            if liveBotManager.isConfigured && liveBotManager.bots.isEmpty {
                Task {
                    await liveBotManager.refreshBots()
                }
            }
        }
    }
}

// MARK: - Preview

struct LiveBotsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LiveBotsListView()
        }
        .preferredColorScheme(.dark)
    }
}

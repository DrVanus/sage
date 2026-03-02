//
//  NotificationsView.swift
//  CryptoSage
//
//  Premium Price Alerts view with unified SubpageHeaderBar styling.
//

import SwiftUI

fileprivate enum NotificationsDesign {
    static let cardCornerRadius: CGFloat = 16
    static let innerCardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 12
}

// MARK: - Main Notifications View

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var notificationsManager = NotificationsManager.shared
    @ObservedObject private var aiMonitor = AIPortfolioMonitor.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showAddAlert = false
    @State private var showUpgradeForAI = false
    @State private var editMode: EditMode = .inactive
    @State private var alertToEdit: PriceAlert? = nil
    @State private var alertToDelete: PriceAlert? = nil
    @State private var showDeleteConfirmation = false
    
    private var activeAlerts: [PriceAlert] {
        // Use allAlerts to include both basic and advanced/AI-enhanced alerts
        // Sort by creation date (newest first) for better UX
        notificationsManager.allAlerts
            .filter { !notificationsManager.triggeredAlertIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private var triggeredAlerts: [PriceAlert] {
        // Use allAlerts to include both basic and advanced/AI-enhanced alerts
        // Sort by creation date (newest first) for better UX
        notificationsManager.allAlerts
            .filter { notificationsManager.triggeredAlertIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private var headerSubtitle: String? {
        let count = activeAlerts.count
        if count == 0 { return nil }
        return "\(count) Active Alert\(count == 1 ? "" : "s")"
    }
    
    var body: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Redesigned header with bell icon and refined button
                SubpageHeaderBar(
                    title: "Alerts",
                    subtitle: headerSubtitle,
                    onDismiss: { dismiss() }
                ) {
                    // Right-side action buttons
                    HStack(spacing: 10) {
                        if !notificationsManager.allAlerts.isEmpty {
                            // Edit button — subtle text style
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3)) {
                                    editMode = editMode == .active ? .inactive : .active
                                }
                            } label: {
                                Text(editMode == .active ? "Done" : "Edit")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(editMode == .active ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                            }
                            .accessibilityLabel(editMode == .active ? "Done editing" : "Edit alerts")
                            .accessibilityHint(editMode == .active ? "Finish editing alerts" : "Reorder or delete alerts")
                        }
                        
                        // New Alert button — refined outlined capsule
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showAddAlert = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("New Alert")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(
                            PremiumSecondaryCTAStyle(
                                height: 30,
                                horizontalPadding: 12,
                                cornerRadius: 15,
                                font: .system(size: 12, weight: .semibold)
                            )
                        )
                        .accessibilityLabel("New Alert")
                        .accessibilityHint("Create a new price alert")
                    }
                }
                
                // AI Market Alerts toggle card
                aiPortfolioAlertsCard
                
                if notificationsManager.allAlerts.isEmpty && aiMonitor.recentEvents.isEmpty {
                    emptyStateView
                } else {
                    alertsListView
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .sheet(isPresented: $showAddAlert) {
            AddAlertView()
        }
        .unifiedPaywallSheet(feature: .aiPoweredAlerts, isPresented: $showUpgradeForAI)
        .sheet(item: $alertToEdit) { alert in
            AddAlertView(editingAlert: alert) {
                // On save callback - delete the old alert
                notificationsManager.removeAlert(id: alert.id)
            }
        }
        .onAppear {
            notificationsManager.startMonitoring()
        }
        .confirmationDialog(
            "Delete Alert",
            isPresented: $showDeleteConfirmation,
            presenting: alertToDelete
        ) { alert in
            Button("Delete", role: .destructive) {
                performDelete(alert)
            }
            Button("Cancel", role: .cancel) {
                alertToDelete = nil
            }
        } message: { alert in
            Text("Are you sure you want to delete the alert for \(alert.symbol)?")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 34)
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(BrandColors.goldBase.opacity(0.2), lineWidth: 1)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bell.badge")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.bottom, 8)
            
            Text("No Alerts Yet")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Text("Create price alerts or enable AI market alerts\nto catch major crypto moves and sentiment shifts.")
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showAddAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Create Alert")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 52,
                    horizontalPadding: 24,
                    cornerRadius: 26,
                    font: .system(size: 16, weight: .bold)
                )
            )
            .padding(.top, 8)
            
            Spacer(minLength: 74)
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No alerts yet. Create price alerts or enable AI market alerts to catch major crypto moves.")
    }

    // MARK: - AI Market Alerts Card
    
    private var aiPortfolioAlertsCard: some View {
        let hasPro = subscriptionManager.hasAccess(to: .aiPoweredAlerts)
        
        return AIPortfolioAlertsCardView(
            hasPro: hasPro,
            isEnabled: aiMonitor.isEnabled,
            coverageMode: aiMonitor.coverageMode,
            monitorStatus: monitorStatusSummary,
            connectionText: relativeTime(aiMonitor.lastDigestReceivedAt),
            lastAlertText: relativeTime(aiMonitor.lastNotificationSentAt),
            onToggle: { newVal in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                aiMonitor.isEnabled = newVal
            },
            onSelectCoverageMode: { aiMonitor.coverageMode = $0 },
            onUpgrade: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showUpgradeForAI = true
            }
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var monitorStatusSummary: String {
        switch aiMonitor.listenerHealth {
        case .idle:
            return aiMonitor.isEnabled ? "Starting" : "Off"
        case .listening:
            return "Connected"
        case .retrying:
            return "Reconnecting"
        case .error:
            return "Retrying"
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
    
    // MARK: - Alerts List
    
    private var alertsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // AI Portfolio Alert events (if any)
                if !aiMonitor.recentEvents.isEmpty {
                    aiEventsSection
                }
                
                if !activeAlerts.isEmpty {
                    alertSectionHeader(title: "ACTIVE ALERTS", count: activeAlerts.count, color: BrandColors.goldBase)
                    
                    ForEach(Array(activeAlerts.enumerated()), id: \.element.id) { index, alert in
                        alertCardWithActions(alert: alert, isTriggered: false)
                            .modifier(StaggeredAppearance(index: index))
                    }
                }
                
                if !triggeredAlerts.isEmpty {
                    // Triggered section header with "Clear All" action
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            // Glowing green dot
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            
                            Text("TRIGGERED")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                                .tracking(1.0)
                            
                            // Count badge
                            Text("\(triggeredAlerts.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.12))
                                )
                            
                            Spacer()
                            
                            // Clear All capsule button
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation {
                                    for alert in triggeredAlerts {
                                        notificationsManager.resetAlert(id: alert.id)
                                    }
                                }
                            } label: {
                                Text("Clear All")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.6))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Explanatory subtitle
                        Text("These alerts fired when their conditions were met")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, activeAlerts.isEmpty ? 8 : 18)
                    .padding(.bottom, 4)
                    
                    ForEach(Array(triggeredAlerts.enumerated()), id: \.element.id) { index, alert in
                        alertCardWithActions(alert: alert, isTriggered: true)
                            .modifier(StaggeredAppearance(index: index + activeAlerts.count))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .withUIKitScrollBridge()
    }
    
    @ViewBuilder
    private func alertCardWithActions(alert: PriceAlert, isTriggered: Bool) -> some View {
        AlertCardView(
            alert: alert,
            isTriggered: isTriggered,
            editMode: editMode,
            onDelete: { deleteAlert(alert) },
            onReset: isTriggered ? { resetAlert(alert) } : nil
        )
        .contextMenu {
            // Edit action
            Button {
                editAlert(alert)
            } label: {
                Label("Edit Alert", systemImage: "pencil")
            }
            
            // Duplicate action
            Button {
                duplicateAlert(alert)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            // Reset action (for triggered alerts)
            if isTriggered {
                Button {
                    resetAlert(alert)
                } label: {
                    Label("Reset Alert", systemImage: "arrow.counterclockwise")
                }
            }
            
            // Delete action
            Button(role: .destructive) {
                deleteAlert(alert)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteAlert(alert)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editAlert(alert)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(BrandColors.goldBase)
            
            Button {
                duplicateAlert(alert)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }
    
    // MARK: - AI Events Section
    
    private var aiEventsSection: some View {
        let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
        let recentEvents = aiMonitor.recentEvents.prefix(8)
        
        return Group {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.72, green: 0.52, blue: 1.0), aiColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("AI INSIGHTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .tracking(0.6)
                
                Text("\(recentEvents.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(aiColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(aiColor.opacity(0.12)))
                
                Spacer()
                
                if aiMonitor.recentEvents.count > 1 {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            aiMonitor.clearAllEvents()
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            ForEach(Array(recentEvents)) { event in
                AIEventCard(event: event)
            }
        }
    }
    
    private func alertSectionHeader(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            // Glowing dot indicator
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Adaptive.textSecondary)
                .tracking(1.0)
            
            Spacer()
            
            // Count badge
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(color.opacity(0.12))
                )
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private func deleteAlert(_ alert: PriceAlert) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        alertToDelete = alert
        showDeleteConfirmation = true
    }
    
    private func performDelete(_ alert: PriceAlert) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            if let idx = notificationsManager.alerts.firstIndex(where: { $0.id == alert.id }) {
                notificationsManager.removeAlerts(at: IndexSet(integer: idx))
            }
            // Also check advanced alerts
            notificationsManager.removeAlert(id: alert.id)
        }
        alertToDelete = nil
    }
    
    private func resetAlert(_ alert: PriceAlert) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            notificationsManager.resetAlert(id: alert.id)
        }
    }
    
    private func editAlert(_ alert: PriceAlert) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        alertToEdit = alert
    }
    
    private func duplicateAlert(_ alert: PriceAlert) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Create a copy with a new ID
        notificationsManager.addAlertWithAI(
            symbol: alert.symbol,
            threshold: alert.threshold,
            isAbove: alert.isAbove,
            conditionType: alert.conditionType,
            timeframe: alert.timeframe,
            enablePush: alert.enablePush,
            enableEmail: alert.enableEmail,
            enableTelegram: alert.enableTelegram,
            minWhaleAmount: alert.minWhaleAmount,
            walletAddress: alert.walletAddress,
            volumeMultiplier: alert.volumeMultiplier,
            enableSentimentAnalysis: alert.enableSentimentAnalysis,
            enableSmartTiming: alert.enableSmartTiming,
            enableAIVolumeSpike: alert.enableAIVolumeSpike,
            frequency: alert.frequency
        )
    }
}

// MARK: - Alert Card View

private struct AlertCardView: View {
    let alert: PriceAlert
    let isTriggered: Bool
    let editMode: EditMode
    let onDelete: () -> Void
    let onReset: (() -> Void)?
    
    @ObservedObject private var notificationsManager = NotificationsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var thresholdFormatted: String {
        formatPrice(alert.threshold)
    }
    
    private var currentPrice: Double? {
        notificationsManager.currentPrice(for: alert.symbol)
    }
    
    private var currentPriceFormatted: String? {
        guard let price = currentPrice else { return nil }
        return formatPrice(price)
    }
    
    /// Progress toward alert trigger (0.0 to 1.0+)
    private var progress: Double? {
        guard let current = currentPrice else { return nil }
        let target = alert.threshold
        
        if alert.isAbove {
            // For "above" alerts, progress increases as price approaches target from below
            if current >= target { return 1.0 }
            // Use actual creation price as baseline when available, else estimate at 80%
            let baseline = alert.creationPrice ?? (target * 0.8)
            if current <= baseline { return 0.0 }
            let range = target - baseline
            guard range > 0 else { return 1.0 }
            return (current - baseline) / range
        } else {
            // For "below" alerts, progress increases as price approaches target from above
            if current <= target { return 1.0 }
            // Use actual creation price as baseline when available, else estimate at 120%
            let baseline = alert.creationPrice ?? (target * 1.2)
            if current >= baseline { return 0.0 }
            let range = baseline - target
            guard range > 0 else { return 1.0 }
            return (baseline - current) / range
        }
    }
    
    /// Extract base symbol (remove USDT suffix if present)
    private var baseSymbol: String {
        let sym = alert.symbol.uppercased()
        if sym.hasSuffix("USDT") {
            return String(sym.dropLast(4))
        }
        return sym
    }
    
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "%.2f", price)
        } else if price >= 1 {
            return String(format: "%.2f", price)
        } else if price >= 0.01 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.6f", price)
        }
    }
    
    /// Format a trigger timestamp as relative time (e.g., "2h ago", "Yesterday 3:15 PM")
    private func triggerTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Delete button in edit mode
            if editMode == .active {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Main card content
            HStack(spacing: 0) {
                // Gold accent bar on the left edge for active alerts
                if !isTriggered {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldBase, BrandColors.goldBase.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 8)
                } else {
                    // Green accent bar for triggered alerts
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
                
                HStack(spacing: 12) {
                    // Coin logo — uses CoinImageView with multi-source fallback
                    CoinImageView(symbol: baseSymbol, url: nil, size: 42)
                    
                    // Alert info
                    VStack(alignment: .leading, spacing: 5) {
                        // Top row: Symbol + badges
                        HStack(spacing: 8) {
                            Text(alert.symbol)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            
                            // Alert type badge
                            if alert.hasAIFeatures {
                PremiumAlertBadge(text: "AI-ENH", colors: [Color(red: 0.58, green: 0.35, blue: 0.98), Color(red: 0.72, green: 0.45, blue: 1.0)])
                            } else if alert.conditionType.isAdvanced {
                                PremiumAlertBadge(text: "ADV", colors: [.orange, .orange.opacity(0.7)])
                            }
                            
                            if isTriggered {
                                PremiumAlertBadge(text: "TRIGGERED", colors: [Color.green, Color(red: 0.2, green: 0.8, blue: 0.4)])
                            }
                        }
                        
                        // AI Features chips (shown when AI features are enabled)
                        if alert.hasAIFeatures {
                            AIFeatureChipsView(alert: alert)
                        }
                        
                        // Smart Timing delay indicator
                        if !isTriggered && alert.enableSmartTiming && notificationsManager.smartTimingDelayedAlerts.contains(alert.id) {
                            SmartTimingDelayBadge()
                        }
                        
                        // Condition type for advanced alerts
                        if alert.conditionType.isAdvanced {
                            HStack(spacing: 4) {
                                Image(systemName: alert.conditionType.icon)
                                    .font(.system(size: 9, weight: .semibold))
                                Text(alert.conditionType.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                if let timeframe = alert.timeframe {
                                    Text("• \(timeframe.displayName)")
                                        .font(.system(size: 10, weight: .medium))
                                }
                            }
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        }
                        
                        // Price row: show trigger price for triggered alerts, current → target for active
                        if isTriggered, let meta = notificationsManager.triggerMetadata[alert.id] {
                            // Triggered: show the price at trigger time with glow
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.green)
                                
                                Text("Triggered at $\(formatPrice(meta.triggeredPrice))")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.green)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.green.opacity(colorScheme == .dark ? 0.1 : 0.06))
                            )
                            
                            // Show when it triggered
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(triggerTimeAgo(meta.triggeredAt))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            
                            // Show AI reason if available
                            if let reason = meta.aiReason, !reason.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9))
                                    Text(reason)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(2)
                                }
                                .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.98))
                                .padding(.top, 1)
                            }
                        } else {
                            // Active alert: Current → Target with enhanced styling
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    // Direction icon
                                    Image(systemName: alert.isAbove ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(alert.isAbove ? Color.green : Color.red)
                                    
                                    if let currentFormatted = currentPriceFormatted {
                                        Text("$\(currentFormatted)")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(DS.Adaptive.textTertiary)
                                    }
                                    
                                    Text("$\(thresholdFormatted)")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(alert.isAbove ? Color.green : Color.red)
                                }
                                
                                // Progress bar (if not triggered and we have current price)
                                if let prog = progress {
                                    AlertProgressBar(progress: prog, isAbove: alert.isAbove)
                                }
                            }
                        }
                        
                        // Frequency badge
                        if alert.frequency != .oneTime {
                            HStack(spacing: 4) {
                                Image(systemName: alert.frequency.icon)
                                    .font(.system(size: 9))
                                Text(alert.frequency.displayName)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .padding(.top, 2)
                        }
                    }
                    
                    Spacer()
                    
                    // Right side: Reset button or notification icons
                    VStack(alignment: .trailing, spacing: 8) {
                        if isTriggered && editMode != .active, let onReset = onReset {
                            Button {
                                onReset()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Reset")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(colorScheme == .dark ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [BrandColors.goldBase, BrandColors.goldBase.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if !isTriggered || editMode == .active {
                            // Notification method icons in a pill
                            HStack(spacing: 4) {
                                if alert.enablePush {
                                    NotificationBadgeIcon(name: "bell.badge.fill", color: BrandColors.goldBase)
                                }
                                if alert.enableEmail {
                                    NotificationBadgeIcon(name: "envelope.fill", color: .blue)
                                }
                                if alert.enableTelegram {
                                    NotificationBadgeIcon(name: "paperplane.fill", color: Color(red: 0.0, green: 0.53, blue: 0.82))
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.6))
                            )
                        }
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous))
            .overlay(cardBorder)
        }
        .animation(.spring(response: 0.3), value: editMode)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
            .fill(
                isTriggered
                    ? Color.green.opacity(colorScheme == .dark ? 0.06 : 0.04)
                    : Color(white: colorScheme == .dark ? 0.11 : 0.97)
            )
            .background(
                RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: isTriggered
                        ? [Color.green.opacity(0.35), Color.green.opacity(0.1)]
                        : [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.3), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isTriggered ? 1 : 0.75
            )
    }
}

// MARK: - Alert Card Subcomponents

// CoinLogo removed — now uses the shared CoinImageView component
// which has multi-source fallback: Firebase Storage → CoinGecko → CoinCap → CryptoIcons → SpotHQ

private struct AlertTypeBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }
}

/// Premium gradient badge for alert types
private struct PremiumAlertBadge: View {
    let text: String
    let colors: [Color]
    
    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
}

private struct AlertProgressBar: View {
    let progress: Double
    let isAbove: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
    
    private var percentText: String {
        "\(Int(clampedProgress * 100))%"
    }
    
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15))
                        .frame(height: 5)
                    
                    // Progress fill with glow
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isAbove
                                    ? [Color.green.opacity(0.7), Color.green]
                                    : [Color.red.opacity(0.7), Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * clampedProgress, 5), height: 5)
                }
            }
            .frame(height: 5)
            .frame(maxWidth: 110)
            
            Text(percentText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isAbove ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
        }
    }
}

private struct NotificationBadgeIcon: View {
    let name: String
    let color: Color
    
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(color.opacity(0.12))
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - AI Feature Chips View

private struct AIFeatureChipsView: View {
    let alert: PriceAlert
    
    // Purple gradient colors for AI features
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    private let aiHighlight = Color(red: 0.72, green: 0.52, blue: 1.0)
    
    var body: some View {
        // Unified AI strip with all enabled features
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                // Sparkle prefix icon
                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(aiHighlight)
                
                if alert.enableSentimentAnalysis {
                    AIFeatureChip(icon: "chart.line.text.clipboard", text: "Sentiment")
                }
                if alert.enableSmartTiming {
                    AIFeatureChip(icon: "clock.badge.checkmark.fill", text: "Timing")
                }
                if alert.enableAIVolumeSpike {
                    AIFeatureChip(icon: "waveform.badge.plus", text: "Volume")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [aiColor.opacity(0.12), aiHighlight.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [aiColor.opacity(0.3), aiHighlight.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.5
                    )
            )
            
            Spacer()
        }
    }
}

private struct AIFeatureChip: View {
    let icon: String
    let text: String
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(aiColor)
    }
}

// MARK: - Smart Timing Delay Badge

private struct SmartTimingDelayBadge: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 5) {
            // Animated clock icon
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            Text("Waiting for market activity")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Staggered Appearance Animation

private struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .onAppear {
                let delay = Double(min(index, 8)) * 0.06
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Legacy Alert Row (kept for compatibility)

struct AlertRowView: View {
    let alert: PriceAlert
    
    var body: some View {
        AlertCardView(alert: alert, isTriggered: false, editMode: .inactive, onDelete: {}, onReset: nil)
    }
}

struct AlertSwipeRowView: View {
    let alert: PriceAlert
    private let notificationsManager = NotificationsManager.shared
    
    var body: some View {
        AlertRowView(alert: alert)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if let idx = notificationsManager.alerts.firstIndex(where: { $0.id == alert.id }) {
                        notificationsManager.removeAlerts(at: IndexSet(integer: idx))
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// MARK: - AI Market Alerts Card (Premium Design)

private struct AIPortfolioAlertsCardView: View {
    let hasPro: Bool
    let isEnabled: Bool
    let coverageMode: AIAlertCoverageMode
    let monitorStatus: String
    let connectionText: String
    let lastAlertText: String
    let onToggle: (Bool) -> Void
    let onSelectCoverageMode: (AIAlertCoverageMode) -> Void
    let onUpgrade: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var sheenOffset: CGFloat = -1.1
    @State private var isCoverageDropdownOpen: Bool = false
    
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    private let aiColorDeep = Color(red: 0.38, green: 0.20, blue: 0.82)
    private let aiColorLight = Color(red: 0.72, green: 0.52, blue: 1.0)
    
    private var isDark: Bool { colorScheme == .dark }

    private var statusDotColor: Color {
        if !isEnabled { return DS.Adaptive.textTertiary.opacity(0.5) }
        switch monitorStatus {
        case "Connected":  return .green
        case "Starting":   return .yellow
        case "Reconnecting", "Retrying": return .orange
        default:           return DS.Adaptive.textTertiary.opacity(0.5)
        }
    }

    private var compactStatusLine: String {
        if !isEnabled { return "Paused" }
        let base = monitorStatus
        if connectionText.isEmpty { return base }
        if connectionText == "just now" { return "\(base) · now" }
        return "\(base) · \(connectionText)"
    }

    private var coverageModeTitle: String {
        coverageMode == .marketAndPortfolio ? "Market + Portfolio" : "Portfolio Only"
    }

    var body: some View {
        ZStack {
            if hasPro {
                // Full card content for pro users
                cardContent
            } else {
                // Clean card for free users — no overlay bleeding
                freeCardContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous))
        // Prevent locked overlay's flexible shape from causing the card to expand
        // and consume VStack space alongside the ScrollView.
        .fixedSize(horizontal: false, vertical: true)
        .overlay(borderGlow)
        .overlay(movingSheen)
        .shadow(
            color: isEnabled ? aiColor.opacity(0.20) : Color.black.opacity(isDark ? 0.30 : 0.10),
            radius: isEnabled ? 18 : 10,
            x: 0,
            y: 6
        )
        .onAppear {
            withAnimation(.linear(duration: isEnabled ? 8.0 : 13.0).repeatForever(autoreverses: false)) {
                glowPhase = 1.0
            }
            withAnimation(.linear(duration: isEnabled ? 6.8 : 10.5).repeatForever(autoreverses: false)) {
                sheenOffset = 1.2
            }
            if isEnabled {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.18
                }
            }
        }
        .onChange(of: isEnabled) { _, newVal in
            if newVal {
                pulseScale = 1.0
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.18
                }
                sheenOffset = -1.1
                withAnimation(.linear(duration: 6.4).repeatForever(autoreverses: false)) {
                    sheenOffset = 1.2
                }
                withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                    glowPhase = 1.0
                }
            } else {
                pulseScale = 1.0
                isCoverageDropdownOpen = false
                sheenOffset = -1.1
                withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                    sheenOffset = 1.2
                }
                withAnimation(.linear(duration: 13.0).repeatForever(autoreverses: false)) {
                    glowPhase = 1.0
                }
            }
        }
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                aiIconView
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("AI Market Alerts")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                            .minimumScaleFactor(0.92)
                        
                        if hasPro && isEnabled {
                            statusPill(
                                text: "LIVE",
                                icon: "dot.radiowaves.left.and.right",
                                tint: Color.green
                            )
                        }
                        
                        if !hasPro {
                            statusPill(
                                text: "PRO",
                                icon: "crown.fill",
                                tint: BrandColors.goldBase
                            )
                        }
                    }
                    
                    if hasPro && isEnabled {
                        Text("Actively monitoring market and portfolio signals")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .lineLimit(2)
                    } else if hasPro {
                        Text("Turn on AI monitoring for market shifts, news, and sentiment changes")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .lineLimit(2)
                    } else {
                        Text("Upgrade to unlock AI-driven market and portfolio monitoring alerts")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 4)
                
                if hasPro {
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: aiColor))
                    .labelsHidden()
                    .accessibilityLabel("AI Market Alerts")
                    .accessibilityHint("Toggles market and portfolio AI monitoring alerts")
                }
            }
            
            if hasPro {
                Divider().opacity(0.15)
                
                HStack(alignment: .top, spacing: 0) {
                    // Coverage mode picker (custom dropdown box)
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isCoverageDropdownOpen.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(coverageModeTitle)
                                    .font(.system(size: 10, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .rotationEffect(.degrees(isCoverageDropdownOpen ? 180 : 0))
                            }
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isCoverageDropdownOpen ? aiColor.opacity(0.16) : DS.Adaptive.chipBackground.opacity(0.95))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isCoverageDropdownOpen ? aiColor.opacity(0.40) : DS.Adaptive.stroke.opacity(0.45),
                                        lineWidth: 0.8
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if isCoverageDropdownOpen {
                            coverageDropdownPanel
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    // Inline status: dot + status text · last alert time
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 5, height: 5)
                        
                        Text(compactStatusLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .lineLimit(1)
                        
                        if isEnabled && !lastAlertText.isEmpty {
                            Text("· Last alert \(lastAlertText)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Market Alerts")
        .accessibilityHint(hasPro ? "Monitors market and portfolio conditions and sends alerts" : "Upgrade to Pro to unlock AI market alerts")
    }
    
    private var coverageDropdownPanel: some View {
        VStack(spacing: 0) {
            coverageDropdownOption(
                title: "Market + Portfolio",
                subtitle: "Broad market and portfolio signals",
                mode: .marketAndPortfolio
            )
            
            Divider().opacity(0.18)
            
            coverageDropdownOption(
                title: "Portfolio Only",
                subtitle: "Only alerts tied to your holdings",
                mode: .portfolioOnly
            )
        }
        .padding(4)
        .frame(width: 208, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotificationsDesign.controlCornerRadius, style: .continuous)
                .fill(isDark ? Color(white: 0.14) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotificationsDesign.controlCornerRadius, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(isDark ? 0.32 : 0.12), radius: 10, x: 0, y: 6)
    }
    
    private func coverageDropdownOption(title: String, subtitle: String, mode: AIAlertCoverageMode) -> some View {
        let isSelected = coverageMode == mode
        
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectCoverageMode(mode)
            withAnimation(.easeInOut(duration: 0.18)) {
                isCoverageDropdownOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? aiColor : DS.Adaptive.textTertiary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? aiColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - AI Icon
    
    private var aiIconView: some View {
        ZStack {
            // Glow behind icon
            Circle()
                .fill(
                    RadialGradient(
                        colors: [aiColor.opacity(isEnabled ? 0.30 : 0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 52)
            
            // Icon circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [aiColorLight, aiColor, aiColorDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
            
            // Sparkle icon
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    
    // MARK: - Card Background
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isDark
                        ? [Color(white: 0.11), Color(white: 0.085)]
                        : [Color(white: 0.99), Color(white: 0.965)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
    }

    private func statusPill(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
            Text(text)
                .font(.system(size: 8, weight: .heavy))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Capsule().stroke(tint.opacity(0.40), lineWidth: 0.7))
        )
    }

    
    
    // MARK: - Animated Border Glow
    
    private var borderGlow: some View {
        RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: isEnabled
                        ? [aiColor.opacity(0.36), aiColorLight.opacity(0.22), aiColor.opacity(0.08), aiColorDeep.opacity(0.20), aiColor.opacity(0.36)]
                        : [aiColor.opacity(0.10), Color.white.opacity(0.04), aiColor.opacity(0.07), Color.white.opacity(0.03), aiColor.opacity(0.10)]
                    ),
                    center: .center,
                    angle: .degrees(glowPhase * 360)
                ),
                lineWidth: isEnabled ? 1.25 : 0.9
            )
    }

    private var movingSheen: some View {
        GeometryReader { geo in
            let width = geo.size.width
            RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(isDark ? 0.06 : 0.12),
                            Color.white.opacity(isDark ? 0.16 : 0.22),
                            Color.white.opacity(isDark ? 0.06 : 0.12),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: max(64, width * 0.32))
                .rotationEffect(.degrees(14))
                .offset(x: width * sheenOffset)
                .blur(radius: 1.2)
                .opacity(isEnabled ? 1.0 : 0.32)
        }
        .clipShape(RoundedRectangle(cornerRadius: NotificationsDesign.cardCornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
    
    // MARK: - Free User Card Content

    private var freeCardContent: some View {
        Button {
            onUpgrade()
        } label: {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    aiIconView

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("AI Market Alerts")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                                .minimumScaleFactor(0.92)

                            statusPill(
                                text: "PRO",
                                icon: "crown.fill",
                                tint: BrandColors.goldBase
                            )
                        }

                        Text("Upgrade to unlock AI-driven market and portfolio monitoring alerts")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)
                }

                // Prominent upgrade CTA
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Unlock with Pro")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 16)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [aiColor, aiColorDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Market Alerts")
        .accessibilityHint("Upgrade to Pro to unlock AI market alerts")
    }
}

// MARK: - AI Event Card

private struct AIEventCard: View {
    let event: PortfolioEvent
    
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    
    private var eventIcon: String {
        switch event.kind {
        case .largeDrop, .portfolioDrop: return "arrow.down.right.circle.fill"
        case .largeGain, .portfolioGain: return "arrow.up.right.circle.fill"
        case .btcMajorMove: return "bitcoinsign.circle.fill"
        case .sentimentShift: return "brain.head.profile"
        case .marketWideMove: return "globe"
        case .breakingNews: return "newspaper.fill"
        }
    }
    
    private var eventColor: Color {
        switch event.kind {
        case .largeDrop, .portfolioDrop: return .red
        case .largeGain, .portfolioGain: return .green
        case .btcMajorMove: return .orange
        case .sentimentShift: return aiColor
        case .marketWideMove: return .cyan
        case .breakingNews: return .yellow
        }
    }
    
    private var eventTitle: String {
        switch event.kind {
        case .largeDrop:
            return "\(event.symbol ?? "Coin") \(String(format: "%.1f", event.changePercent))%"
        case .largeGain:
            return "\(event.symbol ?? "Coin") +\(String(format: "%.1f", event.changePercent))%"
        case .portfolioDrop:
            return "Portfolio \(String(format: "%.1f", event.changePercent))%"
        case .portfolioGain:
            return "Portfolio +\(String(format: "%.1f", event.changePercent))%"
        case .btcMajorMove:
            let dir = event.changePercent > 0 ? "+" : ""
            return "BTC \(dir)\(String(format: "%.1f", event.changePercent))%"
        case .sentimentShift:
            return "Market Sentiment Shift"
        case .marketWideMove:
            return "Market \(event.changePercent >= 0 ? "+" : "")\(String(format: "%.1f", event.changePercent))%"
        case .breakingNews:
            return extractedBreakingHeadline
        }
    }
    
    private var eventKindLabel: String {
        switch event.kind {
        case .largeDrop:
            return "LARGE DROP"
        case .largeGain:
            return "LARGE GAIN"
        case .portfolioDrop:
            return "PORTFOLIO DROP"
        case .portfolioGain:
            return "PORTFOLIO GAIN"
        case .btcMajorMove:
            return "BTC MOVE"
        case .sentimentShift:
            return "SENTIMENT"
        case .marketWideMove:
            return "MARKET"
        case .breakingNews:
            return "NEWS"
        }
    }
    
    private var cleanedSummary: String {
        var text = event.aiSummary
        text = text.replacingOccurrences(of: "(undefined).", with: "")
        text = text.replacingOccurrences(of: "(undefined)", with: "")
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var extractedBreakingHeadline: String {
        guard event.kind == .breakingNews else { return eventTitle }
        let summary = cleanedSummary
        
        if let firstQuote = summary.firstIndex(of: "\""),
           let lastQuote = summary.lastIndex(of: "\""),
           firstQuote < lastQuote {
            let start = summary.index(after: firstQuote)
            let headline = String(summary[start..<lastQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !headline.isEmpty { return headline }
        }
        
        if summary.lowercased().hasPrefix("breaking news:") {
            let trimmed = summary.dropFirst("breaking news:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        
        return "Breaking News Update"
    }
    
    private var summaryBodyText: String {
        let cleaned = cleanedSummary
        if event.kind == .breakingNews {
            let headline = extractedBreakingHeadline
            // If the entire summary is just the headline, nothing extra to show.
            let remaining = cleaned
                .replacingOccurrences(of: "\"\(headline)\"", with: "")
                .replacingOccurrences(of: headline, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "–—-.:"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remaining.count > 10 ? remaining : ""
        }
        return cleaned
    }
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(event.timestamp)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Compact icon
            ZStack {
                Circle()
                    .fill(eventColor.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: eventIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(eventColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Top row: kind pill + time
                HStack(spacing: 5) {
                    Text(eventKindLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(eventColor)
                    
                    Text("·")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    Text(timeAgo)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    Text("AI")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [aiColor, aiColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                
                // Title
                Text(eventTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Body (if any extra context beyond the title)
                if !summaryBodyText.isEmpty {
                    Text(summaryBodyText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: NotificationsDesign.innerCardCornerRadius, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.09)
                        : Color(white: 0.97)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotificationsDesign.innerCardCornerRadius, style: .continuous)
                .stroke(
                    eventColor.opacity(colorScheme == .dark ? 0.18 : 0.12),
                    lineWidth: 0.7
                )
        )
    }
}

#Preview {
    NavigationStack {
        NotificationsView()
    }
    .preferredColorScheme(.dark)
}

//
//  AgentSettingsView.swift
//  CryptoSage
//
//  AI Agent connection management — generate/revoke API keys,
//  view agent status, recent trades, signals, and send commands.
//

import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject private var agentService = AgentConnectionService.shared
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var agentName = AgentConfig.defaultAgentName
    @State private var generatedKey: String?
    @State private var showingGenerateSheet = false
    @State private var showingRevokeConfirm = false
    @State private var keyToRevoke: String?
    @State private var isGenerating = false
    @State private var showCopied = false
    @State private var errorMessage: String?
    @State private var checkmarkScale: CGFloat = 0.01

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                agentStatusSection
                apiKeysSection
                recentActivitySection
                commandsSection
                helpSection
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
        .navigationTitle("Agent Connection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Start Firestore listeners IMMEDIATELY — don't block on Cloud Function
            if let userId = authManager.currentUser?.id {
                agentService.startListening(userId: userId)
            }
            // Load API keys with timeout (Cloud Functions cold-start can take 60s+)
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await agentService.loadApiKeys() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 8_000_000_000) // 8s timeout
                        throw CancellationError()
                    }
                    // Whichever finishes first wins
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                #if DEBUG
                print("[AgentSettingsView] loadApiKeys timed out or failed: \(error)")
                #endif
            }
        }
        .onDisappear {
            agentService.stopListening()
        }
        .sheet(isPresented: $showingGenerateSheet) {
            generateKeySheet
        }
        .alert("Delete API Key?", isPresented: $showingRevokeConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let keyId = keyToRevoke {
                    Task { try? await agentService.revokeApiKey(keyId: keyId) }
                }
            }
        } message: {
            Text("This key will be permanently deleted. Any agent using it will lose access immediately.")
        }
    }

    // MARK: - Agent Status

    private var agentStatusSection: some View {
        SettingsSection(title: "STATUS") {
            if let status = agentService.agentStatus {
                // Connected agent with status data
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(status.statusColor.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(status.statusColor)
                                .frame(width: 10, height: 10)
                                .shadow(color: status.statusColor.opacity(0.6), radius: 4)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.agent_name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            HStack(spacing: 6) {
                                Text(status.statusDisplayName)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(status.statusColor)
                                if status.circuit_breaker_active {
                                    Image(systemName: "exclamationmark.shield.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        Spacer()

                        if let heartbeat = status.last_heartbeat {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(heartbeat, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text("last seen")
                                    .font(.system(size: 9))
                                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Stats row
                    if status.daily_pnl != nil || status.open_positions != nil || status.session_count != nil {
                        SettingsDivider()
                        HStack(spacing: 0) {
                            if let pnl = status.daily_pnl {
                                statBadge(
                                    label: "Daily P&L",
                                    value: String(format: "%@$%.2f", pnl >= 0 ? "+" : "-", abs(pnl)),
                                    color: pnl >= 0 ? .green : .red
                                )
                            }
                            if let positions = status.open_positions {
                                if status.daily_pnl != nil {
                                    Spacer()
                                    Rectangle()
                                        .fill(DS.Adaptive.stroke)
                                        .frame(width: 0.5, height: 28)
                                    Spacer()
                                }
                                statBadge(
                                    label: "Positions",
                                    value: "\(positions)",
                                    color: DS.Adaptive.textPrimary
                                )
                            }
                            if let sessions = status.session_count {
                                if status.daily_pnl != nil || status.open_positions != nil {
                                    Spacer()
                                    Rectangle()
                                        .fill(DS.Adaptive.stroke)
                                        .frame(width: 0.5, height: 28)
                                    Spacer()
                                }
                                statBadge(
                                    label: "Sessions",
                                    value: "\(sessions)",
                                    color: DS.Adaptive.textPrimary
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Agent note
                    if let note = status.note, !note.isEmpty {
                        SettingsDivider()
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(note)
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else if agentService.isConnected {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 15))
                            .foregroundColor(.yellow)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Listening")
                            .font(.body.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Waiting for agent heartbeat...")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(DS.Adaptive.textTertiary.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "power")
                            .font(.system(size: 15))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No Agent Connected")
                            .font(.body.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Generate an API key to get started")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.caption.weight(.bold).monospaced())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - API Keys

    /// Active API keys (cached to avoid repeated filtering)
    private var activeKeys: [AgentApiKeyInfo] {
        agentService.apiKeys.filter(\.isActive)
    }

    private var apiKeysSection: some View {
        SettingsSection(title: "API KEYS") {
            let keys = activeKeys
            // Only active keys are shown — revoked keys are permanently deleted
            ForEach(keys) { key in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "key.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        HStack(spacing: 6) {
                            Text(key.keyPrefix + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            if let lastUsed = key.lastUsedAt {
                                Text("·")
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text("Used \(lastUsed)")
                                    .font(.system(size: 9))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                    }

                    Spacer()

                    // Trash button — permanently deletes the key
                    Button {
                        impactLight.impactOccurred()
                        keyToRevoke = key.id
                        showingRevokeConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.vertical, 4)

                if key.id != keys.last?.id {
                    SettingsDivider()
                }
            }

            if keys.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.6))
                    Text("No API keys yet")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.vertical, 8)
            }

            SettingsDivider()

            Button {
                impactLight.impactOccurred()
                errorMessage = nil
                showingGenerateSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    Text("Generate New Key")
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        Group {
            // Recent Trades
            if !agentService.recentTrades.isEmpty {
                let recentTrades = Array(agentService.recentTrades.prefix(5))
                SettingsSection(title: "RECENT TRADES") {
                    ForEach(recentTrades) { trade in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(trade.isBuy ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: trade.isBuy ? "arrow.down.left" : "arrow.up.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(trade.isBuy ? .green : .red)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(trade.action)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(trade.isBuy ? .green : .red)
                                    Text(trade.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                }
                                if !trade.reason.isEmpty {
                                    Text(trade.reason)
                                        .font(.system(size: 10))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "$%.2f", trade.price))
                                    .font(.caption.weight(.medium).monospaced())
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                if let ts = trade.timestamp {
                                    Text(ts, style: .relative)
                                        .font(.system(size: 9))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 3)

                        if trade.id != recentTrades.last?.id {
                            SettingsDivider()
                        }
                    }
                }
            }

            // Latest Signals
            if !agentService.latestSignals.isEmpty {
                let recentSignals = Array(agentService.latestSignals.prefix(3))
                SettingsSection(title: "LATEST SIGNALS") {
                    ForEach(recentSignals) { signal in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(signal.signalColor.opacity(0.12))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(signal.signalColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(signal.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    Text(signal.signalDisplayName)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(signal.signalColor)
                                }
                                if let confidence = signal.confidence {
                                    Text("Confidence: \(confidence)")
                                        .font(.system(size: 10))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f", signal.composite_score))
                                    .font(.caption.weight(.bold).monospaced())
                                    .foregroundColor(signal.signalColor)
                                if let ts = signal.timestamp {
                                    Text(ts, style: .relative)
                                        .font(.system(size: 9))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 3)

                        if signal.id != recentSignals.last?.id {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Commands

    private var commandsSection: some View {
        Group {
            if agentService.isAgentOnline {
                SettingsSection(title: "COMMANDS") {
                    commandButton(title: "Run Scan Now", icon: "magnifyingglass", type: "RUN_SCAN")
                    SettingsDivider()
                    commandButton(title: "Request Report", icon: "doc.text", type: "REQUEST_REPORT")
                    SettingsDivider()
                    commandButton(title: "Pause Trading", icon: "pause.circle", type: "PAUSE")
                    SettingsDivider()
                    commandButton(title: "Resume Trading", icon: "play.circle", type: "RESUME")
                }
            }
        }
    }

    private func commandButton(title: String, icon: String, type: String) -> some View {
        Button {
            impactMedium.impactOccurred()
            guard let userId = authManager.currentUser?.id else { return }
            Task { try? await agentService.sendCommand(userId: userId, type: type) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BrandColors.goldBase.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(BrandColors.goldBase)
                }
                Text(title)
                    .font(.body)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Help Section

    private var helpSection: some View {
        SettingsSection(title: "HOW IT WORKS") {
            VStack(alignment: .leading, spacing: 12) {
                helpStep(number: "1", text: "Generate an API key above", icon: "key.fill")
                helpStep(number: "2", text: "Paste the key into your agent's config", icon: "doc.on.clipboard")
                helpStep(number: "3", text: "Your agent sends trades & signals here", icon: "arrow.left.arrow.right")
            }
            .padding(.vertical, 6)

            SettingsDivider()

            // Capabilities info
            VStack(alignment: .leading, spacing: 8) {
                Text("AGENT CAPABILITIES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.top, 4)

                capabilityRow(icon: "chart.line.uptrend.xyaxis", text: "Push portfolio & trade data")
                capabilityRow(icon: "waveform.path.ecg", text: "Send market signals & analysis")
                capabilityRow(icon: "banknote", text: "Execute paper trades through app")
                capabilityRow(icon: "bell.badge", text: "Receive push notifications for trades")
                capabilityRow(icon: "command", text: "Accept commands from app (scan, pause, resume)")
            }
            .padding(.vertical, 4)
        }
    }

    private func helpStep(number: String, text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundColor(BrandColors.goldBase)
                .frame(width: 22, height: 22)
                .background(BrandColors.goldBase.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
        }
    }

    private func capabilityRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BrandColors.goldBase.opacity(0.7))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }

    // MARK: - Generate Key Sheet

    private var generateKeySheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let key = generatedKey {
                    // ── Success state ──
                    ScrollView {
                        VStack(spacing: 22) {
                            Spacer().frame(height: 20)

                            // Animated checkmark
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.08))
                                    .frame(width: 88, height: 88)
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.green)
                                    .scaleEffect(checkmarkScale)
                            }
                            .onAppear {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
                                    checkmarkScale = 1.0
                                }
                            }

                            VStack(spacing: 6) {
                                Text("API Key Generated")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(DS.Adaptive.textPrimary)

                                Text("Copy this key now — it won't be shown again.")
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            // Key display card
                            VStack(spacing: 0) {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                    .padding(16)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(DS.Adaptive.cardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(BrandColors.goldBase.opacity(0.25), lineWidth: 1)
                                            )
                                    )
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 24)

                            // Copy button
                            Button {
                                UIPasteboard.general.string = key
                                notificationFeedback.notificationOccurred(.success)
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopied = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .semibold))
                                        .contentTransition(.symbolEffect(.replace))
                                    Text(showCopied ? "Copied!" : "Copy to Clipboard")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(BrandColors.goldBase)
                                )
                            }
                            .padding(.horizontal, 24)

                            // Instructions card
                            VStack(spacing: 8) {
                                Text("Next Step")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(DS.Adaptive.textSecondary)

                                Text("Paste this key into your agent's config file:")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                    .multilineTextAlignment(.center)

                                Text("config/firebase_agent.json")
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .foregroundColor(BrandColors.goldBase)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(BrandColors.goldBase.opacity(0.08))
                                    )
                            }
                            .padding(.top, 4)

                            // Security notice
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 12))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text("Keep this key secret. Revoke it anytime from this screen.")
                                    .font(.system(size: 10))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            .padding(.horizontal, 24)

                            Spacer()
                        }
                    }
                } else {
                    // ── Input state ──
                    VStack(spacing: 24) {
                        Spacer().frame(height: 16)

                        // Icon
                        ZStack {
                            Circle()
                                .fill(BrandColors.goldBase.opacity(0.08))
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(BrandColors.goldBase.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "key.fill")
                                .font(.system(size: 24))
                                .foregroundColor(BrandColors.goldBase)
                        }

                        VStack(spacing: 8) {
                            Text("Connect Your AI Agent")
                                .font(.title3.weight(.bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text("Generate a secure API key for your trading agent to communicate with CryptoSage.")
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        // Agent name field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AGENT NAME")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                                .padding(.leading, 4)

                            TextField(AgentConfig.defaultAgentName, text: $agentName)
                                .font(.body)
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(DS.Adaptive.cardBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                                        )
                                )
                        }
                        .padding(.horizontal, 24)

                        // Generate button
                        Button {
                            Task {
                                isGenerating = true
                                errorMessage = nil
                                checkmarkScale = 0.01
                                do {
                                    let key = try await agentService.generateApiKey(name: agentName)
                                    generatedKey = key
                                    notificationFeedback.notificationOccurred(.success)
                                } catch {
                                    errorMessage = error.localizedDescription
                                    notificationFeedback.notificationOccurred(.error)
                                }
                                isGenerating = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isGenerating {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Generate API Key")
                                        .font(.subheadline.weight(.bold))
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        (isGenerating || agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                                            ? BrandColors.goldBase.opacity(0.4)
                                            : BrandColors.goldBase
                                    )
                            )
                        }
                        .disabled(isGenerating || agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.horizontal, 24)

                        // Error message
                        if let err = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                                    )
                            )
                            .padding(.horizontal, 24)
                        }

                        Spacer()
                    }
                }
            }
            .background(DS.Adaptive.background)
            .navigationTitle(generatedKey != nil ? "Key Created" : "New API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingGenerateSheet = false
                        generatedKey = nil
                        agentName = AgentConfig.defaultAgentName
                        errorMessage = nil
                        checkmarkScale = 0.01
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AgentSettingsView()
    }
}

//
//  AgentSettingsView.swift
//  CryptoSage
//
//  AI Agent connection management — generate/revoke API keys,
//  view agent status, send commands.
//

import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject private var agentService = AgentConnectionService.shared
    @ObservedObject private var authManager = AuthenticationManager.shared

    @State private var agentName = "Sage Trader"
    @State private var generatedKey: String?
    @State private var showingGenerateSheet = false
    @State private var showingRevokeConfirm = false
    @State private var keyToRevoke: String?
    @State private var isGenerating = false
    @State private var showCopied = false
    @State private var errorMessage: String?

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                agentStatusSection
                apiKeysSection
                commandsSection
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
        .navigationTitle("AI Agent")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                try await agentService.loadApiKeys()
                if let userId = authManager.userId {
                    agentService.startListening(userId: userId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            generateKeySheet
        }
        .alert("Revoke API Key?", isPresented: $showingRevokeConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Revoke", role: .destructive) {
                if let keyId = keyToRevoke {
                    Task { try? await agentService.revokeApiKey(keyId: keyId) }
                }
            }
        } message: {
            Text("The agent using this key will lose access immediately.")
        }
    }

    // MARK: - Agent Status

    private var agentStatusSection: some View {
        SettingsSection(title: "AGENT STATUS") {
            if let status = agentService.agentStatus {
                HStack(spacing: 12) {
                    Circle()
                        .fill(status.statusColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.agent_name)
                            .font(.body.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(status.statusDisplayName)
                            .font(.caption)
                            .foregroundColor(status.statusColor)
                    }

                    Spacer()

                    if let heartbeat = status.last_heartbeat {
                        Text(heartbeat, style: .relative)
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .padding(.vertical, 4)

                if let pnl = status.daily_pnl {
                    SettingsDivider()
                    HStack {
                        Text("Daily P&L")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text(String(format: "%@$%.2f", pnl >= 0 ? "+" : "", pnl))
                            .font(.caption.weight(.medium))
                            .foregroundColor(pnl >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 2)
                }
            } else if agentService.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.gray)
                    Text("Waiting for agent heartbeat...")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .foregroundColor(.gray)
                    Text("No agent connected")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        SettingsSection(title: "API KEYS") {
            ForEach(agentService.apiKeys) { key in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(key.keyPrefix + "...")
                            .font(.caption.monospaced())
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }

                    Spacer()

                    if key.isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())

                        Button {
                            keyToRevoke = key.id
                            showingRevokeConfirm = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                        }
                    } else {
                        Text("Revoked")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)

                if key.id != agentService.apiKeys.last?.id {
                    SettingsDivider()
                }
            }

            if agentService.apiKeys.isEmpty {
                Text("Generate an API key to connect your AI agent")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.vertical, 4)
            }

            SettingsDivider()

            Button {
                impactLight.impactOccurred()
                showingGenerateSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(BrandColors.goldBase)
                    Text("Generate New Key")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(BrandColors.goldBase)
                    Spacer()
                }
            }
            .padding(.vertical, 4)
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
            impactLight.impactOccurred()
            guard let userId = authManager.userId else { return }
            Task { try? await agentService.sendCommand(userId: userId, type: type) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(BrandColors.goldBase)
                    .frame(width: 30)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Generate Key Sheet

    private var generateKeySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let key = generatedKey {
                    // Show generated key
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("API Key Generated")
                            .font(.title3.weight(.semibold))

                        Text("Copy this key now — it won't be shown again.")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)

                        Text(key)
                            .font(.system(.caption, design: .monospaced))
                            .padding(12)
                            .background(DS.Adaptive.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = key
                            notificationFeedback.notificationOccurred(.success)
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopied = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                Text(showCopied ? "Copied!" : "Copy to Clipboard")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(BrandColors.goldBase)
                            .clipShape(Capsule())
                        }
                    }
                    .padding()
                } else {
                    // Name input
                    VStack(spacing: 16) {
                        Text("Connect your AI agent to CryptoSage")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)

                        TextField("Agent Name", text: $agentName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        Button {
                            Task {
                                isGenerating = true
                                do {
                                    let key = try await agentService.generateApiKey(name: agentName)
                                    generatedKey = key
                                    notificationFeedback.notificationOccurred(.success)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isGenerating = false
                            }
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "key.fill")
                                    Text("Generate API Key")
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BrandColors.goldBase)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isGenerating || agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                }

                Spacer()

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .background(DS.Adaptive.background)
            .navigationTitle("New API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingGenerateSheet = false
                        generatedKey = nil
                        agentName = "Sage Trader"
                    }
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

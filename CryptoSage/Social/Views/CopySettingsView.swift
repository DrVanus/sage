//
//  CopySettingsView.swift
//  CryptoSage
//
//  Settings view for copy trading risk management and preferences.
//

import SwiftUI

struct CopySettingsView: View {
    let copiedBot: CopiedBotInfo
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var copyTradingManager = CopyTradingManager.shared
    
    // Risk Management Settings
    @State private var maxAllocation: Double = 1000
    @State private var allocationMode: AllocationMode = .proportional
    @State private var stopLossEnabled: Bool = true
    @State private var stopLossPercent: Double = 15
    @State private var takeProfitEnabled: Bool = false
    @State private var takeProfitPercent: Double = 50
    @State private var maxDrawdownEnabled: Bool = true
    @State private var maxDrawdownPercent: Double = 20
    @State private var autoPauseOnDrawdown: Bool = true
    
    // Sync Settings
    @State private var syncEnabled: Bool = false
    @State private var syncFrequency: SyncFrequency = .hourly
    
    // Notification Settings
    @State private var notifyOnTrade: Bool = true
    @State private var notifyOnProfit: Bool = true
    @State private var notifyOnLoss: Bool = true
    @State private var notifyOnPause: Bool = true
    
    @State private var showingSaveConfirmation = false
    
    enum AllocationMode: String, CaseIterable {
        case proportional = "Proportional"
        case fixed = "Fixed Amount"
        
        var description: String {
            switch self {
            case .proportional:
                return "Copy trades proportionally based on your allocation vs creator's"
            case .fixed:
                return "Use a fixed amount for each trade"
            }
        }
    }
    
    enum SyncFrequency: String, CaseIterable {
        case realtime = "Real-time"
        case hourly = "Hourly"
        case daily = "Daily"
        case manual = "Manual Only"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Bot Info Header
                    botInfoHeader
                    
                    // Risk Management Section
                    riskManagementSection
                    
                    // Allocation Settings
                    allocationSection
                    
                    // Sync Settings
                    syncSettingsSection
                    
                    // Notification Settings
                    notificationSection
                    
                    // Danger Zone
                    dangerZoneSection
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("Copy Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button { saveSettings() } label: {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your copy trading settings have been updated.")
            }
        }
    }
    
    // MARK: - Bot Info Header
    
    private var botInfoHeader: some View {
        HStack(spacing: 16) {
            // Bot icon placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(copiedBot.originalBotName)
                    .font(.headline)
                
                Text("by @\(copiedBot.originalCreatorUsername)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Label("Copied \(copiedBot.daysSinceCopy)d ago", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let lastSync = copiedBot.timeSinceLastSync {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("Synced \(lastSync)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Risk Management Section
    
    private var riskManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Risk Management", icon: "shield.checkered")
            
            // Stop Loss
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $stopLossEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop Loss")
                                .font(.subheadline.weight(.medium))
                            Text("Automatically close position at loss threshold")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.red)
                
                if stopLossEnabled {
                    sliderWithValue(
                        value: $stopLossPercent,
                        range: 5...50,
                        label: "Stop at",
                        suffix: "% loss",
                        color: .red
                    )
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
            }
            
            // Take Profit
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $takeProfitEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take Profit")
                                .font(.subheadline.weight(.medium))
                            Text("Automatically close position at profit target")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.green)
                
                if takeProfitEnabled {
                    sliderWithValue(
                        value: $takeProfitPercent,
                        range: 10...200,
                        label: "Target",
                        suffix: "% profit",
                        color: .green
                    )
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
            }
            
            // Max Drawdown
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $maxDrawdownEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.line.downtrend.xyaxis.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max Drawdown Protection")
                                .font(.subheadline.weight(.medium))
                            Text("Pause bot when total drawdown exceeds limit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.orange)
                
                if maxDrawdownEnabled {
                    sliderWithValue(
                        value: $maxDrawdownPercent,
                        range: 10...50,
                        label: "Pause at",
                        suffix: "% drawdown",
                        color: .orange
                    )
                    
                    Toggle("Auto-pause when exceeded", isOn: $autoPauseOnDrawdown)
                        .font(.subheadline)
                        .tint(.orange)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Allocation Section
    
    private var maxAllocationInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maximum Allocation")
                .font(.subheadline.weight(.medium))
            
            HStack {
                let inputBackground = colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96)
                TextField("Amount", value: $maxAllocation, format: .currency(code: "USD"))
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(inputBackground)
                    )
                
                VStack(spacing: 4) {
                    Button {
                        maxAllocation = min(maxAllocation + 100, 100000)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button {
                        maxAllocation = max(maxAllocation - 100, 100)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            Text("This is the maximum amount that can be used for this copied bot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func allocationModeRow(mode: AllocationMode) -> some View {
        let isSelected = allocationMode == mode
        let rowBackground = isSelected 
            ? Color.accentColor.opacity(0.1) 
            : (colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        let borderColor = isSelected ? Color.accentColor.opacity(0.3) : Color.clear
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                allocationMode = mode
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var allocationModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allocation Mode")
                .font(.subheadline.weight(.medium))
            
            ForEach(AllocationMode.allCases, id: \.self) { mode in
                allocationModeRow(mode: mode)
            }
        }
    }
    
    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Allocation", icon: "chart.pie.fill")
            maxAllocationInput
            Divider()
            allocationModeSelector
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Sync Settings Section
    
    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Sync Settings", icon: "arrow.triangle.2.circlepath")
            
            Toggle(isOn: $syncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Sync Enabled")
                        .font(.subheadline.weight(.medium))
                    Text("Automatically sync with creator's latest settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
            .onChange(of: syncEnabled) { _, newValue in
                if newValue {
                    copyTradingManager.enableSync(localBotId: copiedBot.localBotId)
                } else {
                    copyTradingManager.disableSync(localBotId: copiedBot.localBotId)
                }
            }
            
            if syncEnabled {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync Frequency")
                        .font(.subheadline.weight(.medium))
                    
                    HStack(spacing: 8) {
                        ForEach(SyncFrequency.allCases, id: \.self) { frequency in
                            Button {
                                syncFrequency = frequency
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Text(frequency.rawValue)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(syncFrequency == frequency 
                                                ? Color.accentColor 
                                                : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.93)))
                                    )
                                    .foregroundStyle(syncFrequency == frequency ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Notification Section
    
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Notifications", icon: "bell.fill")
            
            Toggle("Trade Executed", isOn: $notifyOnTrade)
                .font(.subheadline)
            
            Toggle("Profit Milestone", isOn: $notifyOnProfit)
                .font(.subheadline)
            
            Toggle("Loss Alert", isOn: $notifyOnLoss)
                .font(.subheadline)
            
            Toggle("Bot Paused", isOn: $notifyOnPause)
                .font(.subheadline)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Danger Zone Section
    
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Danger Zone", icon: "exclamationmark.triangle.fill", color: .red)
            
            Button {
                // Pause bot
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            } label: {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                    Text("Pause Bot")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.orange)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            Button {
                // Remove copied bot
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                    Text("Remove Copied Bot")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.red)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String, color: Color = .accentColor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
            
            Text(title)
                .font(.headline)
        }
    }
    
    private func sliderWithValue(value: Binding<Double>, range: ClosedRange<Double>, label: String, suffix: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(value.wrappedValue))\(suffix)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            
            Slider(value: value, in: range, step: 1)
                .tint(color)
        }
        .padding(.leading, 36)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
    
    private func saveSettings() {
        // In production, save settings to CopyTradingManager
        showingSaveConfirmation = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

#Preview {
    CopySettingsView(copiedBot: CopiedBotInfo(
        id: UUID(),
        originalBotId: UUID(),
        originalBotName: "BTC Weekly DCA",
        originalCreatorId: UUID(),
        originalCreatorUsername: "crypto_whale",
        localBotId: UUID(),
        copiedAt: Date().addingTimeInterval(-86400 * 7),
        syncEnabled: true,
        lastSyncAt: Date().addingTimeInterval(-3600),
        originalConfig: [:],
        originalPerformance: BotPerformanceStats()
    ))
}

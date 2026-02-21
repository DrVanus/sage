//
//  StrategyBuilderView.swift
//  CryptoSage
//
//  Visual Strategy Builder UI for creating and configuring
//  algorithmic trading strategies with indicator conditions.
//

import SwiftUI

// MARK: - Strategy Builder View

struct StrategyBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var viewModel: StrategyBuilderViewModel
    
    @State private var showingConditionPicker = false
    @State private var showingIndicatorInfo = false
    @State private var editingConditionId: UUID?
    @State private var isEntryCondition = true
    @State private var showingValidationErrors = false
    @State private var showingLiveTradingWarning = false
    
    init(existingStrategy: TradingStrategy? = nil) {
        _viewModel = StateObject(wrappedValue: StrategyBuilderViewModel(strategy: existingStrategy))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Strategy name and basic info
                    basicInfoSection
                    
                    // Trading pair and timeframe
                    tradingConfigSection
                    
                    // Entry conditions
                    conditionsSection(
                        title: "Entry Conditions",
                        subtitle: "When to open a position",
                        conditions: $viewModel.strategy.entryConditions,
                        isEntry: true
                    )
                    
                    // Exit conditions
                    conditionsSection(
                        title: "Exit Conditions",
                        subtitle: "When to close a position",
                        conditions: $viewModel.strategy.exitConditions,
                        isEntry: false
                    )
                    
                    // Risk management
                    riskManagementSection
                    
                    // Position sizing
                    positionSizingSection
                    
                    // Preview / summary
                    strategySummarySection
                    
                    // Educational disclaimer
                    deploymentAdvisoryNotice
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background)
            .navigationTitle(viewModel.isEditing ? "Edit Strategy" : "Create Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            saveStrategy()
                        } label: {
                            Label("Save Strategy", systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            // Check if live trading is enabled - show warning
                            if AppConfig.liveTradingEnabled {
                                showingLiveTradingWarning = true
                            } else {
                                saveAndDeployStrategy()
                            }
                        } label: {
                            if AppConfig.liveTradingEnabled {
                                Label("Save & Deploy to Live Trading", systemImage: "bolt.circle")
                            } else {
                                Label("Save & Deploy to Paper Trading", systemImage: "play.circle")
                            }
                        }
                    } label: {
                        Text("Save")
                            .font(.headline)
                            .foregroundColor(BrandColors.goldBase)
                    }
                }
            }
            .sheet(isPresented: $showingConditionPicker) {
                ConditionPickerSheet(
                    isEntryCondition: isEntryCondition,
                    onSelect: { condition in
                        if isEntryCondition {
                            viewModel.strategy.entryConditions.append(condition)
                        } else {
                            viewModel.strategy.exitConditions.append(condition)
                        }
                    }
                )
            }
            .alert("Validation Errors", isPresented: $showingValidationErrors) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.validationErrors.joined(separator: "\n"))
            }
            .alert("Live Trading Warning", isPresented: $showingLiveTradingWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Deploy to Live", role: .destructive) {
                    saveAndDeployStrategy()
                }
            } message: {
                Text("You are in DEVELOPER MODE with LIVE TRADING enabled.\n\nThis strategy will execute REAL trades with REAL money on your connected exchange.\n\nAre you sure you want to deploy this strategy?")
            }
        }
    }
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Strategy Details", icon: "doc.text")
            
            VStack(spacing: 12) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strategy Name")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("My Strategy", text: $viewModel.strategy.name)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(12)
                        .background(DS.Adaptive.overlay(0.05))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                }
                
                // Description field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (Optional)")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("Describe your strategy...", text: $viewModel.strategy.description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(DS.Adaptive.overlay(0.05))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Trading Config Section
    
    private var tradingConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Trading Configuration", icon: "gearshape")
            
            VStack(spacing: 12) {
                // Trading pair picker
                HStack {
                    Text("Trading Pair")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(viewModel.availablePairs, id: \.self) { pair in
                            Button(pair) {
                                viewModel.strategy.tradingPair = pair
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.strategy.tradingPair)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DS.Adaptive.overlay(0.08))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Timeframe picker
                HStack {
                    Text("Timeframe")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(StrategyTimeframe.allCases, id: \.self) { tf in
                            Button(tf.displayName) {
                                viewModel.strategy.timeframe = tf
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.strategy.timeframe.displayName)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DS.Adaptive.overlay(0.08))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Condition logic
                HStack {
                    Text("Condition Logic")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Picker("", selection: $viewModel.strategy.conditionLogic) {
                        ForEach(ConditionLogic.allCases, id: \.self) { logic in
                            Text(logic.shortName).tag(logic)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Conditions Section
    
    private func conditionsSection(
        title: String,
        subtitle: String,
        conditions: Binding<[StrategyCondition]>,
        isEntry: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    title: title,
                    icon: isEntry ? "arrow.right.circle" : "arrow.left.circle"
                )
                Spacer()
                Button {
                    isEntryCondition = isEntry
                    showingConditionPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(BrandColors.goldBase)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BrandColors.goldBase.opacity(0.15))
                    .cornerRadius(8)
                }
            }
            
            VStack(spacing: 8) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if conditions.wrappedValue.isEmpty {
                    emptyConditionsView(isEntry: isEntry)
                } else {
                    ForEach(conditions) { $condition in
                        ConditionRow(
                            condition: $condition,
                            onDelete: {
                                conditions.wrappedValue.removeAll { $0.id == condition.id }
                            }
                        )
                    }
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    private func emptyConditionsView(isEntry: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: isEntry ? "arrow.right.circle" : "arrow.left.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("No conditions added")
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(isEntry ? "Define when to enter a trade" : "Define when to exit a trade")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BrandColors.goldBase.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }
    
    // MARK: - Risk Management Section
    
    private var riskManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Risk Management", icon: "shield.checkered")
            
            VStack(spacing: 16) {
                // Stop Loss
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Stop Loss")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.strategy.riskManagement.stopLossPercent != nil },
                            set: { enabled in
                                viewModel.strategy.riskManagement.stopLossPercent = enabled ? 5.0 : nil
                            }
                        ))
                        .tint(BrandColors.goldBase)
                    }
                    
                    if let stopLoss = viewModel.strategy.riskManagement.stopLossPercent {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { stopLoss },
                                    set: { viewModel.strategy.riskManagement.stopLossPercent = $0 }
                                ),
                                in: 1...20,
                                step: 0.5
                            )
                            .tint(Color.red)
                            
                            Text("\(stopLoss, specifier: "%.1f")%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.red)
                                .frame(width: 50)
                        }
                    }
                }
                
                Divider()
                
                // Take Profit
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Take Profit")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.strategy.riskManagement.takeProfitPercent != nil },
                            set: { enabled in
                                viewModel.strategy.riskManagement.takeProfitPercent = enabled ? 10.0 : nil
                            }
                        ))
                        .tint(BrandColors.goldBase)
                    }
                    
                    if let takeProfit = viewModel.strategy.riskManagement.takeProfitPercent {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { takeProfit },
                                    set: { viewModel.strategy.riskManagement.takeProfitPercent = $0 }
                                ),
                                in: 1...50,
                                step: 0.5
                            )
                            .tint(Color.green)
                            
                            Text("\(takeProfit, specifier: "%.1f")%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.green)
                                .frame(width: 50)
                        }
                    }
                }
                
                // Risk/Reward display
                if let rr = viewModel.strategy.riskManagement.riskRewardRatio {
                    HStack {
                        Text("Risk/Reward")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text("1:\(rr, specifier: "%.1f")")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(rr >= 2 ? .green : (rr >= 1 ? .orange : .red))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Position Sizing Section
    
    private var positionSizingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Position Sizing", icon: "chart.pie")
            
            VStack(spacing: 16) {
                // Sizing method
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sizing Method")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Picker("", selection: $viewModel.strategy.positionSizing.method) {
                        ForEach(PositionSizingMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Divider()
                
                // Dynamic sizing control based on method
                switch viewModel.strategy.positionSizing.method {
                case .fixedAmount:
                    HStack {
                        Text("Trade Amount")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("$")
                                .foregroundColor(DS.Adaptive.textSecondary)
                            TextField("100", value: $viewModel.strategy.positionSizing.fixedAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(8)
                        .background(DS.Adaptive.overlay(0.05))
                        .cornerRadius(8)
                    }
                    
                case .percentOfPortfolio:
                    VStack(spacing: 8) {
                        HStack {
                            Text("Portfolio %")
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Spacer()
                            Text("\(viewModel.strategy.positionSizing.portfolioPercent, specifier: "%.0f")%")
                                .font(.subheadline.weight(.medium))
                        }
                        
                        Slider(
                            value: $viewModel.strategy.positionSizing.portfolioPercent,
                            in: 1...50,
                            step: 1
                        )
                        .tint(BrandColors.goldBase)
                    }
                    
                case .riskBased:
                    VStack(spacing: 8) {
                        HStack {
                            Text("Risk per Trade")
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Spacer()
                            Text("\(viewModel.strategy.positionSizing.riskPercent, specifier: "%.1f")%")
                                .font(.subheadline.weight(.medium))
                        }
                        
                        Slider(
                            value: $viewModel.strategy.positionSizing.riskPercent,
                            in: 0.5...5,
                            step: 0.5
                        )
                        .tint(BrandColors.goldBase)
                        
                        Text("Position size calculated from stop loss distance")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                Divider()
                
                // Max position
                HStack {
                    Text("Max Position")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Text("\(viewModel.strategy.positionSizing.maxPositionPercent, specifier: "%.0f")% of portfolio")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Strategy Summary Section
    
    private var strategySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Strategy Summary", icon: "list.clipboard")
            
            VStack(spacing: 12) {
                summaryRow("Pair", viewModel.strategy.tradingPair)
                summaryRow("Timeframe", viewModel.strategy.timeframe.displayName)
                summaryRow("Entry Conditions", "\(viewModel.strategy.entryConditions.count)")
                summaryRow("Exit Conditions", "\(viewModel.strategy.exitConditions.count)")
                
                if let sl = viewModel.strategy.riskManagement.stopLossPercent {
                    summaryRow("Stop Loss", String(format: "%.1f%%", sl))
                }
                
                if let tp = viewModel.strategy.riskManagement.takeProfitPercent {
                    summaryRow("Take Profit", String(format: "%.1f%%", tp))
                }
                
                Divider()
                
                // Validation status
                HStack {
                    let errors = StrategyEngine.shared.validateStrategy(viewModel.strategy)
                    if errors.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Strategy is valid")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(errors.count) issue(s) found")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Deployment Advisory Notice
    
    private var deploymentAdvisoryNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
                
                Text("About Strategy Deployment")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("When you deploy this strategy:")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    advisoryRow(icon: "play.circle.fill", color: .green, text: "It will run in Paper Trading mode with virtual funds")
                    advisoryRow(icon: "bell.badge.fill", color: .orange, text: "You'll receive signals when conditions trigger")
                    advisoryRow(icon: "square.and.arrow.up", color: .blue, text: "Copy signals to use as advisory for your own trading")
                    advisoryRow(icon: "chart.xyaxis.line", color: .purple, text: "Track performance to validate before using real funds")
                }
            }
            
            Divider()
            
            Text("Signals are for educational purposes. This is not financial advice. Always do your own research before trading.")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private func advisoryRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 14)
            
            Text(text)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
        }
    }
    
    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func saveStrategy() {
        viewModel.validationErrors = StrategyEngine.shared.validateStrategy(viewModel.strategy)
        
        if viewModel.validationErrors.isEmpty {
            StrategyEngine.shared.saveStrategy(viewModel.strategy)
            dismiss()
        } else {
            showingValidationErrors = true
        }
    }
    
    private func saveAndDeployStrategy() {
        viewModel.validationErrors = StrategyEngine.shared.validateStrategy(viewModel.strategy)
        
        if viewModel.validationErrors.isEmpty {
            // Save the strategy
            StrategyEngine.shared.saveStrategy(viewModel.strategy)
            
            // Check trading mode
            let isLiveTradingEnabled = AppConfig.liveTradingEnabled
            let isPaperTradingEnabled = PaperTradingManager.isEnabled
            
            // Live trading mode (developer mode)
            if isLiveTradingEnabled {
                // For now, live trading still uses paper bot infrastructure
                // but in a "live" context. In a full implementation, this would
                // connect to the actual exchange execution service.
                
                // Create and start a bot from the strategy
                let bot = PaperBotManager.shared.createBotFromStrategy(viewModel.strategy)
                PaperBotManager.shared.startBot(id: bot.id)
                
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                
                dismiss()
                return
            }
            
            // Paper trading mode
            guard isPaperTradingEnabled else {
                viewModel.validationErrors = ["Paper trading must be enabled to deploy strategies. Go to Settings to enable it."]
                showingValidationErrors = true
                return
            }
            
            // Create and start a paper bot from the strategy
            let bot = PaperBotManager.shared.createBotFromStrategy(viewModel.strategy)
            PaperBotManager.shared.startBot(id: bot.id)
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            
            dismiss()
        } else {
            showingValidationErrors = true
        }
    }
}

// MARK: - Condition Row

struct ConditionRow: View {
    @Binding var condition: StrategyCondition
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Enable/disable toggle
            Button {
                condition.isEnabled.toggle()
            } label: {
                Image(systemName: condition.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(condition.isEnabled ? BrandColors.goldBase : DS.Adaptive.textTertiary)
            }
            
            // Condition description
            VStack(alignment: .leading, spacing: 2) {
                Text(condition.indicator.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(condition.isEnabled ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                
                HStack(spacing: 4) {
                    Text(condition.comparison.symbol)
                        .foregroundColor(condition.indicator.category.color)
                    Text(condition.value.displayValue)
                }
                .font(.caption)
                .foregroundColor(condition.isEnabled ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Category badge
            Text(condition.indicator.category.rawValue)
                .font(.caption2)
                .foregroundColor(condition.indicator.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(condition.indicator.category.color.opacity(0.15))
                .cornerRadius(6)
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(12)
        .background(DS.Adaptive.overlay(condition.isEnabled ? 0.04 : 0.02))
        .cornerRadius(10)
        .opacity(condition.isEnabled ? 1 : 0.6)
    }
}

// MARK: - Condition Picker Sheet

struct ConditionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let isEntryCondition: Bool
    let onSelect: (StrategyCondition) -> Void
    
    @State private var selectedCategory: StrategyIndicatorCategory = .oscillator
    @State private var selectedIndicator: StrategyIndicatorType = .rsi
    @State private var selectedComparison: ComparisonOperator = .lessThan
    @State private var targetValue: Double = 30
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Category picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indicator Category")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(StrategyIndicatorCategory.allCases, id: \.self) { category in
                                    CategoryPill(
                                        category: category,
                                        isSelected: selectedCategory == category
                                    ) {
                                        selectedCategory = category
                                        // Reset to first indicator in category
                                        if let first = category.indicators.first {
                                            selectedIndicator = first
                                            updateDefaultValue()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Indicator picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indicator")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(selectedCategory.indicators, id: \.self) { indicator in
                                IndicatorPill(
                                    indicator: indicator,
                                    isSelected: selectedIndicator == indicator
                                ) {
                                    selectedIndicator = indicator
                                    updateDefaultValue()
                                }
                            }
                        }
                    }
                    
                    // Comparison picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comparison")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ComparisonOperator.allCases, id: \.self) { op in
                                ComparisonPill(
                                    comparison: op,
                                    isSelected: selectedComparison == op
                                ) {
                                    selectedComparison = op
                                }
                            }
                        }
                    }
                    
                    // Value input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Value")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        if let range = selectedIndicator.valueRange {
                            VStack(spacing: 8) {
                                Slider(value: $targetValue, in: range)
                                    .tint(selectedCategory.color)
                                
                                Text("\(targetValue, specifier: "%.1f")")
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }
                            
                            // Quick presets
                            if !selectedIndicator.commonThresholds.isEmpty {
                                HStack(spacing: 8) {
                                    Text("Presets:")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                    
                                    ForEach(selectedIndicator.commonThresholds, id: \.self) { threshold in
                                        Button {
                                            targetValue = threshold
                                        } label: {
                                            Text("\(threshold, specifier: "%.0f")")
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(targetValue == threshold ? selectedCategory.color : DS.Adaptive.overlay(0.1))
                                                .foregroundColor(targetValue == threshold ? .white : DS.Adaptive.textSecondary)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        } else {
                            TextField("Value", value: $targetValue, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(DS.Adaptive.overlay(0.05))
                                .cornerRadius(12)
                        }
                    }
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Condition Preview")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        HStack {
                            Image(systemName: selectedCategory.icon)
                                .foregroundColor(selectedCategory.color)
                            Text("\(selectedIndicator.displayName) \(selectedComparison.symbol) \(targetValue, specifier: "%.1f")")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedCategory.color.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(DS.Adaptive.background)
            .navigationTitle(isEntryCondition ? "Add Entry Condition" : "Add Exit Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let condition = StrategyCondition(
                            indicator: selectedIndicator,
                            comparison: selectedComparison,
                            value: .number(targetValue)
                        )
                        onSelect(condition)
                        dismiss()
                    } label: {
                        Text("Add")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }
    
    private func updateDefaultValue() {
        // Set sensible default based on indicator
        if let thresholds = selectedIndicator.commonThresholds.first {
            targetValue = thresholds
        } else if let range = selectedIndicator.valueRange {
            targetValue = (range.lowerBound + range.upperBound) / 2
        } else {
            targetValue = 0
        }
    }
}

// MARK: - Supporting Views

struct CategoryPill: View {
    let category: StrategyIndicatorCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                Text(category.rawValue)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? category.color : DS.Adaptive.overlay(0.08))
            .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
            .cornerRadius(8)
        }
    }
}

struct IndicatorPill: View {
    let indicator: StrategyIndicatorType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(indicator.displayName)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? indicator.category.color : DS.Adaptive.overlay(0.06))
                .foregroundColor(isSelected ? .white : DS.Adaptive.textPrimary)
                .cornerRadius(8)
        }
    }
}

struct ComparisonPill: View {
    let comparison: ComparisonOperator
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(comparison.displayName)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? BrandColors.goldBase : DS.Adaptive.overlay(0.06))
                .foregroundColor(isSelected ? .black : DS.Adaptive.textPrimary)
                .cornerRadius(8)
        }
    }
}

// MARK: - View Model

@MainActor
class StrategyBuilderViewModel: ObservableObject {
    @Published var strategy: TradingStrategy
    @Published var validationErrors: [String] = []
    
    let isEditing: Bool
    
    let availablePairs = [
        "BTC_USDT", "ETH_USDT", "SOL_USDT", "BNB_USDT",
        "XRP_USDT", "ADA_USDT", "DOGE_USDT", "AVAX_USDT",
        "DOT_USDT", "LINK_USDT", "MATIC_USDT", "SHIB_USDT"
    ]
    
    init(strategy: TradingStrategy? = nil) {
        if let existing = strategy {
            self.strategy = existing
            self.isEditing = true
        } else {
            self.strategy = TradingStrategy(
                name: "",
                description: "",
                tradingPair: "BTC_USDT",
                timeframe: .oneDay
            )
            self.isEditing = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StrategyBuilderView_Previews: PreviewProvider {
    static var previews: some View {
        StrategyBuilderView()
            .preferredColorScheme(.dark)
    }
}
#endif

//
//  TaxReportView.swift
//  CryptoSage
//
//  Tax reporting dashboard UI.
//

import SwiftUI

// MARK: - Tax Report View

struct TaxReportView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @StateObject private var taxEngine = TaxEngine.shared
    @StateObject private var lotManager = TaxLotManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var selectedYear: TaxYear = .previous
    @State private var currentReport: TaxReport?
    @State private var showingExportSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingTaxLossHarvesting = false
    @State private var showingUpgradeSheet = false
    @State private var isGenerating = false
    @State private var appeared = false
    @State private var unrealizedSummary: UnrealizedSummary?
    
    /// Check if user has tax report access
    private var hasTaxReportAccess: Bool {
        subscriptionManager.hasAccess(to: .taxReports)
    }
    
    private let cardCornerRadius: CGFloat = 16
    
    /// Theme-consistent accent color (gold in dark mode, blue in light mode)
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    /// Gold gradient for back button (matches other views)
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private let availableYears: [TaxYear] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (2020...currentYear).reversed().map { TaxYear($0) }
    }()
    
    // MARK: - Demo Mode
    
    private var isDemoMode: Bool {
        demoModeManager.isDemoMode
    }
    
    private var displayedReport: TaxReport? {
        isDemoMode ? DemoTaxDataProvider.demoReport : currentReport
    }
    
    var body: some View {
        ZStack {
            // Premium background
            FuturisticBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Header
                customHeader
                
                // Demo Mode Banner
                if isDemoMode {
                    demoModeBanner
                }
                
                // Check if user has access or is in demo mode
                if hasTaxReportAccess || isDemoMode {
                    taxReportContent
                } else {
                    // Paywall for non-Pro users
                    taxReportPaywall
                }
            }
        }
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .sheet(isPresented: $showingExportSheet) {
            if let report = displayedReport {
                TaxExportSheet(report: report)
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            TaxSettingsSheet(selectedMethod: $taxEngine.accountingMethod)
        }
        .sheet(isPresented: $showingTaxLossHarvesting) {
            TaxLossHarvestingView()
                .environmentObject(portfolioVM)
        }
        .unifiedPaywallSheet(feature: .taxReports, isPresented: $showingUpgradeSheet)
        .task {
            await generateReport()
            await calculateUnrealizedGains()
        }
        .onChange(of: selectedYear) { _, _ in
            Task { await generateReport() }
        }
        .onAppear {
            // Set appeared immediately without animation to prevent
            // the year selector picker from having a "sling" effect
            appeared = true
        }
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        HStack(spacing: 0) {
            // Back button
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            // Title
            Text("Tax Report")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Export button (only show when report exists)
            if displayedReport != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Export")
            }
            
            // Settings button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(DS.Adaptive.background.opacity(0.95))
    }
    
    // MARK: - Tax Report Content (for Pro users / Demo mode)
    
    private var taxReportContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Year Selector - no animation, shows immediately to prevent picker "sling" effect
                yearSelector
            
                // Summary Cards - subtle offset animations
                if let report = displayedReport {
                    summarySection(report)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(0.05), value: appeared)
                    
                    gainsBreakdown(report)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(0.1), value: appeared)
                    
                    if !report.incomeEvents.isEmpty {
                        incomeSection(report)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.easeOut(duration: 0.35).delay(0.15), value: appeared)
                    }
                    
                    if report.hasWashSales {
                        washSalesSection(report)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)
                    }
                    
                    // Unrealized Gains Section
                    if let summary = unrealizedSummary, summary.totalCostBasis > 0 {
                        unrealizedGainsSection(summary)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.easeOut(duration: 0.35).delay(0.22), value: appeared)
                    }
                    
                    // Tax-Loss Harvesting Link
                    taxLossHarvestingSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(0.24), value: appeared)
                    
                    transactionsSection(report)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(0.26), value: appeared)
                } else if !isDemoMode {
                    emptyState
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(0.05), value: appeared)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    // MARK: - Tax Report Paywall (for free users)
    
    private var taxReportPaywall: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)
                
                // Lock icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.yellow.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldBase, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 8)
                
                // Title
                Text("Tax Reports")
                    .font(.title2.bold())
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Description
                Text("Generate comprehensive crypto tax reports with capital gains/losses, Form 8949 exports, and support for major tax software.")
                    .font(.body)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                // Feature list
                VStack(alignment: .leading, spacing: 12) {
                    taxPaywallFeatureRow(icon: "chart.bar.doc.horizontal", text: "Form 8949 & Schedule D exports")
                    taxPaywallFeatureRow(icon: "arrow.up.doc", text: "TurboTax, Koinly, CoinTracker compatible")
                    taxPaywallFeatureRow(icon: "globe", text: "International formats (UK, Canada, Australia, Germany)")
                    taxPaywallFeatureRow(icon: "chart.pie", text: "Short-term vs long-term gains breakdown")
                    taxPaywallFeatureRow(icon: "exclamationmark.triangle", text: "Wash sale detection & warnings")
                    taxPaywallFeatureRow(icon: "leaf", text: "Tax-loss harvesting opportunities")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DS.Adaptive.cardBackground)
                )
                .padding(.horizontal, 24)
                
                // Upgrade button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    PaywallManager.shared.trackFeatureAttempt(.taxReports)
                    showingUpgradeSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Upgrade to Pro")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PremiumPrimaryCTAStyle(
                        height: 48,
                        horizontalPadding: 16,
                        cornerRadius: 12,
                        font: .headline
                    )
                )
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                // Price hint
                Text("Starting at $9.99/month")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                // Demo mode suggestion - only show if no connected accounts
                if ConnectedAccountsManager.shared.accounts.isEmpty {
                    Button {
                        demoModeManager.enableDemoMode()
                    } label: {
                        Text("Try Demo Mode to preview")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .underline()
                    }
                    .padding(.top, 8)
                }
                
                Spacer().frame(height: 40)
            }
        }
    }
    
    private func taxPaywallFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldBase, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
        }
    }
    
    // MARK: - Year Selector
    
    private var yearSelector: some View {
        HStack(spacing: 12) {
            // Calendar icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.2), Color.orange.opacity(0.1)]
                                : [Color.blue.opacity(0.15), Color.blue.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
            }
            
            Text("Tax Year")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Picker("Year", selection: $selectedYear) {
                ForEach(availableYears) { year in
                    Text(String(year.year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .tint(themedAccent)
        }
        .padding(14)
        .background(premiumCardBackground)
    }
    
    // MARK: - Summary Section
    
    private func summarySection(_ report: TaxReport) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Tax Summary")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            HStack(spacing: 10) {
                summaryCard(
                    title: "Net Capital Gain",
                    value: report.netCapitalGain,
                    subtitle: "\(report.disposals.count) transactions"
                )
                
                summaryCard(
                    title: "Total Income",
                    value: report.totalIncome,
                    subtitle: "\(report.incomeEvents.count) events"
                )
            }
            
            // Total taxable - premium styled
            VStack(spacing: 8) {
                HStack {
                    Text("Total Taxable")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                }
                
                HStack {
                    Text(formatCurrency(report.totalTaxable))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(report.totalTaxable >= 0 ? .green : .red)
                    Spacer()
                }
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.cardBackgroundElevated)
                    
                    // Subtle green/red tint based on value
                    LinearGradient(
                        colors: [
                            (report.totalTaxable >= 0 ? Color.green : Color.red).opacity(colorScheme == .dark ? 0.1 : 0.06),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .padding(14)
        .background(premiumCardBackground)
    }
    
    private func summaryCard(title: String, value: Double, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Text(formatCurrency(value))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(value >= 0 ? DS.Adaptive.textPrimary : .red)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Gains Breakdown
    
    private func gainsBreakdown(_ report: TaxReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capital Gains Breakdown")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            VStack(spacing: 0) {
                gainRow(
                    title: "Short-Term",
                    subtitle: "Held < 1 year • \(report.shortTermCount) txns",
                    value: report.shortTermGain,
                    color: .orange
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                    .padding(.leading, 26)
                
                gainRow(
                    title: "Long-Term",
                    subtitle: "Held ≥ 1 year • \(report.longTermCount) txns",
                    value: report.longTermGain,
                    color: .blue
                )
                
                if report.washSaleAdjustment != 0 {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                        .padding(.leading, 26)
                    
                    gainRow(
                        title: "Wash Sale Adj.",
                        subtitle: "\(report.washSales.count) wash sales",
                        value: report.washSaleAdjustment,
                        color: .purple
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .padding(14)
        .background(premiumCardBackground)
    }
    
    private func gainRow(title: String, subtitle: String, value: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            Text(formatCurrency(value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(value >= 0 ? .green : .red)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Income Section
    
    private func incomeSection(_ report: TaxReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crypto Income")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Group by source
            let incomeBySource = Dictionary(grouping: report.incomeEvents) { $0.source }
            
            VStack(spacing: 0) {
                ForEach(Array(incomeBySource.keys.enumerated()).sorted(by: { $0.element.displayName < $1.element.displayName }), id: \.element) { index, source in
                    if let events = incomeBySource[source] {
                        let total = events.reduce(0) { $0 + $1.totalValue }
                        incomeRow(source: source, total: total)
                        
                        if index < incomeBySource.keys.count - 1 {
                            Rectangle()
                                .fill(DS.Adaptive.divider)
                                .frame(height: 1)
                                .padding(.leading, 46)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private func incomeRow(source: TaxLotSource, total: Double) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.25), .orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: iconForSource(source))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Text(source.displayName)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Text(formatCurrency(total))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
        }
        .padding(.vertical, 10)
    }
    
    private func iconForSource(_ source: TaxLotSource) -> String {
        switch source {
        case .mining: return "hammer.fill"
        case .staking: return "lock.fill"
        case .airdrop: return "gift.fill"
        case .income: return "dollarsign.circle.fill"
        case .interest: return "percent"
        case .rewards: return "star.fill"
        default: return "circle.fill"
        }
    }
    
    // MARK: - Wash Sales Section
    
    private func washSalesSection(_ report: TaxReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.3), .orange.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundColor(.yellow)
                }
                
                Text("Wash Sales Detected")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("The IRS wash sale rule disallows losses when you buy back the same asset within 30 days.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            VStack(spacing: 0) {
                ForEach(Array(report.washSales.prefix(5).enumerated()), id: \.element.id) { index, washSale in
                    washSaleRow(washSale)
                    
                    if index < min(4, report.washSales.count - 1) {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(16)
        .background(
            ZStack {
                premiumCardBackground
                
                // Warning gradient overlay
                LinearGradient(
                    colors: [.yellow.opacity(colorScheme == .dark ? 0.08 : 0.04), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            }
        )
    }
    
    private func washSaleRow(_ washSale: WashSale) -> some View {
        HStack {
            Text(washSale.symbol)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text("Disallowed: \(formatCurrency(washSale.disallowedLoss))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                
                Text("\(washSale.daysBetween) days between")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Unrealized Gains Section
    
    private func unrealizedGainsSection(_ summary: UnrealizedSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.body)
                        .foregroundColor(.purple)
                }
                
                Text("Unrealized Gains")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text(formatCurrency(summary.totalUnrealizedGain))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(summary.totalUnrealizedGain >= 0 ? .green : .red)
            }
            
            Text("Current value of your holdings minus cost basis")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            VStack(spacing: 0) {
                unrealizedRow(
                    title: "Short-Term",
                    subtitle: "Held < 1 year",
                    value: summary.shortTermUnrealizedGain,
                    color: .orange
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                    .padding(.leading, 26)
                
                unrealizedRow(
                    title: "Long-Term",
                    subtitle: "Held ≥ 1 year",
                    value: summary.longTermUnrealizedGain,
                    color: .blue
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Cost Basis")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatCurrency(summary.totalCostBasis))
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current Value")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatCurrency(summary.totalCurrentValue))
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private func unrealizedRow(title: String, subtitle: String, value: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            Text(formatCurrency(value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(value >= 0 ? .green : .red)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Tax-Loss Harvesting Section
    
    private var taxLossHarvestingSection: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingTaxLossHarvesting = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .green.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "leaf.fill")
                        .font(.body)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tax-Loss Harvesting")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Find opportunities to reduce your tax liability")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(premiumCardBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Transactions Section
    
    private func transactionsSection(_ report: TaxReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Only show "See All" if there are transactions
                if !report.disposals.isEmpty {
                    NavigationLink {
                        TaxTransactionsListView(disposals: report.disposals)
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(themedAccent)
                    }
                }
            }
            
            VStack(spacing: 0) {
                if report.disposals.isEmpty {
                    // Empty state for no transactions
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "doc.text")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Transactions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("Tax events will appear here when you record sales, trades, or disposals.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(report.disposals.prefix(5).enumerated()), id: \.element.id) { index, disposal in
                        transactionRow(disposal)
                        
                        if index < min(4, report.disposals.count - 1) {
                            Rectangle()
                                .fill(DS.Adaptive.divider)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private func transactionRow(_ disposal: TaxDisposal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(disposal.symbol)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(formatDate(disposal.disposedDate))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(disposal.gain))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(disposal.isGain ? .green : .red)
                
                Text(disposal.gainType.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(disposal.gainType == .longTerm ? .blue : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (disposal.gainType == .longTerm ? Color.blue : Color.orange).opacity(0.15)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Adaptive.textSecondary.opacity(0.15), DS.Adaptive.textSecondary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            VStack(spacing: 10) {
                Text("No Tax Data")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Add transactions to your portfolio to generate a tax report.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await generateReport() }
            } label: {
                Label("Generate Report", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(premiumCardBackground)
    }
    
    // MARK: - Premium Card Background
    
    private var premiumCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            // Top highlight
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func generateReport() async {
        isGenerating = true
        defer { isGenerating = false }
        
        // Small delay to show loading state
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        currentReport = taxEngine.generateReport(for: selectedYear)
    }
    
    private func calculateUnrealizedGains() async {
        // Get current prices from portfolio
        var currentPrices: [String: Double] = [:]
        for holding in portfolioVM.holdings {
            currentPrices[holding.coinSymbol.uppercased()] = holding.currentPrice
        }
        
        // Calculate unrealized summary
        unrealizedSummary = lotManager.unrealizedSummary(currentPrices: currentPrices)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // MARK: - Demo Mode Banner
    
    private var demoModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue)
            
            Text("Demo Mode – Sample tax data shown")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                demoModeManager.disableDemoMode()
            } label: {
                Text("Disable")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.1), Color.orange.opacity(0.05)]
                    : [.blue.opacity(0.08), .blue.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Demo Tax Data Provider

enum DemoTaxDataProvider {
    
    static var demoReport: TaxReport {
        let currentYear = Calendar.current.component(.year, from: Date())
        let taxYear = TaxYear(currentYear - 1) // Previous year
        
        // Create demo disposals
        let disposals: [TaxDisposal] = [
            // Long-term gain: ETH sale
            TaxDisposal(
                id: UUID(),
                lotId: UUID(),
                symbol: "ETH",
                quantity: 2.5,
                costBasisPerUnit: 1200.0,
                proceedsPerUnit: 3400.0,
                acquiredDate: Calendar.current.date(byAdding: .month, value: -18, to: Date())!,
                disposedDate: Calendar.current.date(byAdding: .month, value: -3, to: Date())!,
                eventType: .sale,
                exchange: "Coinbase"
            ),
            // Short-term gain: BTC trade
            TaxDisposal(
                id: UUID(),
                lotId: UUID(),
                symbol: "BTC",
                quantity: 0.15,
                costBasisPerUnit: 42000.0,
                proceedsPerUnit: 48000.0,
                acquiredDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())!,
                disposedDate: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
                eventType: .trade,
                exchange: "Kraken"
            ),
            // Short-term loss: LINK sale
            TaxDisposal(
                id: UUID(),
                lotId: UUID(),
                symbol: "LINK",
                quantity: 50.0,
                costBasisPerUnit: 18.0,
                proceedsPerUnit: 14.50,
                acquiredDate: Calendar.current.date(byAdding: .month, value: -4, to: Date())!,
                disposedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
                eventType: .sale,
                exchange: "Binance"
            ),
            // Long-term gain: SOL sale
            TaxDisposal(
                id: UUID(),
                lotId: UUID(),
                symbol: "SOL",
                quantity: 25.0,
                costBasisPerUnit: 45.0,
                proceedsPerUnit: 145.0,
                acquiredDate: Calendar.current.date(byAdding: .month, value: -15, to: Date())!,
                disposedDate: Calendar.current.date(byAdding: .month, value: -2, to: Date())!,
                eventType: .sale,
                exchange: "FTX"
            ),
            // Short-term gain: MATIC trade
            TaxDisposal(
                id: UUID(),
                lotId: UUID(),
                symbol: "MATIC",
                quantity: 1000.0,
                costBasisPerUnit: 0.65,
                proceedsPerUnit: 0.92,
                acquiredDate: Calendar.current.date(byAdding: .month, value: -5, to: Date())!,
                disposedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
                eventType: .trade,
                exchange: "Coinbase"
            )
        ]
        
        // Calculate gains
        let shortTermDisposals = disposals.filter { $0.gainType == .shortTerm }
        let longTermDisposals = disposals.filter { $0.gainType == .longTerm }
        let shortTermGain = shortTermDisposals.reduce(0) { $0 + $1.gain }
        let longTermGain = longTermDisposals.reduce(0) { $0 + $1.gain }
        
        // Create demo income events
        let incomeEvents: [IncomeEvent] = [
            IncomeEvent(
                date: Calendar.current.date(byAdding: .month, value: -8, to: Date())!,
                source: .staking,
                symbol: "ETH",
                quantity: 0.12,
                fairMarketValuePerUnit: 2800.0,
                exchange: "Lido"
            ),
            IncomeEvent(
                date: Calendar.current.date(byAdding: .month, value: -6, to: Date())!,
                source: .interest,
                symbol: "USDC",
                quantity: 85.0,
                fairMarketValuePerUnit: 1.0,
                exchange: "Aave"
            ),
            IncomeEvent(
                date: Calendar.current.date(byAdding: .month, value: -4, to: Date())!,
                source: .airdrop,
                symbol: "ARB",
                quantity: 625.0,
                fairMarketValuePerUnit: 1.15,
                exchange: nil,
                notes: "Arbitrum Airdrop"
            )
        ]
        
        let totalIncome = incomeEvents.reduce(0) { $0 + $1.totalValue }
        
        // Create a demo wash sale
        let linkDisposal = disposals.first { $0.symbol == "LINK" }!
        let washSales: [WashSale] = [
            WashSale(
                saleDate: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
                repurchaseDate: Calendar.current.date(byAdding: .day, value: -15, to: Date())!,
                symbol: "LINK",
                saleQuantity: 50.0,
                repurchaseQuantity: 60.0,
                disallowedLoss: 175.0, // Portion of the $175 loss disallowed
                affectedDisposalId: linkDisposal.id,
                affectedLotId: linkDisposal.lotId
            )
        ]
        
        let washSaleAdjustment = washSales.reduce(0) { $0 + $1.disallowedLoss }
        
        return TaxReport(
            taxYear: taxYear,
            accountingMethod: .fifo,
            shortTermGain: shortTermGain,
            longTermGain: longTermGain,
            totalIncome: totalIncome,
            washSaleAdjustment: washSaleAdjustment,
            disposals: disposals,
            incomeEvents: incomeEvents,
            washSales: washSales,
            form8949Rows: [],
            generatedAt: Date()
        )
    }
}

// MARK: - Tax Transactions List View

struct TaxTransactionsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let disposals: [TaxDisposal]
    
    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(disposals) { disposal in
                        transactionCard(disposal)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("All Transactions")
    }
    
    private func transactionCard(_ disposal: TaxDisposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(disposal.symbol)
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text(formatCurrency(disposal.gain))
                    .font(.headline)
                    .foregroundColor(disposal.isGain ? .green : .red)
            }
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(label: "Sold", value: String(format: "%.6f", disposal.quantity))
                    detailRow(label: "Proceeds", value: formatCurrency(disposal.totalProceeds))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    detailRow(label: "Cost", value: formatCurrency(disposal.totalCostBasis))
                    detailRow(label: "Held", value: "\(disposal.holdingPeriodDays) days")
                }
            }
            
            HStack {
                Text(disposal.gainType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(disposal.gainType == .longTerm ? .blue : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (disposal.gainType == .longTerm ? Color.blue : Color.orange).opacity(0.15)
                    )
                    .clipShape(Capsule())
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - Tax Export Sheet

struct TaxExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let report: TaxReport
    @State private var selectedFormat: TaxExportFormat = .form8949CSV
    @State private var isExporting = false
    @State private var exportResult: ExportResult?
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Format selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Export Format")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(TaxExportFormat.allCases.enumerated()), id: \.element.id) { index, format in
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        selectedFormat = format
                                    } label: {
                                        HStack(spacing: 14) {
                                            // Format icon
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        selectedFormat == format
                                                            ? (colorScheme == .dark
                                                                ? Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.2)
                                                                : Color.blue.opacity(0.15))
                                                            : DS.Adaptive.chipBackground
                                                    )
                                                    .frame(width: 36, height: 36)
                                                
                                                Image(systemName: format.iconName)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(
                                                        selectedFormat == format
                                                            ? (colorScheme == .dark
                                                                ? LinearGradient(
                                                                    colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                  )
                                                                : LinearGradient(
                                                                    colors: [.blue, .blue.opacity(0.8)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                  ))
                                                            : LinearGradient(
                                                                colors: [DS.Adaptive.textSecondary, DS.Adaptive.textSecondary],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                              )
                                                    )
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(format.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(selectedFormat == format ? .semibold : .regular)
                                                    .foregroundColor(DS.Adaptive.textPrimary)
                                                Text(format.description)
                                                    .font(.caption)
                                                    .foregroundColor(DS.Adaptive.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if selectedFormat == format {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: colorScheme == .dark
                                                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                                                : [.blue, .blue.opacity(0.8)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                            }
                                        }
                                        .padding(14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < TaxExportFormat.allCases.count - 1 {
                                        Rectangle()
                                            .fill(DS.Adaptive.divider)
                                            .frame(height: 1)
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(DS.Adaptive.cardBackground)
                                    
                                    LinearGradient(
                                        colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                        }
                        
                        // Export button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            exportData()
                        } label: {
                            HStack {
                                if isExporting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .black : .white))
                                        .padding(.trailing, 8)
                                }
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                        : [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isExporting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Export Tax Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let result = exportResult, let url = result.saveToDocuments() {
                    TaxShareSheet(items: [url])
                }
            }
        }
    }
    
    private func exportData() {
        isExporting = true
        
        let exportService = TaxExportService.shared
        exportResult = exportService.export(report: report, format: selectedFormat)
        
        isExporting = false
        showShareSheet = true
    }
}

// MARK: - Tax Settings Sheet

struct TaxSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedMethod: AccountingMethod
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cost Basis Method")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(AccountingMethod.allCases.enumerated()), id: \.element.id) { index, method in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selectedMethod = method
                                    TaxEngine.shared.setAccountingMethod(method)
                                } label: {
                                        HStack(spacing: 14) {
                                            // Method icon
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        selectedMethod == method
                                                            ? (colorScheme == .dark
                                                                ? Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.2)
                                                                : Color.blue.opacity(0.15))
                                                            : DS.Adaptive.chipBackground
                                                    )
                                                    .frame(width: 36, height: 36)
                                                
                                                Image(systemName: method.iconName)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(
                                                        selectedMethod == method
                                                            ? (colorScheme == .dark
                                                                ? LinearGradient(
                                                                    colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                  )
                                                                : LinearGradient(
                                                                    colors: [.blue, .blue.opacity(0.8)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                  ))
                                                            : LinearGradient(
                                                                colors: [DS.Adaptive.textSecondary, DS.Adaptive.textSecondary],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                              )
                                                    )
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(method.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(selectedMethod == method ? .semibold : .medium)
                                                    .foregroundColor(DS.Adaptive.textPrimary)
                                                Text(method.shortDescription)
                                                    .font(.caption)
                                                    .foregroundColor(DS.Adaptive.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if selectedMethod == method {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: colorScheme == .dark
                                                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                                                : [.blue, .blue.opacity(0.8)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                            }
                                        }
                                        .padding(14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < AccountingMethod.allCases.count - 1 {
                                        Rectangle()
                                            .fill(DS.Adaptive.divider)
                                            .frame(height: 1)
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(DS.Adaptive.cardBackground)
                                    
                                    LinearGradient(
                                        colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                            
                            Text("FIFO is the default and most commonly used. HIFO can minimize taxes but requires good record keeping.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textTertiary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Tax Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }
}

// MARK: - Tax Share Sheet

private struct TaxShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    TaxReportView()
}

//
//  OpenOrdersFullView.swift
//  CryptoSage
//
//  Full-screen view for managing all open orders across all connected exchanges.
//  Premium trading platform design with animated stats and modern UI.
//

import SwiftUI

// MARK: - Open Orders Full View

struct OpenOrdersFullView: View {
    @ObservedObject private var ordersManager = OpenOrdersManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Filters
    @State private var selectedExchangeFilter: TradingExchange? = nil
    @State private var selectedSideFilter: TradeSide? = nil
    @State private var showPartiallyFilledOnly: Bool = false
    @State private var searchText: String = ""
    
    // UI State
    @State private var showCancelAllConfirmation: Bool = false
    @State private var sortOrder: SortOrder = .newest
    @State private var pulseAnimation: Bool = false
    @State private var headerAppeared: Bool = false
    @State private var showSortPicker: Bool = false
    @State private var showAIHelper: Bool = false
    
    /// Whether we're in demo mode
    private var isDemoMode: Bool {
        demoModeManager.isDemoMode
    }
    
    /// Gold gradient for header buttons (matches Tax/DeFi pages)
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Check if any filters are active
    private var hasActiveFilters: Bool {
        selectedExchangeFilter != nil || selectedSideFilter != nil || showPartiallyFilledOnly
    }
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case highestValue = "Highest Value"
        case lowestValue = "Lowest Value"
    }
    
    private var filteredOrders: [OpenOrder] {
        var orders = ordersManager.orders
        
        // Filter by exchange
        if let exchange = selectedExchangeFilter {
            orders = orders.filter { $0.exchange == exchange }
        }
        
        // Filter by side
        if let side = selectedSideFilter {
            orders = orders.filter { $0.side == side }
        }
        
        // Filter by partially filled status
        if showPartiallyFilledOnly {
            orders = orders.filter { $0.status == .partiallyFilled }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            let search = searchText.uppercased()
            orders = orders.filter {
                $0.symbol.uppercased().contains(search) ||
                $0.baseAsset.uppercased().contains(search)
            }
        }
        
        // Sort
        switch sortOrder {
        case .newest:
            orders.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            orders.sort { $0.createdAt < $1.createdAt }
        case .highestValue:
            orders.sort { $0.totalValue > $1.totalValue }
        case .lowestValue:
            orders.sort { $0.totalValue < $1.totalValue }
        }
        
        return orders
    }
    
    /// Count of partially filled orders
    private var partiallyFilledCount: Int {
        ordersManager.orders.filter { $0.status == .partiallyFilled }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header (matching Tax/DeFi pattern)
            customHeader
            
            // Demo mode banner
            if isDemoMode {
                demoBanner
            }
            
            // Premium Stats header
            premiumStatsHeader
            
            // Filters
            filtersSection
            
            // Content
            if ordersManager.isLoading && ordersManager.orders.isEmpty {
                loadingView
            } else if filteredOrders.isEmpty {
                emptyState
            } else {
                ordersList
            }
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.05, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .searchable(text: $searchText, prompt: "Search by symbol")
        .refreshable {
            if !isDemoMode {
                await ordersManager.refreshAllOrders()
            }
        }
        .onAppear {
            // Seed demo orders when in demo mode
            if isDemoMode {
                ordersManager.seedDemoOrders()
            } else {
                Task {
                    await ordersManager.refreshAllOrders()
                }
            }
            // Trigger entrance animation
            withAnimation(.easeOut(duration: 0.5)) {
                headerAppeared = true
            }
            // Start pulse animation for active orders
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onReceive(demoModeManager.$isDemoMode) { newDemoMode in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if newDemoMode {
                    ordersManager.seedDemoOrders()
                } else {
                    ordersManager.clearDemoOrders()
                }
            }
        }
        .confirmationDialog(
            "Cancel All Orders",
            isPresented: $showCancelAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel \(filteredOrders.count) Orders", role: .destructive) {
                Task {
                    for order in filteredOrders {
                        await ordersManager.cancelOrder(order)
                    }
                }
            }
            Button("Keep Orders", role: .cancel) {}
        } message: {
            Text("This will cancel all \(filteredOrders.count) filtered open orders. This action cannot be undone.")
        }
        .overlay {
            if showSortPicker {
                sortPickerOverlay
            }
        }
        // AI Helper sheet
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .orders)
        }
    }
    
    // MARK: - Sort Picker Overlay
    
    private var sortPickerOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSortPicker = false
                    }
                }
            
            // Picker card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Sort By")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSortPicker = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Sort options grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        sortOptionButton(order)
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(BrandColors.goldBase.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSortPicker)
    }
    
    private func sortOptionButton(_ order: SortOrder) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeOut(duration: 0.2)) {
                sortOrder = order
                showSortPicker = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sortIconName(for: order))
                    .font(.system(size: 12, weight: .semibold))
                Text(order.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(sortOrder == order ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sortOrder == order ? BrandColors.goldBase : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(sortOrder == order ? BrandColors.goldBase : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func sortIconName(for order: SortOrder) -> String {
        switch order {
        case .newest: return "clock.arrow.circlepath"
        case .oldest: return "clock"
        case .highestValue: return "arrow.up.circle"
        case .lowestValue: return "arrow.down.circle"
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
            Text("Open Orders")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // AI Helper button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAIHelper = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ask AI")
            
            // Refresh button (only show if not in demo mode)
            if !isDemoMode {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await ordersManager.refreshAllOrders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Refresh")
            }
            
            // Clear filters button (show when filters are active)
            if hasActiveFilters {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedExchangeFilter = nil
                        selectedSideFilter = nil
                        showPartiallyFilledOnly = false
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear Filters")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(DS.Adaptive.background.opacity(0.95))
    }
    
    // MARK: - Demo Banner
    
    private var demoBanner: some View {
        let demoColor = AppTradingMode.demo.color
        
        return HStack(spacing: 10) {
            Image(systemName: AppTradingMode.demo.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(demoColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(AppTradingMode.demo.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Sample orders for preview")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Demo badge — uses shared ModeBadge for consistent styling
            ModeBadge(mode: .demo, variant: .compact)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    demoColor.opacity(0.15),
                    demoColor.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            Rectangle()
                .fill(demoColor)
                .frame(height: 2),
            alignment: .bottom
        )
    }
    
    // MARK: - Premium Stats Header
    
    private var premiumStatsHeader: some View {
        VStack(spacing: 0) {
            // Main stats grid
            HStack(spacing: 12) {
                // Total Orders - Hero stat
                PremiumStatCard(
                    icon: "list.bullet.rectangle.portrait",
                    label: "Total Orders",
                    value: "\(ordersManager.totalCount)",
                    gradient: [Color.blue.opacity(0.8), Color.blue],
                    isActive: ordersManager.totalCount > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 20)
                
                // Buy Orders
                PremiumStatCard(
                    icon: "arrow.down.left.circle.fill",
                    label: "Buy Orders",
                    value: "\(ordersManager.buyOrders.count)",
                    gradient: [Color.green.opacity(0.8), Color.green],
                    isActive: ordersManager.buyOrders.count > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.1), value: headerAppeared)
                
                // Sell Orders
                PremiumStatCard(
                    icon: "arrow.up.right.circle.fill",
                    label: "Sell Orders",
                    value: "\(ordersManager.sellOrders.count)",
                    gradient: [Color.red.opacity(0.8), Color.red],
                    isActive: ordersManager.sellOrders.count > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: headerAppeared)
                
                // Total Value
                PremiumStatCard(
                    icon: "dollarsign.circle.fill",
                    label: "Total Value",
                    value: formatCompactUSD(ordersManager.totalValue),
                    gradient: [BrandColors.goldLight, BrandColors.goldBase],
                    isActive: ordersManager.totalValue > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: headerAppeared)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            
            // Subtle gradient divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, BrandColors.goldBase.opacity(0.3), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .background(
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Subtle gold accent glow when orders are active
                if ordersManager.totalCount > 0 {
                    RadialGradient(
                        colors: [BrandColors.goldBase.opacity(0.08), Color.clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 200
                    )
                }
            }
        )
    }
    
    // Legacy statItem kept for compatibility - now uses PremiumStatCard
    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Filters Section
    
    private var filtersSection: some View {
        VStack(spacing: 12) {
            // Exchange and Side filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // All filter
                    PremiumFilterPill(
                        title: "All",
                        isSelected: selectedExchangeFilter == nil && selectedSideFilter == nil && !showPartiallyFilledOnly,
                        count: ordersManager.orders.count,
                        color: BrandColors.goldBase
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedExchangeFilter = nil
                            selectedSideFilter = nil
                            showPartiallyFilledOnly = false
                        }
                    }
                    
                    // Elegant divider
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.2), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1, height: 24)
                    
                    // Side filters
                    PremiumFilterPill(
                        title: "Buy",
                        isSelected: selectedSideFilter == .buy,
                        count: ordersManager.buyOrders.count,
                        color: .green,
                        icon: "arrow.down.left"
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedSideFilter = selectedSideFilter == .buy ? nil : .buy
                        }
                    }
                    
                    PremiumFilterPill(
                        title: "Sell",
                        isSelected: selectedSideFilter == .sell,
                        count: ordersManager.sellOrders.count,
                        color: .red,
                        icon: "arrow.up.right"
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedSideFilter = selectedSideFilter == .sell ? nil : .sell
                        }
                    }
                    
                    // Partial filter (only show if there are partially filled orders)
                    if partiallyFilledCount > 0 {
                        PremiumFilterPill(
                            title: "Partial",
                            isSelected: showPartiallyFilledOnly,
                            count: partiallyFilledCount,
                            color: .orange,
                            icon: "chart.bar.fill"
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showPartiallyFilledOnly.toggle()
                            }
                        }
                    }
                    
                    // Exchange filters (if any)
                    if !ordersManager.exchangesWithOrders.isEmpty {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.2), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1, height: 24)
                        
                        ForEach(ordersManager.exchangesWithOrders, id: \.self) { exchange in
                            PremiumFilterPill(
                                title: exchange.displayName,
                                isSelected: selectedExchangeFilter == exchange,
                                count: ordersManager.orders(for: exchange).count,
                                color: BrandColors.goldBase
                            ) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedExchangeFilter = selectedExchangeFilter == exchange ? nil : exchange
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Sort and results row with premium styling
            HStack {
                // Sort picker button (premium styled)
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showSortPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(sortOrder.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Results count with badge styling
                HStack(spacing: 4) {
                    Circle()
                        .fill(filteredOrders.isEmpty ? Color.gray : BrandColors.goldBase)
                        .frame(width: 6, height: 6)
                    Text("\(filteredOrders.count) order\(filteredOrders.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.02))
    }
    
    // Legacy filterPill kept for compatibility
    private func filterPill(_ title: String, isSelected: Bool, count: Int, color: Color = BrandColors.goldBase, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? color : Color.gray.opacity(0.3))
                        )
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? color : Color.white.opacity(0.08))
            )
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Animated loading indicator
            ZStack {
                // Outer ring
                Circle()
                    .stroke(BrandColors.goldBase.opacity(0.2), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                // Spinning ring
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(pulseAnimation ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: pulseAnimation)
                
                // Center icon
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 20))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(spacing: 6) {
                Text("Loading Orders")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text("Fetching from connected exchanges...")
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)
                
                // Premium Empty State Card
                PremiumGlassCard(showGoldAccent: true, cornerRadius: 20) {
                    VStack(spacing: 20) {
                        // Animated icon with glow ring
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [BrandColors.goldBase.opacity(headerAppeared ? 0.25 : 0.1), Color.clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 70
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: headerAppeared)
                            
                            // Gold ring stroke
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight.opacity(0.7), BrandColors.goldBase.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 100, height: 100)
                            
                            // Inner background
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 96, height: 96)
                            
                            // Icon
                            Image(systemName: emptyStateIcon)
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 8)
                        
                        // Title and description
                        VStack(spacing: 8) {
                            Text(emptyStateTitle)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text(emptyStateMessage)
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        
                        // CTA Buttons (only show when no filters active)
                        if searchText.isEmpty && selectedExchangeFilter == nil && selectedSideFilter == nil {
                            VStack(spacing: 12) {
                                // Primary CTA - Place Order
                                Button {
                                    appState.selectedTab = .trade
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Place a Limit Order")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule()
                                            .fill(
                                                AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [BrandColors.goldLight.opacity(0.6), BrandColors.goldBase.opacity(0.3)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                
                                // Secondary CTA - Ask AI for entry points
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    showAIHelper = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Ask AI for entry points")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, 20)
                
                // AI Suggestions Section (when no orders and no filters)
                if searchText.isEmpty && selectedExchangeFilter == nil && selectedSideFilter == nil {
                    aiSuggestionsSection
                }
                
                Spacer(minLength: 100)
            }
        }
    }
    
    // MARK: - AI Suggestions Section
    
    private var aiSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("AI Trading Ideas")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Button {
                    showAIHelper = true
                } label: {
                    Text("See All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrandColors.goldBase)
                }
            }
            .padding(.horizontal, 4)
            
            // Quick suggestion cards
            VStack(spacing: 10) {
                AISuggestionCard(
                    icon: "arrow.down.circle.fill",
                    iconColor: .green,
                    title: "Find good entries",
                    subtitle: "Ask AI for optimal buy levels"
                ) {
                    showAIHelper = true
                }
                
                AISuggestionCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .blue,
                    title: "Support & Resistance",
                    subtitle: "Identify key price levels"
                ) {
                    showAIHelper = true
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyStateIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        } else if selectedExchangeFilter != nil || selectedSideFilter != nil {
            return "line.3.horizontal.decrease.circle"
        } else {
            return "checkmark.circle"
        }
    }
    
    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No Results"
        } else if selectedExchangeFilter != nil || selectedSideFilter != nil {
            return "No Matching Orders"
        } else {
            return "All Clear!"
        }
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No orders match '\(searchText)'\nTry a different search term"
        } else if selectedExchangeFilter != nil || selectedSideFilter != nil {
            return "No orders match the selected filters.\nTry adjusting your filters."
        } else {
            return "You don't have any pending limit orders.\nPlace a limit order to see it here."
        }
    }
    
    // MARK: - Orders List
    
    private var ordersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Group by symbol
                let groupedOrders = Dictionary(grouping: filteredOrders, by: { $0.baseAsset })
                let sortedSymbols = groupedOrders.keys.sorted()
                
                ForEach(sortedSymbols, id: \.self) { symbol in
                    if let orders = groupedOrders[symbol] {
                        symbolSection(symbol: symbol, orders: orders)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 100)
        }
    }
    
    private func symbolSection(symbol: String, orders: [OpenOrder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Symbol header with coin icon
            HStack(spacing: 8) {
                // Coin icon
                CoinImageView(
                    symbol: symbol,
                    url: coinImageURL(for: symbol),
                    size: 22
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                )
                
                Text(symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("\(orders.count) order\(orders.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                // Total value for this symbol
                let totalValue = orders.reduce(0) { $0 + $1.totalValue }
                Text(formatCompactUSD(totalValue))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            .padding(.horizontal, 4)
            
            // Orders
            ForEach(orders) { order in
                OpenOrderRowView(order: order, showSymbol: false, isDemoMode: isDemoMode) {
                    Task {
                        await ordersManager.cancelOrder(order)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatCompactUSD(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "$\(String(format: "%.1fM", value / 1_000_000))"
        } else if value >= 1_000 {
            return "$\(String(format: "%.1fK", value / 1_000))"
        } else {
            return "$\(String(format: "%.2f", value))"
        }
    }
}

// MARK: - Premium Stat Card

/// A premium-styled stat card for the header with gradient background and animations
private struct PremiumStatCard: View {
    let icon: String
    let label: String
    let value: String
    let gradient: [Color]
    let isActive: Bool
    let pulseAnimation: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon with subtle glow when active
            ZStack {
                if isActive {
                    Circle()
                        .fill(gradient[0].opacity(pulseAnimation ? 0.3 : 0.15))
                        .frame(width: 32, height: 32)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                }
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            // Value with emphasized styling
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)

            // Label
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(isActive ? 0.08 : 0.04), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive ? gradient[0].opacity(0.3) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Premium Filter Pill

/// A premium-styled filter pill with icon support and smooth animations
private struct PremiumFilterPill: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let color: Color
    var icon: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // Optional icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                
                // Count badge
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? color : .white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.black.opacity(0.2) : Color.white.opacity(0.1))
                        )
                }
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Open Orders Widget

/// A compact widget that can be embedded in other views (like Portfolio)
struct OpenOrdersWidget: View {
    @ObservedObject private var ordersManager = OpenOrdersManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private var hasOrders: Bool { ordersManager.hasOpenOrders }
    
    var body: some View {
        NavigationLink(destination: OpenOrdersFullView()) {
            HStack(spacing: 12) {
                // Icon with status indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            hasOrders
                                ? LinearGradient(colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: isDark ? [Color.white.opacity(0.06), Color.white.opacity(0.03)] : [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            hasOrders
                                ? LinearGradient(colors: [Color.orange, Color.orange.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                    
                    // Active indicator dot
                    if hasOrders {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(isDark ? Color.black : Color.white, lineWidth: 2)
                            )
                            .offset(x: 14, y: -14)
                    }
                }
                
                // Info section
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Open Orders")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if ordersManager.totalCount > 0 {
                            Text("\(ordersManager.totalCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    
                    if hasOrders {
                        Text("\(ordersManager.buyOrders.count) buy, \(ordersManager.sellOrders.count) sell")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    } else {
                        Text("No pending orders")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                Spacer()
                
                // Right side: Value & chevron in horizontal layout
                HStack(spacing: 8) {
                    if hasOrders {
                        Text(formatCompactUSD(ordersManager.totalValue))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(DS.Adaptive.goldText)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.05) : DS.Adaptive.cardBackground)
                    
                    // Top highlight for glass effect
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.5),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        hasOrders ? Color.orange.opacity(0.3) : (isDark ? Color.white.opacity(0.08) : DS.Adaptive.stroke),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .onAppear {
            Task {
                await ordersManager.refreshAllOrders()
            }
        }
    }
    
    private func formatCompactUSD(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "$\(String(format: "%.1fM", value / 1_000_000))"
        } else if value >= 1_000 {
            return "$\(String(format: "%.1fK", value / 1_000))"
        } else {
            return "$\(String(format: "%.2f", value))"
        }
    }
}

// MARK: - AI Suggestion Card

/// A card for AI trading suggestions
private struct AISuggestionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [DS.Adaptive.stroke.opacity(0.5), DS.Adaptive.stroke.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
                }
        )
    }
}

// MARK: - Preview

#if DEBUG
struct OpenOrdersFullView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            OpenOrdersFullView()
        }
        .environmentObject(AppState())
    }
}
#endif

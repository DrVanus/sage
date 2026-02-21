import SwiftUI

struct ActionCenterSection: View {
    let result: RiskScanResult?
    let isScanning: Bool
    let lastScan: Date?
    let overlayActive: Bool
    let onScan: () -> Void
    let onViewReport: () -> Void
    
    @State private var showPaywall = false
    
    /// Determines if the user can access the Risk Report feature
    /// - Demo mode users: Always allowed (shows value of the feature)
    /// - Users without connected accounts: Allowed (empty state shown)
    /// - Connected accounts with Pro+: Allowed
    /// - Connected accounts without subscription: Locked
    private var canAccessRiskReport: Bool {
        // Demo mode users can always access (to see the feature value)
        if DemoModeManager.shared.isDemoMode { return true }
        
        // Users without any connected accounts get empty state, not locked
        // (they need to connect first, not subscribe)
        if ConnectedAccountsManager.shared.accounts.isEmpty &&
           !PaperTradingManager.isEnabled { return true }
        
        // Connected accounts require Pro+ subscription
        return SubscriptionManager.shared.hasAccess(to: .riskReport)
    }
    
    /// True if the feature should show a locked overlay
    private var isLocked: Bool {
        !canAccessRiskReport
    }

    var body: some View {
        CardContainer {
            ZStack {
                RiskScanCard(
                    result: result,
                    isScanning: isScanning,
                    lastScan: lastScan,
                    onScan: isLocked ? { showPaywall = true } : onScan,
                    onViewReport: isLocked ? { showPaywall = true } : onViewReport,
                    overlayActive: overlayActive
                )
                .padding(12)
                
                // Locked overlay
                if isLocked {
                    lockedOverlay
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showPaywall) {
            UnifiedPaywallSheet(feature: .riskReport)
        }
    }
    
    // MARK: - Locked Overlay
    
    private var lockedOverlay: some View {
        VStack(spacing: 12) {
            // Lock icon with gold styling
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 4) {
                Text("AI Risk Report")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text("Upgrade to Pro to unlock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Unlock button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showPaywall = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Unlock")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
        )
        .transition(.opacity)
    }
}

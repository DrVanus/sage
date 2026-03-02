//
//  AIInsightView.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import SwiftUI

struct AIInsightView: View {
    @StateObject private var vm = AIInsightViewModel()
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradePrompt = false
    
    /// Check if user has access to personalized portfolio analysis
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .personalizedPortfolioAnalysis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Use standardized GoldHeaderGlyph for consistency with other sections
                GoldHeaderGlyph(systemName: "brain.head.profile")
                Text("AI Insight")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                
                if hasAccess {
                    Button {
                        Task { await vm.refresh(using: portfolioVM.portfolio) }
                    } label: {
                        if vm.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(width: 24, height: 24)
                                .padding(4)
                                .background(
                                    Circle().fill(Color(uiColor: .systemBackground))
                                )
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .padding(4)
                                .background(
                                    Circle().fill(Color(uiColor: .systemBackground))
                                )
                        }
                    }
                    .disabled(vm.isLoading)
                    .help("Generate a new AI insight")
                } else {
                    // Pro badge for locked state
                    LockedFeatureBadge(feature: .personalizedPortfolioAnalysis, style: .compact)
                }
            }

            Divider()

            if hasAccess {
                // Full access - show insights
                if let text = vm.insight?.text {
                    Text(text)
                        .font(.body)
                } else {
                    Text("Press the refresh button to generate your first AI insight.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let timestamp = vm.insight?.timestamp {
                    Text("Updated \(timestamp, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else {
                // Locked state - show upgrade prompt
                VStack(spacing: 12) {
                    Text("Get personalized AI insights about your portfolio including risk analysis, diversification suggestions, and market opportunities.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    Button {
                        showUpgradePrompt = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 12))
                            Text("Unlock with Pro")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 32,
                            horizontalPadding: 14,
                            cornerRadius: 16,
                            font: .subheadline.weight(.semibold)
                        )
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .systemBackground))
        )
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if hasAccess && vm.insight == nil {
                    Task { await vm.refresh(using: portfolioVM.portfolio) }
                }
            }
        }
        .unifiedPaywallSheet(feature: .personalizedPortfolioAnalysis, isPresented: $showUpgradePrompt)
    }
}

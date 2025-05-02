import SwiftUI

/// Describes a subscription tier and its benefits.
struct SubscriptionTier: Identifiable {
    let id = UUID()
    let name: String
    let monthlyPrice: String
    let yearlyPrice: String
    let features: [String]
    let isRecommended: Bool
}

/// A polished subscription pricing view for CryptoSage AI.
struct SubscriptionPricingView: View {
    // Gold accent for pricing cards
    var accentColor: Color = Color(red: 0.85, green: 0.65, blue: 0.13)  // gold
    var backgroundColor: Color = .theme.background
    var secondaryColor: Color = Color(red: 0.95, green: 0.85, blue: 0.60)  // light gold
    /// Soft gold wash background for pricing cards
    var cardGradient: LinearGradient {
        LinearGradient(
            colors: [.theme.gradientStart.opacity(0.2), .theme.gradientEnd.opacity(0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    @State private var annualBilling = false

    init() {
        UINavigationBar.appearance().topItem?.title = "Choose Your Plan"
    }

    private let tiers: [SubscriptionTier] = [
        SubscriptionTier(
            name: "Free",
            monthlyPrice: "$0",
            yearlyPrice: "$0",
            features: [
                "Unlimited wallet & exchange connections",
                "Live market data",
                "Basic AI insights (daily)",
                "Basic AI Chat (3 prompts/day)",
                "Standard price & portfolio alerts",
                "Ad-supported interface"
            ],
            isRecommended: false
        ),
        SubscriptionTier(
            name: "Pro",
            monthlyPrice: "$9",
            yearlyPrice: "$90",
            features: [
                "Unlimited wallet & exchange connections",
                "Live market data",
                "AI Insights & personalized portfolio analysis",
                "AI Chat Assistant (20 prompts/day)",
                "Execute trades through your connected wallets & exchanges",
                "AI-powered notifications & alerts",
                "Ad-free experience"
            ],
            isRecommended: false
        ),
        SubscriptionTier(
            name: "Elite",
            monthlyPrice: "$19",
            yearlyPrice: "$180",
            features: [
                "Includes all Pro features",
                "Advanced AI Insights & strategy builder",
                "Unlimited AI Chat Assistant",
                "Automated trading bots",
                "Custom algorithmic strategies",
                "Priority customer support"
            ],
            isRecommended: true
        )
    ]

var body: some View {
    ScrollView(showsIndicators: true) {
        VStack(spacing: 16) {
            // Billing segmented control
            Picker("Billing", selection: $annualBilling) {
                Text("Monthly").tag(false)
                Text("Annual").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .tint(accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Subscription cards
            VStack(spacing: 24) {
                ForEach(tiers) { tier in
                    PricingCard(
                        tier: tier,
                        annual: annualBilling,
                        accentColor: accentColor,
                        secondaryColor: secondaryColor,
                        cardBackground: tier.name == "Free"
                            ? AnyShapeStyle(Color.theme.cardBackground)
                            : AnyShapeStyle(cardGradient)
                    )
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
    .accentColor(accentColor)
}
}

private struct PricingCard: View {
    let tier: SubscriptionTier
    let annual: Bool
    let accentColor: Color
    let secondaryColor: Color
    let cardBackground: AnyShapeStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 20) {
                if tier.name == "Pro" {
                    Text("MOST POPULAR")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(tier.name)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text(currentPrice)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }

                Divider()
                    .background(secondaryColor)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tier.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: featureIcon(feature))
                                .foregroundColor(accentColor)
                                .font(.body)
                            Text(feature)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }

                Button(action: {
                    // TODO: connect to purchase flow for `tier.name`
                }) {
                    Text("Select \(tier.name)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tier.name == "Free" ? secondaryColor : accentColor)
                .clipShape(Capsule())
            }
            .padding(16)
            .background(cardBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(tier.name == "Free" ? Color.clear : accentColor, lineWidth: 2)
            )
            .shadow(color: accentColor.opacity(0.2), radius: 12, x: 0, y: 6)

            if tier.isRecommended {
                Text("Recommended")
                    .font(.caption2.bold())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(accentColor)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-15))
                    .offset(x: -10, y: -10)
            }
        }
    }

    private var currentPrice: String {
        let price = annual ? tier.yearlyPrice : tier.monthlyPrice
        return "\(price)/mo"
    }
}

private func featureIcon(_ feature: String) -> String {
    let lower = feature.lowercased()
    switch true {
    case lower.contains("automated trading bots"):
        return "bolt.fill"
    case lower.contains("bot"):
        return "bolt.fill"
    case lower.contains("connect"):
        return "link.circle.fill"
    case lower.contains("wallet"):
        return "wallet.pass.fill"
    case lower.contains("exchange"):
        return "bitcoinsign.circle.fill"
    case lower.contains("market data"):
        return "chart.line.uptrend.xyaxis"
    case lower.contains("insight"):
        return "brain.head.profile"
    case lower.contains("chat"):
        return "message.circle.fill"
    case lower.contains("algorithmic"):
        return "gearshape.2.fill"
    case lower.contains("alert"):
        return "bell.fill"
    case lower.contains("ad-supported"):
        return "megaphone.fill"
    case lower.contains("support"):
        return "star.fill"
    default:
        return "checkmark.circle.fill"
    }
}

struct SubscriptionPricingView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPricingView()
            .environmentObject(PortfolioViewModel.sample)
            .preferredColorScheme(.dark)
    }
}

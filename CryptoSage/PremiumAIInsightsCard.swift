import SwiftUI

public struct PremiumAIInsightsCard: View {
    let portfolioVM: PortfolioViewModel
    let onOpenChat: (String) -> Void
    let prompts: [String]

    @State private var promptIndex = 0
    @State private var isHidden = false

    private var currentPrompt: String {
        guard prompts.indices.contains(promptIndex) else { return "" }
        return prompts[promptIndex]
    }

    private var personalizedHeadline: String {
        // Example personalized headline logic based on portfolio history and allocationData
        // Uses local helpers
        let gainLoss = portfolioVM.history.last?.value ?? 0
        return "Your portfolio is currently \(gainLoss >= 0 ? "up" : "down") \(pct(gainLoss))"
    }

    private var personalizedTip: String {
        // Example personalized tip logic based on latest allocation data and history
        let latestAllocation = portfolioVM.allocationData.last?.percentage ?? 0
        return "Consider rebalancing your portfolio by \(pct(latestAllocation)) for optimal growth."
    }

    public var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Premium AI Insights")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)

                Text(personalizedHeadline)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)

                Text(personalizedTip)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .background(Color.white.opacity(0.5))

            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        promptIndex = (promptIndex - 1 + prompts.count) % prompts.count
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }

                Button {
                    isHidden.toggle()
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }

                Button {
                    withAnimation {
                        promptIndex = (promptIndex + 1) % prompts.count
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }

                Spacer()

                Text(isHidden ? "*****" : currentPrompt)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture {
                        onOpenChat(currentPrompt)
                    }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]),
                            center: .center,
                            startRadius: 5,
                            endRadius: 60
                        )
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 400
                    )
                )
                .background(ScanLineBackground())
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Local Helper Functions

private func currency(_ v: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = Locale.current.currencyCode ?? "USD"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let sign = v >= 0 ? "+" : "-"
    let absValue = abs(v)
    if let formatted = formatter.string(from: NSNumber(value: absValue)) {
        return "\(sign)\(formatted)"
    }
    return "\(sign)$\(String(format: "%.2f", absValue))"
}

private func pct(_ p: Double) -> String {
    let value = abs(p) * 100
    return String(format: "%.2f%%", value)
}

// MARK: - Supporting Views and Modifiers

private struct ScanLineBackground: View {
    var body: some View {
        GeometryReader { geo in
            let lineHeight: CGFloat = 1
            let spacing: CGFloat = 12
            let count = Int(geo.size.height / (lineHeight + spacing))
            VStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.1), Color.clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: lineHeight)
                        .blur(radius: 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .allowsHitTesting(false)
        .compositingGroup()
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.white.opacity(0.3), .white.opacity(0.7), .white.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .blendMode(.screen)
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 300
                }
            }
    }
}

private extension View {
    func shimmering(_ active: Bool = true) -> some View {
        modifier(active ? Shimmer() : IdentityModifier())
    }
}

private struct IdentityModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

#if DEBUG
/*
struct PremiumAIInsightsCard_Previews: PreviewProvider {
    static var previews: some View {
        // Minimal fake PortfolioViewModel to make the preview compile
        struct FakePortfolioVM: PortfolioViewModel {
            var history: [HistoryEntry] = [HistoryEntry(value: 0.05)]
            var allocationData: [AllocationEntry] = [AllocationEntry(percentage: 0.15)]
            init() {}
        }
        PremiumAIInsightsCard(
            portfolioVM: FakePortfolioVM(),
            onOpenChat: { _ in },
            prompts: ["How can I optimize my portfolio?", "What are top stocks today?", "Any risk alerts?"]
        )
        .frame(width: 350, height: 200)
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
*/
#endif

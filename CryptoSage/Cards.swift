import SwiftUI

struct CardCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var font: Font = .subheadline.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Color.black)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.92, blue: 0.30).opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CardContainer<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
            content()
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InviteCard: View {
    private let shareURL = URL(string: "https://example.com/app")!
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill").foregroundStyle(Color(red: 1.0, green: 0.92, blue: 0.30))
                Text("Invite & Earn BTC").font(.headline).foregroundStyle(.white)
            }
            Text("Refer friends, get rewards.").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ShareLink(item: shareURL, message: Text("Join me on Crypto AI — track, analyze and chat with AI about markets.\n")) { Text("Invite").lineLimit(1).minimumScaleFactor(0.9) }
                    .buttonStyle(CardCTAButtonStyle(height: 34))
                Button { UIPasteboard.general.string = shareURL.absoluteString; UINotificationFeedbackGenerator().notificationOccurred(.success) } label: { Text("Copy Link") }
                    .buttonStyle(CardCTAButtonStyle(height: 34))
                    .accessibilityLabel("Copy Link")
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }
}

struct RiskScanCard: View {
    let result: RiskScanResult?
    let isScanning: Bool
    let lastScan: Date?
    let onScan: () -> Void
    let onViewReport: () -> Void
    let overlayActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Color(red: 1.0, green: 0.92, blue: 0.30))
                Text("Risk Scan")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let last = lastScan {
                    Text(stubRelativeString(last))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular)
                    Text("Scanning…").foregroundStyle(.secondary).font(.subheadline)
                }
            } else if let res = result {
                Text("Level: \(res.level.rawValue) • Score: \(res.score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Button("View Report", action: onViewReport)
                        .buttonStyle(CardCTAButtonStyle(height: 32))
                    Button("Rescan", action: onScan)
                        .buttonStyle(CardCTAButtonStyle(height: 32))
                }
            } else {
                Text("Analyze your portfolio risk to get insights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Run Scan", action: onScan)
                    .buttonStyle(CardCTAButtonStyle(height: 34))
            }
        }
    }
}

fileprivate func stubRelativeString(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "Just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}

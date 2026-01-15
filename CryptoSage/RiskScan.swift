import SwiftUI

public enum RiskLevel: String, Codable {
    case low = "Low", medium = "Medium", high = "High"
}

public struct RiskHighlight: Identifiable, Codable {
    public let id = UUID()
    public let title: String
    public let detail: String
    public let severity: RiskLevel
    
    public init(title: String, detail: String, severity: RiskLevel) {
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct RiskMetrics: Codable {
    public var topWeight: Double
    public var hhi: Double
    public var stablecoinWeight: Double
    public var volatility: Double
    public var maxDrawdown: Double
    public var illiquidCount: Int
    
    public static let zero = RiskMetrics(topWeight: 0, hhi: 0, stablecoinWeight: 0, volatility: 0, maxDrawdown: 0, illiquidCount: 0)
}

public struct RiskScanResult: Codable {
    public let score: Int
    public let level: RiskLevel
    public let highlights: [RiskHighlight]
    public let metrics: RiskMetrics
}

public enum RiskScanner {
    @MainActor
    static func scan(portfolioVM: PortfolioViewModel, marketVM: MarketViewModel) -> RiskScanResult {
        RiskScanResult(score: 12, level: .low, highlights: [], metrics: .zero)
    }
}

public struct GaugeRing: View {
    public var progress: CGFloat
    public var color: Color
    public var lineWidth: CGFloat = 3
    
    public init(progress: CGFloat, color: Color, lineWidth: CGFloat = 3) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [color.opacity(0.6), color]), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

public struct RiskRingBadge: View {
    public let level: RiskLevel
    public let score: Int
    public let progress: CGFloat
    
    public init(level: RiskLevel, score: Int, progress: CGFloat) {
        self.level = level
        self.score = score
        self.progress = progress
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                GaugeRing(progress: progress, color: color, lineWidth: 3)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text("\(level.rawValue) \(score)")
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }
    
    private var color: Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

public struct SparkleBurstView: View {
    public var color: Color
    @State private var animate = false
    
    public init(color: Color) {
        self.color = color
    }
    
    public var body: some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color.opacity(0.95))
                .scaleEffect(animate ? 1.6 : 0.7)
                .opacity(animate ? 0 : 1)
                .blur(radius: animate ? 1 : 0)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .offset(x: -10, y: 6)
                .scaleEffect(animate ? 1.4 : 0.6)
                .opacity(animate ? 0 : 1)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .offset(x: 10, y: 6)
                .scaleEffect(animate ? 1.4 : 0.6)
                .opacity(animate ? 0 : 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animate = true
            }
        }
    }
}

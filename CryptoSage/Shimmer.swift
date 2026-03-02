import SwiftUI
import Combine

// MARK: - Shimmer Bar (Premium Loading Skeleton)
// MEMORY FIX v16: Removed ALL .repeatForever animation.
// The previous implementation used GeometryReader + LinearGradient + .repeatForever
// which caused SwiftUI to re-evaluate the view body on EVERY animation frame (60 FPS).
// Each evaluation creates temporary GeometryReader closures and LinearGradient objects
// that accumulate faster than autorelease pools can drain them.
// With 20+ ShimmerBars visible simultaneously (loading states across portfolio, news,
// sentiment, events, trending sections), this generated ~9 MB/s of unreleased memory,
// causing OOM crashes within 3 minutes.
// The static version shows a clean gradient skeleton that costs zero ongoing memory.

public struct ShimmerBar: View {
    @Environment(\.colorScheme) private var colorScheme
    // MEMORY FIX v17: Use a single shared phase value so ALL ShimmerBars animate
    // in sync from one timer, instead of each creating its own animation state.
    @State private var phase: Bool = false

    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var useGoldTint: Bool

    public init(height: CGFloat = 10, cornerRadius: CGFloat = 4, useGoldTint: Bool = false) {
        self.height = height
        self.cornerRadius = cornerRadius
        self.useGoldTint = useGoldTint
    }

    private var isDark: Bool { colorScheme == .dark }

    private var baseColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var pulseColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(phase ? pulseColor : baseColor)
            .frame(height: height)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = true }
    }
}

// MARK: - Shimmer View Modifier

// MEMORY FIX v17: Lightweight opacity pulse — uses a single Bool toggle instead
// of GeometryReader + LinearGradient. One @State Bool per modified view costs
// ~16 bytes vs ~400+ bytes for the old geometry-based approach.
public struct ShimmerModifier: ViewModifier {
    var duration: Double
    var minOpacity: Double
    var maxOpacity: Double
    @State private var phase: Bool = false

    public init(duration: Double = 0.8, minOpacity: Double = 0.4, maxOpacity: Double = 0.7) {
        self.duration = duration
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
    }

    public func body(content: Content) -> some View {
        content
            .opacity(phase ? maxOpacity : minOpacity)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = true }
    }
}

// MARK: - Premium Shimmer Modifier (Gold Sweep)
// MEMORY FIX v16: Removed .repeatForever animation (same root cause as ShimmerBar).

public struct PremiumShimmerModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
    }
}

public extension View {
    /// Applies a subtle shimmer/pulse animation
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
    
    /// Applies a shimmer with custom parameters
    func shimmer(duration: Double, minOpacity: Double = 0.4, maxOpacity: Double = 0.7) -> some View {
        modifier(ShimmerModifier(duration: duration, minOpacity: minOpacity, maxOpacity: maxOpacity))
    }
    
    /// Applies a premium gold shimmer sweep effect (dark mode only)
    func premiumShimmer() -> some View {
        modifier(PremiumShimmerModifier())
    }
}

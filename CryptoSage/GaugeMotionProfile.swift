import SwiftUI

/// Shared motion profile for gauge-like components.
/// Keeps all indicator animations consistent across the app.
enum GaugeMotionProfile {
    // Best-default "smooth premium" preset across the app.
    static let settle = Animation.easeInOut(duration: 0.30)
    static let fill = Animation.easeOut(duration: 0.62)
    static let spring = Animation.spring(response: 0.56, dampingFraction: 0.86)
    static let springEmphasis = Animation.spring(response: 0.66, dampingFraction: 0.84)

    static func clampUnit(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    static func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}

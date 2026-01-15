import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

final class ChartHaptics {
    static let shared = ChartHaptics()

    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    private var lastTickAt: CFTimeInterval = 0
    private var lastMajorAt: CFTimeInterval = 0

    // Throttle intervals (seconds)
    var minTickInterval: CFTimeInterval = 0.05   // ~20 Hz max
    var minMajorInterval: CFTimeInterval = 0.25  // avoid spamming major bumps

    func begin() {
        selection.prepare()
        light.prepare()
        light.impactOccurred(intensity: 0.6)
    }

    func end() {
        light.prepare()
        light.impactOccurred(intensity: 0.5)
    }

    func tickIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - lastTickAt >= minTickInterval else { return }
        selection.selectionChanged()
        selection.prepare()
        lastTickAt = now
    }

    func majorIfNeeded(intensity: CGFloat = 0.9) {
        let now = CACurrentMediaTime()
        guard now - lastMajorAt >= minMajorInterval else { return }
        rigid.prepare()
        rigid.impactOccurred(intensity: intensity)
        lastMajorAt = now
    }
}

#else

// Non-iOS platforms: provide no-op stubs so code compiles.
final class ChartHaptics {
    static let shared = ChartHaptics()
    var minTickInterval: CFTimeInterval = 0.05
    var minMajorInterval: CFTimeInterval = 0.25
    func begin() {}
    func end() {}
    func tickIfNeeded() {}
    func majorIfNeeded(intensity: CGFloat = 1.0) {}
}

#endif

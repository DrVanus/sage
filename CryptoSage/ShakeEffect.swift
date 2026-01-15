import SwiftUI

/// A reusable shake effect that triggers when the `animatableData` changes.
/// Usage:
///   @State private var shakeAttempts = 0
///   SomeView()
///     .modifier(ShakeEffect(animatableData: CGFloat(shakeAttempts)))
///   // then increment `shakeAttempts += 1` to trigger a shake
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

extension View {
    /// Convenience wrapper to apply a shake with an integer trigger.
    func shake(_ trigger: Int, amount: CGFloat = 8, shakesPerUnit: CGFloat = 3) -> some View {
        modifier(ShakeEffect(amount: amount, shakesPerUnit: shakesPerUnit, animatableData: CGFloat(trigger)))
    }
}

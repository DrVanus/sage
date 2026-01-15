import SwiftUI

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var opacity: Double = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? opacity : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

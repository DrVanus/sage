import SwiftUI

// Gold gradient and solid color helpers
extension ShapeStyle where Self == LinearGradient {
    static var csGold: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 1.0, green: 0.92, blue: 0.3),
                Color.orange
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    static var csGoldSolid: Color { Color(red: 1.0, green: 0.92, blue: 0.30) }
}

extension ShapeStyle where Self == Color {
    static var csGoldSolid: Color { Color.csGoldSolid }
}

// Button styles
struct CSGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.black)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.84, blue: 0.0),
                        Color.orange
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

struct CSPrimaryCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var cornerRadius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.black)
            .frame(height: height)
            .padding(.horizontal, 14)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.3),
                        Color.orange
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct CSSecondaryCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 12
    var font: Font = .callout.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Color.csGoldSolid)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.csGoldSolid.opacity(configuration.isPressed ? 0.9 : 0.6), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct CSPlainCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var font: Font = .subheadline.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.28 : 0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct CSNeonCTAStyle: ButtonStyle {
    var accent: Color = .csGoldSolid
    var height: CGFloat = 38
    var cornerRadius: CGFloat = 14
    var horizontalPadding: CGFloat = 16
    var font: Font = .callout.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.black)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accent.opacity(0.95), Color.orange]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: accent.opacity(0.35), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// Glass card background and breathing glow modifier
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 14
    var accent: Color? = nil
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
            if let accent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [accent.opacity(0.35), accent.opacity(0.05)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.14)
                    .blur(radius: 10)
            }
        }
    }
}

struct BreathingGlow: ViewModifier {
    var color: Color
    @State private var breathe = false
    func body(content: Content) -> some View {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        return content
            .shadow(color: color.opacity(breathe ? 0.45 : 0.15), radius: breathe ? 16 : 8, x: 0, y: 0)
            .scaleEffect(reduceMotion ? 1.0 : (breathe ? 1.01 : 1.0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
            .onAppear { if !reduceMotion { breathe = true } }
    }
}

extension View {
    func breathingGlow(color: Color) -> some View { self.modifier(BreathingGlow(color: color)) }
}

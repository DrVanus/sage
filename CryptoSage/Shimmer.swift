import SwiftUI

public struct ShimmerBar: View {
    @State private var phase: CGFloat = -120
    public var height: CGFloat
    public var cornerRadius: CGFloat

    public init(height: CGFloat = 10, cornerRadius: CGFloat = 4) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.10))
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.55), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 80)
                .offset(x: phase)
        }
        .frame(height: height)
        .mask(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 160
            }
        }
    }
}

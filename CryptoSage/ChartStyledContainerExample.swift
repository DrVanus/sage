import SwiftUI

struct ChartStyledContainerExample: View {
    @State private var crosshairX: CGFloat? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Chart Styled Container Example")
                .font(.headline)

            ChartStyledContainer(rows: 4, columns: 6, vignetteOpacity: 0.12) {
                // Simulated chart area fill (underlay)
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    Path { path in
                        let step = w / 60
                        path.move(to: CGPoint(x: 0, y: h))
                        for i in stride(from: 0, through: w, by: step) {
                            let t = Double(i / w)
                            let y = h * (0.6 - 0.15 * sin(t * 6 * .pi))
                            let p = CGPoint(x: i, y: y)
                            path.addLine(to: p)
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .chartAreaFill()
                }
                .padding(10)
                .overlay(
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let h = proxy.size.height
                        Path { path in
                            let step = w / 60
                            path.move(to: CGPoint(x: 0, y: h * 0.6))
                            for i in stride(from: 0, through: w, by: step) {
                                let t = Double(i / w)
                                let y = h * (0.6 - 0.15 * sin(t * 6 * .pi))
                                path.addLine(to: CGPoint(x: i, y: y))
                            }
                        }
                        .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .chartPrimaryLine()
                    }
                    .padding(10)
                )
            } overlay: {
                // Crosshair overlay that appears while dragging
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    if let x = crosshairX {
                        let clampedX = min(max(0, x), w)
                        let t = Double(clampedX / w)
                        let y = h * (0.6 - 0.15 * sin(t * 6 * .pi))
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 1)
                                .position(x: clampedX, y: h / 2)
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 6, height: 6)
                                .position(x: clampedX, y: y)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        crosshairX = value.location.x
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.15)) { crosshairX = nil }
                    }
            )
            .frame(height: 240)
            .padding(.horizontal)

            Text("Use ChartStyledContainer to wrap your real trading chart.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ChartStyledContainerExample()
}


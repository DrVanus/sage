import SwiftUI

struct ChartStyledContainerExample: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Chart Styled Container Example")
                .font(.headline)

            ChartStyledContainer(rows: 4, columns: 6) {
                // Simulated chart area fill (underlay)
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    Path { path in
                        let step = w / 60
                        var lastPoint: CGPoint = .zero
                        path.move(to: CGPoint(x: 0, y: h))
                        for i in stride(from: 0, through: w, by: step) {
                            let t = Double(i / w)
                            let y = h * (0.6 - 0.15 * sin(t * 6 * .pi))
                            let p = CGPoint(x: i, y: y)
                            if i == 0 { lastPoint = p }
                            path.addLine(to: p)
                            lastPoint = p
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
                        .stroke(style: StrokeStyle(lineWidth: 2.5, lineJoin: .round, lineCap: .round))
                        .chartPrimaryLine()
                    }
                    .padding(10)
                )
            }
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

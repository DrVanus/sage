import SwiftUI

struct HomeLineChartView: View {
    let data: [Double]
    var lineColor: Color = .green

    @State private var drawProgress: CGFloat = 0
    @State private var hasAnimated: Bool = false

    var body: some View {
        GeometryReader { geo in
            if data.count > 1,
               let minVal = data.min(),
               let maxVal = data.max(),
               maxVal > minVal {

                let range = maxVal - minVal
                let points: [CGPoint] = data.enumerated().map { (index, value) in
                    let xPos = geo.size.width * CGFloat(index) / CGFloat(data.count - 1)
                    let yPos = geo.size.height * (1 - CGFloat((value - minVal) / range))
                    return CGPoint(x: xPos, y: yPos)
                }

                ZStack {
                    let gridColor = Color.white.opacity(0.04)
                    ForEach(0..<3, id: \.self) { i in
                        let y = geo.size.height * CGFloat(i + 1) / 4.0
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(gridColor, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }

                    if let firstPoint = points.first {
                        Path { path in
                            let y = firstPoint.y
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                    }

                    Path { path in
                        guard let first = points.first, let last = points.last else { return }
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        path.addLine(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [lineColor.opacity(0.22), lineColor.opacity(0.04)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .trim(from: 0, to: max(0, min(1, drawProgress)))
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: lineColor.opacity(0.25), radius: 3, x: 0, y: 1)

                    // Soft outer glow on the main line (restored from older HomeView)
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .trim(from: 0, to: max(0, min(1, drawProgress)))
                    .stroke(lineColor.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .blur(radius: 4)
                    .opacity(0.25)

                    if let last = points.last {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                            .shadow(color: lineColor.opacity(0.35), radius: 3)
                            .position(last)
                    }
                }
                .onAppear {
                    let reduceMotion = UIAccessibility.isReduceMotionEnabled
                    if reduceMotion || hasAnimated {
                        drawProgress = 1
                    } else {
                        withAnimation(.easeInOut(duration: 0.6)) { drawProgress = 1 }
                        hasAnimated = true
                    }
                }
                .onChange(of: data.count) { _ in
                    drawProgress = 1
                }
                .drawingGroup(opaque: false)

            } else {
                Text("No Chart Data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}


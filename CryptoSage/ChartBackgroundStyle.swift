import SwiftUI

// MARK: - Semantic tokens for chart styling
public struct ChartTheme {
    public var panelCornerRadius: CGFloat = 14
    public var panelBorderColor: Color = Color.yellow.opacity(0.12)
    public var panelTopShade: Color = Color.black.opacity(0.30)
    public var panelBottomShade: Color = Color.black.opacity(0.15)

    public var gridMajor: Color = Color.white.opacity(0.10)
    public var gridMinor: Color = Color.white.opacity(0.06)

    public var linePrimary: Color = Color.yellow
    public var lineGlow: Color = Color.yellow.opacity(0.25)
    public var areaTop: Color = Color.yellow.opacity(0.18)
    public var areaBottom: Color = Color.yellow.opacity(0.02)

    public init() {}
}

// MARK: - Reusable background panel with glass depth
public struct ChartGlassBackground: View {
    public var theme: ChartTheme
    public var showBorder: Bool = true

    public init(theme: ChartTheme = ChartTheme(), showBorder: Bool = true) {
        self.theme = theme
        self.showBorder = showBorder
    }

    public var body: some View {
        ZStack {
            // Subtle vertical gradient to add depth
            RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.panelTopShade, theme.panelBottomShade],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Group {
                        if showBorder {
                            RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
                                .strokeBorder(theme.panelBorderColor, lineWidth: 1)
                        }
                    }
                )
        }
        .compositingGroup()
        .drawingGroup(opaque: false)
    }
}

// MARK: - Gridlines layer
public struct ChartGrid: View {
    public var rows: Int
    public var columns: Int
    public var theme: ChartTheme

    public init(rows: Int = 4, columns: Int = 0, theme: ChartTheme = ChartTheme()) {
        self.rows = max(0, rows)
        self.columns = max(0, columns)
        self.theme = theme
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                // Horizontal lines
                if rows > 0 {
                    for i in 0...rows {
                        let y = size.height * CGFloat(i) / CGFloat(rows)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        let isEdge = (i == 0 || i == rows)
                        context.stroke(path, with: .color(isEdge ? theme.gridMajor : theme.gridMinor), lineWidth: 0.5)
                    }
                }
                // Vertical lines
                if columns > 0 {
                    for j in 0...columns {
                        let x = size.width * CGFloat(j) / CGFloat(columns)
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        let isEdge = (j == 0 || j == columns)
                        context.stroke(path, with: .color(isEdge ? theme.gridMajor : theme.gridMinor), lineWidth: 0.5)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Container that hosts any chart content with background + grid
public struct ChartStyledContainer<Content: View, Overlay: View>: View {
    public var theme: ChartTheme
    public var rows: Int
    public var columns: Int
    public var content: () -> Content
    public var overlay: () -> Overlay

    public init(
        theme: ChartTheme = ChartTheme(),
        rows: Int = 4,
        columns: Int = 0,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder overlay: @escaping () -> Overlay = { EmptyView() }
    ) {
        self.theme = theme
        self.rows = rows
        self.columns = columns
        self.content = content
        self.overlay = overlay
    }

    public var body: some View {
        ZStack {
            ChartGlassBackground(theme: theme)
            ChartGrid(rows: rows, columns: columns, theme: theme)
            content()
                .clipShape(RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous))
            overlay()
        }
    }
}

// MARK: - Convenience modifiers for line + area styling
public extension View {
    func chartPrimaryLine(theme: ChartTheme = ChartTheme(), lineWidth: CGFloat = 2.5) -> some View {
        self
            .shadow(color: theme.lineGlow, radius: 6, x: 0, y: 0)
            .overlay(
                self
                    .foregroundStyle(
                        LinearGradient(colors: [theme.linePrimary, theme.linePrimary.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                    )
            )
    }

    func chartAreaFill(theme: ChartTheme = ChartTheme()) -> some View {
        self
            .foregroundStyle(
                LinearGradient(colors: [theme.areaTop, theme.areaBottom], startPoint: .top, endPoint: .bottom)
            )
    }
}

// MARK: - Preview / Example usage
struct ChartBackgroundStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChartStyledContainer {
                // Placeholder chart content for preview: a simple sine path
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    Path { path in
                        let step = w / 60
                        path.move(to: .init(x: 0, y: h * 0.6))
                        for i in stride(from: 0, through: w, by: step) {
                            let t = Double(i / w)
                            let y = h * (0.6 - 0.15 * sin(t * 8 * .pi))
                            path.addLine(to: .init(x: i, y: y))
                        }
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2.5, lineJoin: .round, lineCap: .round))
                    .chartPrimaryLine()
                }
                .padding(10)
            }
            .frame(height: 220)
            .padding(.horizontal)

            Text("Drop your existing chart view inside ChartStyledContainer to adopt the new background and grid.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .preferredColorScheme(.dark)
    }
}

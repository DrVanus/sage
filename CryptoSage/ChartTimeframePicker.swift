import SwiftUI

/// A reusable, brand-styled timeframe picker that can be presented as a popover or a sheet.
/// - Use with: ChartTimeframePicker(isPresented: $flag, selection: $interval)
/// - Optionally pass a custom set of supported intervals.
struct ChartTimeframePicker: View {
    @Binding var isPresented: Bool
    @Binding var selection: ChartInterval
    var supported: [ChartInterval]

    init(isPresented: Binding<Bool>, selection: Binding<ChartInterval>, supported: [ChartInterval]? = nil) {
        self._isPresented = isPresented
        self._selection = selection
        // Default list mirrors common intervals used across the app
        self.supported = supported ?? [.live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour, .oneDay, .oneWeek, .oneMonth, .threeMonth, .oneYear, .threeYear, .all]
    }

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Timeframe")
                    .font(DS.Fonts.axis)
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.Colors.gold)
                .buttonStyle(.plain)
            }

            // Grid of timeframe chips
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(supported, id: \.self) { interval in
                        timeframeChip(for: interval)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 260)

            // Footer Close button (gold capsule)
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Text("Close")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.96))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule()
                                .fill(DS.Colors.gold)
                                .overlay(
                                    LinearGradient(colors: [Color.white.opacity(0.16), Color.clear], startPoint: .top, endPoint: .center)
                                        .clipShape(Capsule())
                                )
                                .overlay(
                                    Capsule().stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Colors.badgeStroke.opacity(0.6), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .tint(DS.Colors.gold)
        .frame(minWidth: 260, maxWidth: 360) // encourage two columns on wider popovers
    }

    @ViewBuilder
    private func timeframeChip(for interval: ChartInterval) -> some View {
        let selected = (interval == selection)
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = interval
            }
        } label: {
            Text(interval.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.92))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    ZStack {
                        Capsule()
                            .fill(selected ? DS.Colors.gold : Color.white.opacity(0.08))
                        // top gloss
                        Capsule()
                            .fill(LinearGradient(colors: [Color.white.opacity(selected ? 0.18 : 0.10), .clear], startPoint: .top, endPoint: .center))
                        // rim
                        Capsule()
                            .stroke(selected ? DS.Colors.badgeStroke.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 0.8)
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(interval.rawValue))
        .accessibilityAddTraits(selection == interval ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var showing = true
    @Previewable @State var interval: ChartInterval = .oneHour
    return ZStack {
        Color.black.ignoresSafeArea()
        ChartTimeframePicker(isPresented: $showing, selection: $interval)
            .padding()
    }
}

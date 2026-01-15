import SwiftUI

struct TechnicalsIndicatorListView: View {
    let indicators: [IndicatorSignal]

    private func color(for s: IndicatorSignalStrength) -> Color {
        switch s {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(indicators) { item in
                HStack {
                    Text(item.label)
                        .foregroundColor(.white)
                        .font(.subheadline)
                    Spacer()
                    if let v = item.valueText, !v.isEmpty {
                        Text(v)
                            .foregroundColor(.white.opacity(0.7))
                            .font(.caption)
                    }
                    Text(item.signal.rawValue.capitalized)
                        .foregroundColor(color(for: item.signal))
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            }
        }
    }
}

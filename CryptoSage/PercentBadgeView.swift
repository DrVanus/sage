import SwiftUI

struct PercentBadgeView: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let backdrop: Color
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.5)
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backdrop, in: Capsule())
            .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .trailing)
    }
}

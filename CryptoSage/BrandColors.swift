import SwiftUI

public enum BrandColors {
    public static let goldLight: Color = Color(red: 0.9647, green: 0.8275, blue: 0.3961) // #F6D365
    public static let goldDark:  Color = Color(red: 0.8314, green: 0.6863, blue: 0.2157) // #D4AF37

    public static var goldHorizontal: LinearGradient {
        LinearGradient(colors: [goldLight, goldDark], startPoint: .leading, endPoint: .trailing)
    }

    public static var goldVertical: LinearGradient {
        LinearGradient(colors: [goldLight, goldDark], startPoint: .top, endPoint: .bottom)
    }

    public static var gold: Color {
        goldDark
    }

    public static var goldStrokeHighlight: Color {
        goldLight.opacity(0.9)
    }

    public static var goldStrokeShadow: Color {
        goldDark.opacity(0.9)
    }
}

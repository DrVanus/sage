import SwiftUI

extension Color {
    static var brandAccent: Color {
        #if canImport(UIKit)
        if UIColor(named: "BrandAccent") != nil {
            return Color("BrandAccent")
        } else {
            return .yellow
        }
        #elseif canImport(AppKit)
        if NSColor(named: "BrandAccent") != nil {
            return Color("BrandAccent")
        } else {
            return .yellow
        }
        #else
        return .yellow
        #endif
    }
}

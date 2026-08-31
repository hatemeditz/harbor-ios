import Foundation
import SwiftUI

enum Theme {
    static let background = Color(red: 0.045, green: 0.047, blue: 0.05)
    static let surface = Color(red: 0.075, green: 0.078, blue: 0.082)
    static let surfaceRaised = Color(red: 0.12, green: 0.123, blue: 0.13)
    static let surfaceSelected = Color(red: 0.16, green: 0.163, blue: 0.17)
    static let accent = Color(red: 0.96, green: 0.58, blue: 0.25)
    static let accentSoft = Color(red: 0.34, green: 0.20, blue: 0.105)
    static let border = Color.white.opacity(0.09)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)

    static let cardRadius: CGFloat = 14
    static let pillRadius: CGFloat = 18

    static func posterPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cardRadius)
            .fill(surfaceRaised)
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: "film")
                    .foregroundColor(textSecondary.opacity(0.4))
            )
    }
}

extension Color {
    init(harborHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        switch cleaned.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

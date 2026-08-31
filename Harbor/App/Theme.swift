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

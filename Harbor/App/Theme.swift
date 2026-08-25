import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let surface = Color(red: 0.09, green: 0.11, blue: 0.16)
    static let surfaceRaised = Color(red: 0.13, green: 0.15, blue: 0.22)
    static let accent = Color(red: 0.31, green: 0.64, blue: 1.0)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)

    static func posterPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(surfaceRaised)
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: "film")
                    .foregroundColor(textSecondary.opacity(0.4))
            )
    }
}

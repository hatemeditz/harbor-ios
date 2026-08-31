import SwiftUI

struct HarborWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            Image("HarborMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: compact ? 25 : 31, height: compact ? 25 : 31)
                .foregroundColor(.white)

            Text("Harbor")
                .font(.system(size: compact ? 23 : 29, weight: .bold, design: .serif))
                .tracking(-0.8)
                .foregroundColor(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Harbor")
    }
}

struct HarborPageHeader: View {
    let title: String
    var eyebrow: String?
    var subtitle: String?
    var showsWordmark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsWordmark {
                HarborWordmark()
                    .padding(.bottom, 12)
            }
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.2)
                    .foregroundColor(Theme.accent)
            }
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .serif))
                .tracking(-0.8)
                .foregroundColor(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HarborSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }
}

struct HarborFilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(selected ? .black : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? Color.white : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct HarborSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundColor(Theme.textSecondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Theme.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

struct HarborPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundColor(.black)
            .padding(.horizontal, 18)
            .frame(minHeight: 43)
            .background(Color.white.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct HarborSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 43)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.65 : 0.92), in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    func harborNavigationChrome() -> some View {
        self
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

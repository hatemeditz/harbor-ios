import SwiftUI

private enum HarborTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case discover = "Discover"
    case library = "Library"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .discover: return "safari"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject private var auth = AuthStore.shared
    @State private var selectedTab: HarborTab = .home

    var body: some View {
        if auth.isSignedIn {
            tabs
        } else {
            LoginView()
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(HarborTab.home)
                .tabItem {
                    Label(HarborTab.home.rawValue, systemImage: "house.fill")
                }
            SearchView()
                .tag(HarborTab.discover)
                .tabItem {
                    Label(HarborTab.discover.rawValue, systemImage: "safari.fill")
                }
            LibraryView()
                .tag(HarborTab.library)
                .tabItem {
                    Label(HarborTab.library.rawValue, systemImage: "books.vertical.fill")
                }
            SettingsView()
                .tag(HarborTab.settings)
                .tabItem {
                    Label(HarborTab.settings.rawValue, systemImage: "gearshape.fill")
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customTabBar
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 4) {
            ForEach(HarborTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedTab == tab ? "\(tab.icon).fill" : tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(selectedTab == tab ? .white : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        selectedTab == tab ? Theme.surfaceRaised : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("harbor.tab.\(tab.rawValue.lowercased())")
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Theme.background.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }
}

#Preview {
    RootView()
}

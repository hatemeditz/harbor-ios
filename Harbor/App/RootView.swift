import SwiftUI

struct RootView: View {
    @ObservedObject private var auth = AuthStore.shared

    var body: some View {
        if auth.isSignedIn {
            tabs
        } else {
            LoginView()
        }
    }

    private var tabs: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    RootView()
}

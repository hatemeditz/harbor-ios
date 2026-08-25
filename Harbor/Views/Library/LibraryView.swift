import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableCompat(
                icon: "books.vertical.fill",
                title: "Library",
                message: "Continue Watching and your watchlist sync in Milestone 4."
            )
            .navigationTitle("Library")
        }
    }
}

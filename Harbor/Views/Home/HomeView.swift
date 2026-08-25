import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "anchor")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.accent)
                    Text("Harbor")
                        .font(.title.bold())
                    Text("Home rails arrive in Milestone 3.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 120)
            }
            .background(Theme.background)
            .navigationTitle("Home")
        }
    }
}

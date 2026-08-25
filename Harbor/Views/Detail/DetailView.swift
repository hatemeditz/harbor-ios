import SwiftUI

/// Temporary detail placeholder — replaced with the full detail page in M5.
struct DetailView: View {
    let meta: Meta

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: URL(string: (meta.background ?? meta.poster) ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.surfaceRaised
                    }
                }
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipped()

                HStack(alignment: .top, spacing: 14) {
                    PosterCard(meta: meta, width: 100, showTitle: false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meta.name)
                            .font(.title2.bold())
                        if let year = meta.releaseInfo, !year.isEmpty {
                            Text(year).foregroundColor(Theme.textSecondary)
                        }
                        if let rating = meta.imdbRating, !rating.isEmpty {
                            Label(rating, systemImage: "star.fill")
                                .font(.subheadline)
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if let description = meta.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 16)
                }

                Text("Full detail view arrives in Milestone 5.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

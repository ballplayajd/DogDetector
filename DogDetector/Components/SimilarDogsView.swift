import SwiftUI

struct SimilarDogsView: View {
    let baseURL: URL
    var dogViewModel: DogViewModel

    @State private var baseImage: CGImage?
    @State private var results: [(image: CGImage, score: Float)] = []
    @State private var isLoading = true
    @State private var progress: (done: Int, total: Int) = (0, 0)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                baseDogSection
                Divider()
                similarDogsSection
            }
            .padding()
        }
        .navigationTitle("Similar Dogs")
        .task {
            baseImage = try? await dogViewModel.getImageFor(url: baseURL)
            results = await dogViewModel.fetchAndRankSimilarDogs(for: baseURL, candidateCount: 50) { done, total in
                progress = (done, total)
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private var baseDogSection: some View {
        VStack(spacing: 8) {
            Text("Selected Dog")
                .font(.headline)
            if let baseImage {
                Image(decorative: baseImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ProgressView()
                    .frame(height: 200)
            }
        }
    }

    @ViewBuilder
    private var similarDogsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Similar Dogs")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: progress.total > 0 ? Double(progress.done) : 0, total: max(Double(progress.total), 1))
                    Text(progress.total > 0
                         ? "Processing \(progress.done)/\(progress.total) dogs..."
                         : "Fetching dogs...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            } else if results.isEmpty {
                Text("No similar dogs found")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        VStack(spacing: 4) {
                            Image(decorative: result.image, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(String(format: "Similarity: %.2f", result.score))
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }
}

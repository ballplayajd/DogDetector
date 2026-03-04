import SwiftUI

struct ImageDetectionView: View {
    let url: URL
    var dogViewModel: DogViewModel

    @State var cgImage: CGImage?
    @State var error: String?

    var body: some View {
        NavigationLink(value: url) {
            image
                .aspectRatio(contentMode: .fill)
                .overlay(content: {errorOverlay})
        }
        .task(id: "\(url)\(dogViewModel.showDetection)") {
            await updateImage()
            await dogViewModel.runEmbedding(for: url)
        }
    }

    @ViewBuilder
    var errorOverlay: some View {
        if let errorMessage = error {
            VStack {
                Spacer()
                Text(errorMessage)
                    .foregroundColor(Color.white)
                Spacer()
            }
            .frame(minWidth: .zero, maxWidth: .infinity)
            .background(Color.black.opacity(0.5))
        }
    }

    @ViewBuilder
    var image: some View {
        if let cgImage = cgImage {
            Image(decorative: cgImage, scale: 1)
                .resizable()
        } else {
            Rectangle()
        }
    }

    func updateImage() async {
        do {
            self.error = nil
            guard let sourceImage = try? await dogViewModel.getImageFor(url: url) else {
                self.error = "Image download failed"
                return
            }
            self.cgImage = sourceImage
            if dogViewModel.showDetection {
                let detectionResult = try await dogViewModel.dogDetectionService.detectBreed(for: sourceImage)
                guard !detectionResult.isEmpty else { return }
                self.cgImage = sourceImage.lensHighlightRegions(
                    regions: detectionResult.map { $0.boxes },
                    outsideBlurRadius: 10
                )?.drawingNormalizedKeypoints(dogViewModel.showKeypoints ? detectionResult.flatMap { $0.keypoints } : nil)
            }
        } catch DogDetectionService.DogDetectionError.requestAlreadyRunning {
            self.error = nil
        } catch is CancellationError {
            self.error = nil
        } catch {
            self.error = nil
        }
    }
}

#Preview {
    NavigationStack {
        ImageDetectionView(
            url: URL(string: "https://images.dog.ceo/breeds/mountain-swiss/n02107574_1597.jpg")!,
            dogViewModel: DogViewModel()
        )
        .scaledToFit()
    }
}

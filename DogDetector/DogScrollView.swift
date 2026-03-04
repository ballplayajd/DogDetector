import SwiftUI

struct DogScrollView: View {
    @State var dogViewModel: DogViewModel = DogViewModel()
    @State var showCamera: Bool = false

    var body: some View {
        NavigationStack {
            dogScrollView
                .navigationTitle("Dog Detector")
                .navigationDestination(for: URL.self) { url in
                    SimilarDogsView(baseURL: url, dogViewModel: dogViewModel)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showCamera = true
                        }) {
                            Image(systemName: "camera")
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing, content: {detectionToggle})
                .task {
                    await dogViewModel.getDogImages()
                }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(dogDetectionService: dogViewModel.dogDetectionService)
        }
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                dogViewModel.errorMessage = nil
            }
        } message: {
            Text(dogViewModel.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    var detectionToggle: some View {
        HStack {
            Toggle(isOn: $dogViewModel.showDetection, label: {
                Text("Show Detection")
                    .foregroundColor(.white)
            })
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .frame(width: 240)
        .padding(16)
    }

    var dogScrollView: some View {
        List {
            ForEach(Array(dogViewModel.dogImages.enumerated()), id: \.element) { urlIndex, url in
                ImageDetectionView(url: url, dogViewModel: dogViewModel)
                    .task {
                        if urlIndex > dogViewModel.dogImages.count - 3 {
                            await dogViewModel.getDogImages()
                        }
                    }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { dogViewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    dogViewModel.errorMessage = nil
                }
            }
        )
    }
}

#Preview {
    DogScrollView()
}

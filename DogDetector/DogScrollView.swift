//
//  DogScrollView.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//


import SwiftUI

@Observable
class DogViewModel {
    let dogService = DogService()
    
    var dogImages: [URL] = []
    var isFetching = false
    
    func getDogImages() async {
        if !isFetching {
            defer { isFetching = false }
            isFetching = true
            do {
                let newDogImages = try await dogService.fetchDogImages()
                dogImages.append(contentsOf: newDogImages)
            } catch {
                self.dogImages = []
            }
        }
    }
}

struct DogImage: View {
    @State var loadedImage: UIImage? = nil
   
    let url: URL
    var dogViewModel: DogViewModel
    
    var body: some View {
        image
            .aspectRatio(contentMode: .fill)
            .task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data) {
                        self.loadedImage = uiImage
                    }
                } catch {
                    // Optionally log the error or handle it
                }
            }
    }
    
    @ViewBuilder
    var image: some View {
        if let loadedImage = loadedImage {
            Image(uiImage: loadedImage)
                .resizable()
        }else{
            Rectangle()
        }
    }
}

struct DogScrollView: View {
    @State var dogViewModel: DogViewModel = DogViewModel()
    var body: some View {
        ScrollView{
            LazyVStack{
                ForEach(0..<dogViewModel.dogImages.count, id: \.self){urlIndex in
                    DogImage(url: dogViewModel.dogImages[urlIndex], dogViewModel: dogViewModel)
                        .onAppear {
                            if urlIndex > dogViewModel.dogImages.count - 3 {
                                Task {
                                    await dogViewModel.getDogImages()
                                }
                            }
                        }
                }
            }
        }
        .task{
            await dogViewModel.getDogImages()
        }
    }
}

#Preview {
    DogScrollView()
}

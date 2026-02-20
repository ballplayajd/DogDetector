//
//  DogScrollView.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//


import SwiftUI

struct DogScrollView: View {
    @State var dogViewModel: DogViewModel = DogViewModel()
    
    var body: some View {
        NavigationStack{
            dogScrollView
                .navigationTitle("Dog Detector")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            
                        }) {
                            Image(systemName: "camera")
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing, content: {detectionToggle})
                .task{
                    await dogViewModel.getDogImages()
                }
        }
    }
    
    @ViewBuilder
    var detectionToggle: some View {
        HStack{
            Toggle(isOn: $dogViewModel.showDetection, label: {
                Text("Show Detection")
                    .foregroundColor(.white)
            })
           
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        )
        .frame(width: 240)
        .padding(16)
    }

    
    
    var dogScrollView: some View {
        ScrollView{
            LazyVStack{
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
    }
    
}

#Preview {
    DogScrollView()
}

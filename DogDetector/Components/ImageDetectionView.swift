//
//  ImageDetectionView.swift
//  ImageDetectionView
//
//  Created by Joe Donino on 2/19/26.
//

import SwiftUI

struct ImageDetectionView: View {
    let url: URL
    var dogViewModel: DogViewModel
    
    @State var cgImage: CGImage?
    
    var body: some View {
        image
            .aspectRatio(contentMode: .fill)
            .task(id: "\(url)\(dogViewModel.showDetection)") {
                self.cgImage = await dogViewModel.getImageFor(url: url)
            }
    }
    
    @ViewBuilder
    var image: some View {
        if let cgImage = cgImage {
            Image(decorative: cgImage, scale: 1)
                .resizable()
        }else{
            Rectangle()
        }
    }
    
    @ViewBuilder
    var boxOverlay: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 24)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
                .frame(width: 320, height: 300)
                .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }
    }
    

}

#Preview {
    ImageDetectionView(url: URL(string: "https://images.dog.ceo/breeds/mountain-swiss/n02107574_1597.jpg")!, dogViewModel: DogViewModel())
        .scaledToFit()
}

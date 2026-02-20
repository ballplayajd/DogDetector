//
//  CameraView.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import SwiftUI
import QuartzCore

@Observable
class CameraViewModel {
    
    private let cameraManager = CameraManager()
    let dogDetectionService: DogDetectionService
    
    var showKeypoints = true
    
    var currentFrame: CGImage?
    
    
    init(dogDetectionService: DogDetectionService) {
        self.dogDetectionService = dogDetectionService
        Task {
            await handleCameraPreviews()
        }
    }
    
    func start(){
        self.cameraManager.startSession()
    }
    
    func stop(){
        self.cameraManager.stopSession()
    }
    
    func handleCameraPreviews() async {
        for await image in cameraManager.previewStream {
            Task{@MainActor in
                do{
                    let detectionResult = try await dogDetectionService.detectBreed(for: image)
                    self.currentFrame = image.lensHighlightRegions(
                        regions: detectionResult.map{$0.boxes},
                        outsideBlurRadius: 10
                    )?.drawingNormalizedKeypoints(showKeypoints ? detectionResult.flatMap{$0.keypoints} : nil)
                }catch{
                    self.currentFrame = image
                }
            }
        }
    }
}


struct CameraView: View {
    @Environment(\.dismiss) var dismiss
    
    @State var cameraViewModel: CameraViewModel
    
    init(dogDetectionService: DogDetectionService) {
        self.cameraViewModel = CameraViewModel(dogDetectionService: dogDetectionService)
    }
    var body: some View {
        GeometryReader { geometry in
            if let image = cameraViewModel.currentFrame {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width,
                           height: geometry.size.height)
            } else {
                VStack{
                    Text("Content Unavailable")
                    Image(systemName: "xmark.circle.fill")
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .overlay(alignment: .topLeading, content: {exitButton})
        .onAppear(){
            cameraViewModel.start()
        }
        .onDisappear(){
            cameraViewModel.stop()
        }
    }
    
    var exitButton: some View {
        Button(action: {
            dismiss()
        }){
            Image(systemName: "xmark")
                .font(Font.system(size: 24))
                .foregroundColor(.white)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .padding(16)
    }
}



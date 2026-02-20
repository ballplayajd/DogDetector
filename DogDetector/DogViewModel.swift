//
//  DogViewModel.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import SwiftUI
import ImageIO


struct DetectionResult {
    let boxes: CGRect
    let keypoints: [(point: CGPoint, conf: Float)]
}

struct DogImageEntry {
    let cgImage: CGImage
    var detectionResult: [DetectionResult]?
}

@Observable
@MainActor
class DogViewModel {
    let dogService = DogService()
    let dogDetectionService = DogDetectionService()
    var showDetection: Bool = true
    var showKeypoints: Bool = true
    
    
    var dogImages: [URL] = []
    private var imageEntries: [String: DogImageEntry] = [:]
    var isFetching = false
    
    func getDogImages() async {
        if !isFetching {
            defer { isFetching = false }
            isFetching = true
            do {
                let newDogImages = try await dogService.fetchDogImages()
                dogImages.append(contentsOf: newDogImages)
            } catch {
               // self.dogImages = []
            }
        }
    }
    
    func detectBreed(for image: CGImage, cacheKey _: String?) async -> [DetectionResult] {
        var detectionResults: [DetectionResult] = []
        let poses = await dogDetectionService.runDetection(cgImage: image)
        for pose in poses{
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            let normalizedBox = CGRect(
                x: (pose.boxInOriginalPixels.minX / width),
                y: (pose.boxInOriginalPixels.minY / height),
                width: (pose.boxInOriginalPixels.width / width),
                height: (pose.boxInOriginalPixels.height / height)
            )
            detectionResults.append(DetectionResult(
                boxes: normalizedBox,
                keypoints: pose.keypointsNormalized
            ))
        }
        return detectionResults
    }

    func prepareImageIfNeeded(for url: URL) async {
        let key = url.absoluteString
        if imageEntries[key] != nil { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let cgImage = cgImage(from: data) else { return }
            imageEntries[key] = DogImageEntry(
                cgImage: cgImage,
                detectionResult: nil
            )
        } catch {
            return
        }
    }
    
    func getImageFor(url: URL) async -> CGImage?{
        await prepareImageIfNeeded(for: url)
        if var entry = imageEntries[url.absoluteString] {
            if showDetection {
                if let detectionResult = entry.detectionResult {
                    return entry.cgImage.lensHighlightRegions(
                        regions: detectionResult.map{$0.boxes},
                        outsideBlurRadius: 10
                    )?.drawingNormalizedKeypoints(showKeypoints ? entry.detectionResult?.flatMap{$0.keypoints} : nil)
                }else{
                    let detectionResult = await detectBreed(for: entry.cgImage, cacheKey: url.absoluteString)
                    entry.detectionResult = detectionResult
                    imageEntries[url.absoluteString] = entry
                    return entry.cgImage.lensHighlightRegions(
                        regions: detectionResult.map{$0.boxes},
                        outsideBlurRadius: 10
                    )?.drawingNormalizedKeypoints(showKeypoints ? entry.detectionResult?.flatMap{$0.keypoints} : nil)
                }
            }else{
                return entry.cgImage
            }
        }
        return nil
    }

    private func cgImage(from data: Data) -> CGImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct DogPose {
    let score: Float
    let boxInOriginalPixels: CGRect
    let keypointsInOriginalPixels: [(point: CGPoint, conf: Float)]
    let keypointsNormalized: [(point: CGPoint, conf: Float)]
}

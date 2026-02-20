//
//  DogViewModel.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import SwiftUI
import ImageIO


final class DogImageEntry: NSObject {
    let cgImage: CGImage
    var detectionResult: [DetectionResult]?

    init(cgImage: CGImage, detectionResult: [DetectionResult]?) {
        self.cgImage = cgImage
        self.detectionResult = detectionResult
    }
}

@Observable
@MainActor
class DogViewModel {
    let dogService = DogService()
    let dogDetectionService = DogDetectionService()
    var showDetection: Bool = true
    var showKeypoints: Bool = true
    var errorMessage: String?
    
    var dogImages: [URL] = []
    private let imageEntries = NSCache<NSString, DogImageEntry>()
    var isFetching = false

    init() {
        imageEntries.countLimit = 120
        imageEntries.totalCostLimit = 256 * 1024 * 1024
    }
    
    func getDogImages() async {
        if !isFetching {
            defer { isFetching = false }
            isFetching = true
            do {
                let newDogImages = try await dogService.fetchDogImages()
                let existing = Set(dogImages)
                let uniqueNew = newDogImages.reduce(into: [URL]()) { result, url in
                    if !existing.contains(url) && !result.contains(url) {
                        result.append(url)
                    }
                }
                dogImages.append(contentsOf: uniqueNew)
            } catch {
                self.errorMessage = errorMessage?.debugDescription
            }
        }
    }
    
    
    func prepareImageIfNeeded(for url: URL) async {
        let key = cacheKey(for: url)
        if imageEntries.object(forKey: key) != nil { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let cgImage = cgImage(from: data) else { return }
            let entry = DogImageEntry(
                cgImage: cgImage,
                detectionResult: nil
            )
            imageEntries.setObject(entry, forKey: key, cost: imageCost(cgImage))
        } catch {
            return
        }
    }
    
    func getImageFor(url: URL) async throws -> CGImage?{
        await prepareImageIfNeeded(for: url)
        if let entry = imageEntries.object(forKey: cacheKey(for: url)) {
            return entry.cgImage
        }
        return nil
    }

    private func cgImage(from data: Data) -> CGImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func cacheKey(for url: URL) -> NSString {
        url.absoluteString as NSString
    }

    private func imageCost(_ image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}


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
    var embedding: [Float]?

    init(cgImage: CGImage, detectionResult: [DetectionResult]?, embedding: [Float]? = nil) {
        self.cgImage = cgImage
        self.detectionResult = detectionResult
        self.embedding = embedding
    }
}

@Observable
@MainActor
class DogViewModel {
    let dogService = DogService()
    let dogDetectionService = DogDetectionService()
    let dogEmbeddingService = DogEmbeddingService()
    var showDetection: Bool = true
    var showKeypoints: Bool = true
    var errorMessage: String?
    
    var dogImages: [URL] = []
    var embeddingsByURL: [URL: [Float]] = [:]
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
            } catch is CancellationError {
                // Task cancelled by SwiftUI during scroll — ignore
            } catch {
               // self.errorMessage = error.localizedDescription
            }
        }
    }
    
    
    func prepareImageIfNeeded(for url: URL) async {
        let key = cacheKey(for: url)
        if imageEntries.object(forKey: key) != nil { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let cgImage = cgImage(from: data) else {
                print("[SimilarDogs] prepareImageIfNeeded decode failed: \(url.absoluteString)")
                return
            }
            let entry = DogImageEntry(
                cgImage: cgImage,
                detectionResult: nil,
                embedding: nil
            )
            imageEntries.setObject(entry, forKey: key, cost: imageCost(cgImage))
            print("[SimilarDogs] Cached image: \(url.lastPathComponent)")
        } catch {
            print("[SimilarDogs] prepareImageIfNeeded download failed: \(url.absoluteString), error: \(error)")
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

    func runEmbedding(for url: URL) async {
        guard embeddingsByURL[url] == nil else { return }
        do {
            guard let croppedDog = await getPrimaryDogCrop(for: url) else { return }
            let embedding = try await dogEmbeddingService.predict(for: croppedDog)
            let key = cacheKey(for: url)
            imageEntries.object(forKey: key)?.embedding = embedding
            embeddingsByURL[url] = embedding
            print("[SimilarDogs] Saved embedding dim=\(embedding.count) for \(url.lastPathComponent)")
        } catch {
            print("[SimilarDogs] Embedding failed for \(url.lastPathComponent), error: \(error)")
        }
    }

    func fetchAndRankSimilarDogs(for targetURL: URL) async -> [(image: CGImage, score: Float)] {
        print("[SimilarDogs] fetchAndRank start target=\(targetURL.lastPathComponent)")
        await runEmbedding(for: targetURL)
        guard let targetEmbedding = embeddingsByURL[targetURL] else {
            print("[SimilarDogs] Missing target embedding for \(targetURL.lastPathComponent)")
            return []
        }

        let newURLs: [URL]
        do {
            newURLs = try await dogService.fetchDogImages()
            print("[SimilarDogs] Fetched \(newURLs.count) candidate URLs")
        } catch {
            print("[SimilarDogs] Failed to fetch candidate URLs: \(error)")
            return []
        }

        for url in newURLs {
            await prepareImageIfNeeded(for: url)
            await runEmbedding(for: url)
        }

        var results: [(image: CGImage, score: Float)] = []
        for url in newURLs {
            guard let embedding = embeddingsByURL[url],
                  let similarity = cosineSimilarity(targetEmbedding, embedding),
                  let image = imageEntries.object(forKey: cacheKey(for: url))?.cgImage
            else { continue }
            results.append((image: image, score: similarity))
        }
        results.sort { $0.score > $1.score }
        print("[SimilarDogs] Returning \(results.count) ranked results")
        return results
    }

    func getPrimaryDogCrop(for url: URL) async -> CGImage? {
        await prepareImageIfNeeded(for: url)
        let key = cacheKey(for: url)
        guard let entry = imageEntries.object(forKey: key) else {
            print("[SimilarDogs] No cached image entry for \(url.lastPathComponent)")
            return nil
        }

        if entry.detectionResult == nil {
            entry.detectionResult = try? await dogDetectionService.detectBreed(for: entry.cgImage)
        }
        guard let detections = entry.detectionResult else {
            print("[SimilarDogs] No detections for \(url.lastPathComponent)")
            return nil
        }
        print("[SimilarDogs] Detections count=\(detections.count) for \(url.lastPathComponent)")
        guard let box = detections.max(by: { $0.boxes.width * $0.boxes.height < $1.boxes.width * $1.boxes.height })?.boxes else {
            print("[SimilarDogs] No primary box for \(url.lastPathComponent)")
            return nil
        }
        let crop = entry.cgImage.cropped(toNormalizedRect: box)
        if crop == nil {
            print("[SimilarDogs] Crop failed for \(url.lastPathComponent), box=\(box)")
        }
        return crop
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

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0
        for i in 0..<lhs.count {
            dot += lhs[i] * rhs[i]
            lhsNorm += lhs[i] * lhs[i]
            rhsNorm += rhs[i] * rhs[i]
        }
        let denom = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denom > 0 else { return nil }
        return dot / denom
    }
}


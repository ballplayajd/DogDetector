//
//  DogViewModel.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import SwiftUI
import ImageIO
import Accelerate


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
            let raw = try await dogEmbeddingService.predict(for: croppedDog)
            let embedding = l2Normalize(raw)
            let key = cacheKey(for: url)
            imageEntries.object(forKey: key)?.embedding = embedding
            embeddingsByURL[url] = embedding
            print("[SimilarDogs] Saved embedding dim=\(embedding.count) for \(url.lastPathComponent)")
        } catch {
            print("[SimilarDogs] Embedding failed for \(url.lastPathComponent), error: \(error)")
        }
    }

    func fetchAndRankSimilarDogs(
        for targetURL: URL,
        candidateCount: Int = 50,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> [(image: CGImage, score: Float)] {
        print("[SimilarDogs] fetchAndRank start target=\(targetURL.lastPathComponent) candidates=\(candidateCount)")
        await runEmbedding(for: targetURL)
        guard let targetEmbedding = embeddingsByURL[targetURL] else {
            print("[SimilarDogs] Missing target embedding for \(targetURL.lastPathComponent)")
            return []
        }

        let newURLs: [URL]
        do {
            newURLs = try await dogService.fetchDogImages(count: candidateCount)
            print("[SimilarDogs] Fetched \(newURLs.count) candidate URLs")
        } catch {
            print("[SimilarDogs] Failed to fetch candidate URLs: \(error)")
            return []
        }

        for (i, url) in newURLs.enumerated() {
            await prepareImageIfNeeded(for: url)
            await runEmbedding(for: url)
            onProgress?(i + 1, newURLs.count)
        }

        let candidates = newURLs.compactMap { url -> (url: URL, embedding: [Float])? in
            guard let embedding = embeddingsByURL[url] else { return nil }
            return (url: url, embedding: embedding)
        }
        let ranked = rankBySimilarity(target: targetEmbedding, candidates: candidates)

        var results: [(image: CGImage, score: Float)] = []
        results.reserveCapacity(ranked.count)
        for entry in ranked {
            if let image = imageEntries.object(forKey: cacheKey(for: entry.url))?.cgImage {
                results.append((image: image, score: entry.score))
            }
        }
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

    private func l2Normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 0 else { return v }
        var result = [Float](repeating: 0, count: v.count)
        var divisor = norm
        vDSP_vsdiv(v, 1, &divisor, &result, 1, vDSP_Length(v.count))
        return result
    }

    private func dotProduct(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &dot, vDSP_Length(lhs.count))
        return dot
    }

    private func rankBySimilarity(
        target: [Float],
        candidates: [(url: URL, embedding: [Float])]
    ) -> [(url: URL, score: Float)] {
        let dim = target.count
        let n = candidates.count
        guard dim > 0, n > 0 else { return [] }

        var matrix = [Float](repeating: 0, count: n * dim)
        for i in 0..<n {
            matrix.replaceSubrange(i * dim..<(i + 1) * dim, with: candidates[i].embedding)
        }

        var scores = [Float](repeating: 0, count: n)
        cblas_sgemv(
            CblasRowMajor, CblasNoTrans,
            Int32(n), Int32(dim),
            1.0, &matrix, Int32(dim),
            target, 1,
            0.0, &scores, 1
        )

        var indexed = [(url: URL, score: Float)]()
        indexed.reserveCapacity(n)
        for i in 0..<n {
            indexed.append((url: candidates[i].url, score: scores[i]))
        }
        indexed.sort { $0.score > $1.score }
        return indexed
    }
}


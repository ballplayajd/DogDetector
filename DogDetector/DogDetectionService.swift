//
//  DogDetector.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import CoreML
import Vision

final class DogDetectionService {
    private var request: VNRequest!
    private var inFlightContinuation: CheckedContinuation<[DogPose], Never>?
    private var pendingOriginalSize: CGSize = .zero
    private let modelInputSize = CGSize(width: 640, height: 640)
    
    var isProcessing: Bool = false
    
    init() {
        setupCoreML()
    }
    
    private func setupCoreML() {
        let modelConfig = MLModelConfiguration()
        modelConfig.allowLowPrecisionAccumulationOnGPU = false
        modelConfig.computeUnits = .cpuAndNeuralEngine
        guard let model = try? VNCoreMLModel(for: dog_pose(configuration: modelConfig).model) else {
            fatalError("Failed to load CoreML model")
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            self?.processPredictions(for: request, error: error)
        }
        request.imageCropAndScaleOption = .scaleFit
        self.request = request
    }
    
    func runDetection(cgImage: CGImage) async -> [DogPose] {
        if isProcessing { return [] }
        isProcessing = true
        pendingOriginalSize = CGSize(width: cgImage.width, height: cgImage.height)

        return await withCheckedContinuation { continuation in
            inFlightContinuation = continuation
            performRequest(cgImage: cgImage)
        }
    }

    private func performRequest(cgImage: CGImage) {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Detection error: \(error)")
            isProcessing = false
            inFlightContinuation?.resume(returning: [])
            inFlightContinuation = nil
        }
    }
    
    private func processPredictions(for request: VNRequest, error: Error?){
        defer { isProcessing = false }

        if let error {
            print("VN error: \(error)")
            inFlightContinuation?.resume(returning: [])
            inFlightContinuation = nil
            return
        }

        guard
            let observations = request.results as? [VNCoreMLFeatureValueObservation]
        else {
            inFlightContinuation?.resume(returning: [])
            inFlightContinuation = nil
            return
        }
        var poses: [DogPose] = []
        for obs in observations {
            let decodedPoses = decodeDogPoses(
                observation: obs,
                originalSize: pendingOriginalSize,
                modelInputSize: modelInputSize,
                scoreThreshold: 0.25
            )
            poses.append(contentsOf: decodedPoses)
        }
        let filteredPoses = nonMaxSuppression(poses, iouThreshold: 0.25)
        inFlightContinuation?.resume(returning: filteredPoses)
        inFlightContinuation = nil
    }

    private func decodeDogPoses(
        observation: VNCoreMLFeatureValueObservation,
        originalSize: CGSize,
        modelInputSize: CGSize,
        scoreThreshold: Float
    ) -> [DogPose] {
        guard let arr = observation.featureValue.multiArrayValue,
              arr.dataType == .float32,
              arr.shape.count == 3
        else { return [] }

        let batch = arr.shape[0].intValue
        let channels = arr.shape[1].intValue
        let predictions = arr.shape[2].intValue
        guard batch == 1, channels == 77 else { return [] }

        let ptr = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
        let strideB = arr.strides[0].intValue
        let strideC = arr.strides[1].intValue
        let strideN = arr.strides[2].intValue
        func at(c: Int, n: Int) -> Float32 {
            let index = 0 * strideB + c * strideC + n * strideN
            return ptr[index]
        }

        let inW = modelInputSize.width
        let inH = modelInputSize.height
        let origW = originalSize.width
        let origH = originalSize.height
        let scale = min(inW / origW, inH / origH)
        let newW = origW * scale
        let newH = origH * scale
        let padX = (inW - newW) / 2
        let padY = (inH - newH) / 2

        func unletterboxPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - padX) / scale, y: (p.y - padY) / scale)
        }
        func unletterboxRect(_ r: CGRect) -> CGRect {
            let p0 = unletterboxPoint(CGPoint(x: r.minX, y: r.minY))
            let p1 = unletterboxPoint(CGPoint(x: r.maxX, y: r.maxY))
            return CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
        }

        var poses: [DogPose] = []
        poses.reserveCapacity(16)

        for n in 0..<predictions {
            let score = Float(at(c: 4, n: n))
            guard score >= scoreThreshold else { continue }

            let bx = CGFloat(at(c: 0, n: n))
            let by = CGFloat(at(c: 1, n: n))
            let bw = CGFloat(at(c: 2, n: n))
            let bh = CGFloat(at(c: 3, n: n))
            let boxInModel = CGRect(x: bx - bw / 2, y: by - bh / 2, width: bw, height: bh)
            let boxInOriginal = unletterboxRect(boxInModel)

            var keypointsInOriginal: [(point: CGPoint, conf: Float)] = []
            keypointsInOriginal.reserveCapacity(24)
            for k in 0..<24 {
                let base = 5 + 3 * k
                let x = CGFloat(at(c: base, n: n))
                let y = CGFloat(at(c: base + 1, n: n))
                let conf = Float(at(c: base + 2, n: n))
                keypointsInOriginal.append((point: unletterboxPoint(CGPoint(x: x, y: y)), conf: conf))
            }

            let keypointsNormalized = keypointsInOriginal.map { kp in
                (point:
                    CGPoint(
                        x: (kp.point.x / origW),
                        y: (kp.point.y / origH)
                    ),
                 conf: kp.conf
                )
            }

            poses.append(
                DogPose(
                    score: score,
                    boxInOriginalPixels: boxInOriginal,
                    keypointsInOriginalPixels: keypointsInOriginal,
                    keypointsNormalized: keypointsNormalized
                )
            )
        }

        return poses
    }

    private func nonMaxSuppression(_ poses: [DogPose], iouThreshold: CGFloat) -> [DogPose] {
        let sorted = poses.sorted { $0.score > $1.score }
        var selected: [DogPose] = []
        selected.reserveCapacity(sorted.count)

        for candidate in sorted {
            var shouldKeep = true
            for kept in selected {
                if iou(candidate.boxInOriginalPixels, kept.boxInOriginalPixels) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }
            if shouldKeep {
                selected.append(candidate)
            }
        }

        return selected
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }

        return intersectionArea / unionArea
    }
}

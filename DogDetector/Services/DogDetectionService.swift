//
//  DogDetector.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import CoreML
import Vision

final class DogDetectionService {
    enum DogDetectionError: Error {
        case requestAlreadyRunning
        case noFeatureValueObservation
    }

    private var request: VNRequest!
    private var inFlightContinuation: CheckedContinuation<[DogPose], Error>?
    private var pendingOriginalSize: CGSize = .zero
    private let modelInputSize = CGSize(width: 640, height: 640)
    
    var isProcessing: Bool = false
    
    init() {
        setupCoreML()
    }
    
    private func setupCoreML() {
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .cpuAndNeuralEngine
        guard let model = try? VNCoreMLModel(for: dog_pose_model(configuration: modelConfig).model) else {
            fatalError("Failed to load CoreML model")
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            self?.processPredictions(for: request, error: error)
        }
        request.imageCropAndScaleOption = .scaleFit
        self.request = request
    }
    
    public func detectBreed(for image: CGImage) async throws-> [DetectionResult] {
        var detectionResults: [DetectionResult] = []
        let poses = try await runDetection(cgImage: image)
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
    
    private func runDetection(cgImage: CGImage) async throws -> [DogPose] {
        if isProcessing { throw DogDetectionError.requestAlreadyRunning }
        isProcessing = true
        pendingOriginalSize = CGSize(width: cgImage.width, height: cgImage.height)

        return try await withCheckedThrowingContinuation { continuation in
            inFlightContinuation = continuation
            do {
                try performRequest(cgImage: cgImage)
            } catch {
                isProcessing = false
                inFlightContinuation?.resume(throwing: error)
                inFlightContinuation = nil
            }
        }
    }

    private func performRequest(cgImage: CGImage) throws {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
    }
    
    private func processPredictions(for request: VNRequest, error: Error?){
        defer { isProcessing = false }

        if let error {
            print("VN error: \(error)")
            inFlightContinuation?.resume(throwing: error)
            inFlightContinuation = nil
            return
        }
        
        guard
            let observations = request.results as? [VNCoreMLFeatureValueObservation]
        else {
            inFlightContinuation?.resume(throwing: DogDetectionError.noFeatureValueObservation)
            inFlightContinuation = nil
            return
        }
        var poses: [DogPose] = []
        for obs in observations {
            let decodedPoses = decodeDogPoses(
                observation: obs,
                originalSize: pendingOriginalSize,
                modelInputSize: modelInputSize,
                scoreThreshold: 0.3
            )
            poses.append(contentsOf: decodedPoses)
        }
        inFlightContinuation?.resume(returning: poses)
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
        else {
            return []
        }

        let batch = arr.shape[0].intValue
        let dim1 = arr.shape[1].intValue
        let dim2 = arr.shape[2].intValue


        guard batch == 1, dim1 == 300, dim2 == 78 else {
            return []
        }

        let ptr = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
        let strideB = arr.strides[0].intValue
        let strideC = arr.strides[1].intValue
        let strideN = arr.strides[2].intValue

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

        // Current model layout: [1, detections, features] == [1,300,78].
        func atDetection(_ d: Int, _ f: Int) -> Float32 {
            let index = 0 * strideB + d * strideC + f * strideN
            return ptr[index]
        }

        for d in 0..<dim1 {
            let score = Float(atDetection(d, 4))
            guard score >= scoreThreshold else { continue }

            let x1 = CGFloat(atDetection(d, 0))
            let y1 = CGFloat(atDetection(d, 1))
            let x2 = CGFloat(atDetection(d, 2))
            let y2 = CGFloat(atDetection(d, 3))
            let boxInModel = CGRect(
                x: x1,
                y: y1,
                width: max(0, x2 - x1),
                height: max(0, y2 - y1)
            )
            let boxInOriginal = unletterboxRect(boxInModel)

            var keypointsInOriginal: [(point: CGPoint, conf: Float)] = []
            keypointsInOriginal.reserveCapacity(24)
            for k in 0..<24 {
                let base = 6 + 3 * k
                let x = CGFloat(atDetection(d, base))
                let y = CGFloat(atDetection(d, base + 1))
                let conf = Float(atDetection(d, base + 2))
                keypointsInOriginal.append((point: unletterboxPoint(CGPoint(x: x, y: y)), conf: conf))
            }

            let keypointsNormalized = keypointsInOriginal.map { kp in
                (
                    point: CGPoint(x: kp.point.x / origW, y: kp.point.y / origH),
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
}

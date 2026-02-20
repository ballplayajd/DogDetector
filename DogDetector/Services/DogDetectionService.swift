//
//  DogDetector.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import CoreML
import Vision
import ImageIO

actor DogDetectionService {
    enum DogDetectionError: Error {
        case requestAlreadyRunning
        case noFeatureValueObservation
    }

    private var isProcessing = false

    private var request: CoreMLRequest
    private let modelInputSize = CGSize(width: 640, height: 640)
    private let maxRetryCount = 3

    @MainActor
    init() {
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .cpuAndNeuralEngine

        let mlModel: MLModel
        do {
            mlModel = try dog_pose_model(configuration: modelConfig).model
        } catch {
            fatalError("Failed to load CoreML model: \(error)")
        }

        let container: CoreMLModelContainer
        do {
            container = try CoreMLModelContainer(model: mlModel, featureProvider: nil)
        } catch {
            fatalError("Failed to create CoreMLModelContainer: \(error)")
        }

        var req = CoreMLRequest(model: container)
        req.cropAndScaleAction = .scaleToFit
        self.request = req
    }

    func detectBreed(
        for image: CGImage,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> [DetectionResult] {
        var attempt = 0
        while true {
            do {
                return try await detectBreedOnce(for: image, orientation: orientation)
            } catch DogDetectionError.requestAlreadyRunning {
                attempt += 1
                if attempt > maxRetryCount { throw DogDetectionError.requestAlreadyRunning }
                try await Task.sleep(nanoseconds: UInt64(100_000_000 * attempt))
            }
        }
    }

    private func detectBreedOnce(
        for image: CGImage,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> [DetectionResult] {
        guard !isProcessing else { throw DogDetectionError.requestAlreadyRunning }
        isProcessing = true
        defer { isProcessing = false }

        let originalSize = CGSize(width: image.width, height: image.height)

        // CoreMLRequest returns observations from the model run
        let observations: [CoreMLFeatureValueObservation]
        do {
            observations = try await request.perform(on: image, orientation: orientation) as! [CoreMLFeatureValueObservation]
        } catch {
            throw error
        }

        var poses: [DogPose] = []
        poses.reserveCapacity(16)

        for obs in observations {
            poses.append(
                contentsOf: decodeDogPoses(
                    observation: obs,
                    originalSize: originalSize,
                    modelInputSize: modelInputSize,
                    scoreThreshold: 0.3
                )
            )
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        return poses.map { pose in
            let normalizedBox = CGRect(
                x: pose.boxInOriginalPixels.minX / width,
                y: pose.boxInOriginalPixels.minY / height,
                width: pose.boxInOriginalPixels.width / width,
                height: pose.boxInOriginalPixels.height / height
            )
            return DetectionResult(
                boxes: normalizedBox,
                keypoints: pose.keypointsNormalized
            )
        }
    }


    private func decodeDogPoses(
        observation: CoreMLFeatureValueObservation,
        originalSize: CGSize,
        modelInputSize: CGSize,
        scoreThreshold: Float
    ) -> [DogPose] {
        guard let shaped = observation.featureValue.shapedArrayValue(of: Float32.self),
              shaped.shape.count == 3
        else {
            return []
        }

        let batch = shaped.shape[0]
        let dim1 = shaped.shape[1]
        let dim2 = shaped.shape[2]

        guard batch == 1, dim1 == 300, dim2 == 78 else {
            return []
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

        shaped.withUnsafeShapedBufferPointer { ptr, _, strides in
            func atDetection(_ d: Int, _ f: Int) -> Float32 {
                let index = d * strides[1] + f * strides[2]
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
                    (point: CGPoint(x: kp.point.x / origW, y: kp.point.y / origH), conf: kp.conf)
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
        }

        return poses
    }
}

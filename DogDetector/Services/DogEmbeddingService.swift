import Foundation
import CoreML
import Vision

class DogEmbeddingService {
    enum DogEmbeddingError: Error {
        case requestAlreadyRunning
        case noEmbeddingFound
        case unsupportedOutputFeature
    }

    private var isProcessing = false
    private let request: Requestable
    private let maxRetryCount = 3

    init(request: Requestable? = nil) {
        if let request {
            self.request = request
            return
        }

        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .cpuAndNeuralEngine

        let mlModel: MLModel
        do {
            mlModel = try clip_vision_encoder(configuration: modelConfig).model
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
        self.request = RequestWrapper(request: req)
    }

    func predict(
        for image: CGImage,
        orientation: CGImagePropertyOrientation? = nil,
        outputFeatureName: String = "image_embeds"
    ) async throws -> [Float] {
        var attempt = 0
        while true {
            do {
                return try await predictOnce(
                    for: image,
                    orientation: orientation,
                    outputFeatureName: outputFeatureName
                )
            } catch DogEmbeddingError.requestAlreadyRunning {
                attempt += 1
                if attempt > maxRetryCount { throw DogEmbeddingError.requestAlreadyRunning }
                try await Task.sleep(nanoseconds: UInt64(100_000_000 * attempt))
            }
        }
    }

    private func predictOnce(
        for image: CGImage,
        orientation: CGImagePropertyOrientation? = nil,
        outputFeatureName: String
    ) async throws -> [Float] {
        //guard !isProcessing else { throw DogEmbeddingError.requestAlreadyRunning }
        //isProcessing = true
       // defer { isProcessing = false }

        let observations = try await request.perform(image: image, orientation: orientation)
        guard let observation = observations.first else {
            throw DogEmbeddingError.noEmbeddingFound
        }
        guard observation.featureName == outputFeatureName || observations.count == 1 else {
            throw DogEmbeddingError.noEmbeddingFound
        }

        return try decodeVector(from: observation.featureValue)
    }

    private func decodeVector(from value: MLSendableFeatureValue) throws -> [Float] {
        if let shaped = value.shapedArrayValue(of: Float16.self) {
            return shaped.scalars.map(Float.init)
        }
        throw DogEmbeddingError.unsupportedOutputFeature
    }
}

//
//  DetectionSmoother.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//
import Foundation
import QuartzCore

class DetectionOneEuroSmoother {
    private var filters: [String: OneEuroFilter1D] = [:]

    func filter(_ detections: [DetectionResult]) -> [DetectionResult] {
        let t = CACurrentMediaTime()
        var activeKeys = Set<String>()

        let smoothed = detections.enumerated().map { detectionIndex, detection in
            let boxPrefix = "d\(detectionIndex).box"
            let x = smoothedValue(detection.boxes.origin.x, key: "\(boxPrefix).x", t: t, activeKeys: &activeKeys)
            let y = smoothedValue(detection.boxes.origin.y, key: "\(boxPrefix).y", t: t, activeKeys: &activeKeys)
            let w = smoothedValue(detection.boxes.size.width, key: "\(boxPrefix).w", t: t, activeKeys: &activeKeys)
            let h = smoothedValue(detection.boxes.size.height, key: "\(boxPrefix).h", t: t, activeKeys: &activeKeys)

            let smoothedKeypoints = detection.keypoints.enumerated().map { keypointIndex, keypoint in
                let keypointPrefix = "d\(detectionIndex).k\(keypointIndex)"
                let kx = smoothedValue(keypoint.point.x, key: "\(keypointPrefix).x", t: t, activeKeys: &activeKeys)
                let ky = smoothedValue(keypoint.point.y, key: "\(keypointPrefix).y", t: t, activeKeys: &activeKeys)
                return (point: CGPoint(x: kx, y: ky), conf: keypoint.conf)
            }

            return DetectionResult(
                boxes: CGRect(x: x, y: y, width: w, height: h),
                keypoints: smoothedKeypoints
            )
        }
        filters = filters.filter { activeKeys.contains($0.key) }
        return smoothed
    }

    private func smoothedValue(_ value: CGFloat, key: String, t: CFTimeInterval, activeKeys: inout Set<String>) -> CGFloat {
        activeKeys.insert(key)
        let filter = filters[key] ?? OneEuroFilter1D()
        filters[key] = filter
        return filter.filter(value, timestamp: t)
    }
}

private final class OneEuroFilter1D {
    private let minCutoff: CGFloat
    private let beta: CGFloat
    private let dCutoff: CGFloat

    private var previousValue: CGFloat?
    private var previousDerivative: CGFloat = 0
    private var previousTimestamp: CFTimeInterval?

    init(minCutoff: CGFloat = 1.0, beta: CGFloat = 10.0, dCutoff: CGFloat = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    func filter(_ value: CGFloat, timestamp: CFTimeInterval) -> CGFloat {
        guard let oldValue = previousValue, let oldTimestamp = previousTimestamp else {
            previousValue = value
            previousTimestamp = timestamp
            return value
        }

        let dt = max(CGFloat(timestamp - oldTimestamp), 1.0 / 120.0)
        let derivative = (value - oldValue) / dt
        let derivativeAlpha = alpha(cutoff: dCutoff, dt: dt)
        let derivativeHat = lowpass(value: derivative, previous: previousDerivative, alpha: derivativeAlpha)
        let cutoff = minCutoff + beta * abs(derivativeHat)
        let valueAlpha = alpha(cutoff: cutoff, dt: dt)
        let valueHat = lowpass(value: value, previous: oldValue, alpha: valueAlpha)

        previousDerivative = derivativeHat
        previousValue = valueHat
        previousTimestamp = timestamp
        return valueHat
    }

    private func alpha(cutoff: CGFloat, dt: CGFloat) -> CGFloat {
        let tau = 1 / (2 * .pi * max(cutoff, 0.001))
        return 1 / (1 + tau / dt)
    }

    private func lowpass(value: CGFloat, previous: CGFloat, alpha: CGFloat) -> CGFloat {
        alpha * value + (1 - alpha) * previous
    }
}

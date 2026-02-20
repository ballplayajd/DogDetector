//
//  Detectionresult.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//
import Foundation

struct DetectionResult {
    let boxes: CGRect
    let keypoints: [(point: CGPoint, conf: Float)]
}

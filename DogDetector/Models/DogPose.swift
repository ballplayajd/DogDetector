//
//  DogPose.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import Foundation

struct DogPose {
    let score: Float
    let boxInOriginalPixels: CGRect
    let keypointsInOriginalPixels: [(point: CGPoint, conf: Float)]
    let keypointsNormalized: [(point: CGPoint, conf: Float)]
}

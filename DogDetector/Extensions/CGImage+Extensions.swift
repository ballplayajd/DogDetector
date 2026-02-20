//
//  CGImage+Extensions.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//

import Foundation
import Metal
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreImage
import CoreImage.CIFilterBuiltins

private enum SharedCIContext {
    static let instance = CIContext()
}

extension CGImage {
    private static let ciContext = CIContext()

    func lensHighlightRegions(
        regions: [CGRect],
        outsideBlurRadius: Float = 12
    ) -> CGImage? {
        guard !regions.isEmpty else { return self }

        let base = CIImage(cgImage: self)
        let extent = base.extent
        let W = CGFloat(self.width)
        let H = CGFloat(self.height)

        func toPixelRect(_ r: CGRect) -> CGRect {
            let x = r.origin.x * W
            let y: CGFloat
           
            y = (1 - r.origin.y - r.size.height) * H
            
            return CGRect(x: x, y: y, width: r.size.width * W, height: r.size.height * H)
        }

        // Build a full-extent mask: black everywhere, white in regions
        var mask = CIImage(color: .black).cropped(to: extent)
        for r in regions {
            let pr = toPixelRect(r).integral
            let whiteRect = CIImage(color: .white).cropped(to: pr)
            mask = whiteRect.composited(over: mask) // union
        }

        // Outside: blur only
        let outsideBlur = CIFilter.gaussianBlur()
        outsideBlur.inputImage = base.clampedToExtent()
        outsideBlur.radius = outsideBlurRadius
        guard let outside = outsideBlur.outputImage?.cropped(to: extent) else { return nil }

        // Composite: white mask = inside (original), black = outside (blurred)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = base
        blend.backgroundImage = outside
        blend.maskImage = mask

        guard let out = blend.outputImage?.cropped(to: extent),
              let cgOut = Self.ciContext.createCGImage(out, from: extent) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgOut
        }

        context.draw(cgOut, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(0.01 * W)

        for region in regions {
            let rect = toPixelRect(region).integral
            context.stroke(rect)
        }

        return context.makeImage() ?? cgOut
    }

    func drawingNormalizedKeypoints(
        _ keypoints: [(point: CGPoint, conf: Float)]?,
        minConfidence: Float = 0.25,
        radius: CGFloat = 4,
        color: CGColor = CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1)
    ) -> CGImage? {
        guard let keypoints else { return self }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color)

        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        
        for keypoint in keypoints where keypoint.conf >= minConfidence {
            let nx = min(max(keypoint.point.x, 0), 1)
            let ny = min(max(keypoint.point.y, 0), 1)

            let px = nx * imageWidth
            let py: CGFloat
            py = (1 - ny) * imageHeight
        
            let dotRect = CGRect(
                x: px - radius,
                y: py - radius,
                width: 0.02 * imageWidth,
                height: 0.02 *  imageWidth
            )
            context.fillEllipse(in: dotRect)
        }

        return context.makeImage()
    }
}


extension CIImage {
    
    var cgImage: CGImage? {
        guard let cgImage = SharedCIContext.instance.createCGImage(self, from: self.extent) else {
            return nil
        }
        
        return cgImage
    }
    var rotatedCGImage: CGImage? {
        let transformed = self.transformed(by: CGAffineTransform(rotationAngle: -.pi/2)
            .translatedBy(
                    x: -self.extent.height,
                    y: 0
            ))
                
        return SharedCIContext.instance.createCGImage(transformed, from: transformed.extent)
    }
}


extension CMSampleBuffer {
    
    var cgImage: CGImage? {
        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(self)
        
        guard let imagePixelBuffer = pixelBuffer else {
            return nil
        }
        
        return CIImage(cvPixelBuffer: imagePixelBuffer).rotatedCGImage
    }
    
}

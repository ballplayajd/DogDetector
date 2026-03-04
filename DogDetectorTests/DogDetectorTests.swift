import Testing
import CoreML
import Vision
@testable import DogDetector

struct DogDetectorTests {

    @Test func testDecodeDogPoses() throws {
        let service = DogDetectionService()

        let array = try MLMultiArray(shape: [1, 300, 78], dataType: .float32)
        for i in 0..<(300 * 78) { array[i] = 0 }

        func set(_ d: Int, _ f: Int, _ v: Float) {
            array[d * 78 + f] = NSNumber(value: v)
        }

        // Detection 0: score 0.9, box (100,150)→(300,400), kp0=(110,160), kp1=(120,170)
        set(0, 0, 100); set(0, 1, 150); set(0, 2, 300); set(0, 3, 400)
        set(0, 4, 0.9)
        set(0, 6, 110); set(0, 7, 160); set(0, 8, 0.8)
        set(0, 9, 120); set(0, 10, 170); set(0, 11, 0.7)

        // Detection 1: score 0.5, box (50,60)→(200,250), kp0=(55,65)
        set(1, 0, 50); set(1, 1, 60); set(1, 2, 200); set(1, 3, 250)
        set(1, 4, 0.5)
        set(1, 6, 55); set(1, 7, 65); set(1, 8, 0.6)

        // Detection 2: below threshold (0.1 < 0.3)
        set(2, 4, 0.1)

        let vnObs = StubVNObservation(MLFeatureValue(multiArray: array))
        let observation = CoreMLFeatureValueObservation(vnObs)

        // originalSize == modelInputSize → unletterbox is identity
        let poses = service.decodeDogPoses(
            observation: observation,
            originalSize: CGSize(width: 640, height: 640),
            modelInputSize: CGSize(width: 640, height: 640),
            scoreThreshold: 0.3
        )

        #expect(poses.count == 2)

        #expect(poses[0].score == 0.9)
        #expect(poses[0].boxInOriginalPixels == CGRect(x: 100, y: 150, width: 200, height: 250))
        #expect(poses[0].keypointsInOriginalPixels.count == 24)
        #expect(poses[0].keypointsInOriginalPixels[0].point == CGPoint(x: 110, y: 160))
        #expect(poses[0].keypointsInOriginalPixels[0].conf == 0.8)
        #expect(poses[0].keypointsInOriginalPixels[1].point == CGPoint(x: 120, y: 170))
        #expect(poses[0].keypointsInOriginalPixels[1].conf == 0.7)
        #expect(poses[0].keypointsNormalized[0].point.x == 110.0 / 640.0)
        #expect(poses[0].keypointsNormalized[0].point.y == 160.0 / 640.0)

        #expect(poses[1].score == 0.5)
        #expect(poses[1].boxInOriginalPixels == CGRect(x: 50, y: 60, width: 150, height: 190))
        #expect(poses[1].keypointsInOriginalPixels[0].point == CGPoint(x: 55, y: 65))
        #expect(poses[1].keypointsInOriginalPixels[0].conf == 0.6)
    }
}

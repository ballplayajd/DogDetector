# DogDetector

DogDetector is an iOS SwiftUI app that fetches dog images, runs pose detection, and renders highlighted detections with keypoints.
Demo Video here: https://www.youtube.com/shorts/zKRpOKIQS7Q

## Platform Support

- iOS 18+

## Model

- Uses a YOLO pose estimation model trained for dogs (`dog_pose_model.mlmodel`).
- Dog-pose setup follows the Ultralytics Dog-Pose dataset conventions (24 keypoints, dog class).
- Reference: https://docs.ultralytics.com/datasets/pose/dog-pose/#introduction

## Core Tech Stack

- SwiftUI for UI
- Apple Vision (`CoreMLRequest`) for model inference
- CoreML for running the YOLO pose model
- CoreImage/CoreGraphics (`CGImage`) for rendering overlays and effects

## Detection Pipeline

1. Image enters the system as a `CGImage`.
2. `DogDetectionService` runs Vision + CoreML with `.scaleFit`.
3. Model output is decoded from tensor shape `[1, 300, 78]`:
   - per-detection box + score + keypoints
4. Coordinates are mapped from model-input space back to original image space.
5. Results are converted to normalized coordinates for drawing.

## Performance Design

- Image transforms are done in `CGImage` space to reduce conversion overhead.
- Rendering operations (`lensHighlightRegions`, keypoint drawing) use CoreImage/CoreGraphics directly.
- Shared `CIContext` is reused for frame/image conversions.
- `DogViewModel` uses `NSCache` (count + memory cost limits) to avoid unbounded image memory growth.

## UI Modes

### Scroll Feed Mode

- Fetches random dog images from Dog API.
- Toggle to enable/disable detection overlays.
- Lazy list paging to load more images as user scrolls.

### Live Camera Mode

- Full-screen camera preview for real-time model testing.
- Runs detection per frame through `DogDetectionService`.
- Applies a One Euro filter to smooth box/keypoint jitter frame-to-frame.
- Useful for validating model behavior under live framerate constraints.

## Networking and Services Layer

The app uses a small service-oriented networking layer:

- `Endpoint` protocol defines path/method/query/body contract.
- `NetworkClient` builds and executes typed async requests and decodes JSON generically.
- `DogService` owns Dog API-specific endpoint(s) and maps response payloads to app models.
- `DogDetectionService` is dedicated to inference and decode logic, separated from UI/view model code.

This separation keeps API access, ML inference, and UI state management independent and easier to maintain.

## Error Handling

- Detection path uses throwing async flow.
- UI surfaces service/network failures through `DogViewModel.errorMessage` and a SwiftUI alert.


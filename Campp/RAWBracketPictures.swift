

import Foundation
import AVFoundation
import UIKit
import Photos

var bracketCount = 1

func getRAWLowISOLongExposureSettings(capturePhotoOutput: AVCapturePhotoOutput,
                            currentAutoShutterDuration: CMTime,
                            currentAutoISO: Float,
                            currentLuminance: Float,
                            currentAccelerationScale: Double,
                            deviceMaxShutterDuration: CMTime,
                            deviceISORange: (Float, Float)) -> AVCapturePhotoSettings {
    
//    let isoCompensation = Float(maxDuration.seconds) / Float(duration.seconds)
//
//    let isoNew = min(isoRange.1, max(isoRange.0, iso/isoCompensation))
//    var newIso = iso / 2
//     Specify a 3-shot bracket, where exposure compensation varies between each shot.
//    let makeShutterSettings = AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings
//    if iso > isoRange.1 {
//        newIso = isoRange.1
//    }
//    if iso < isoRange.0 {
//        newIso = isoRange.0
//    }
    let newIso = deviceISORange.0*2 //  最低感光度
    print("Selected ISO \(newIso)")
//    var bracketedStillImageSettings = Array<AVCaptureManualExposureBracketedStillImageSettings>()
//    for _ in 0..<bracketCount {
//    bracketedStillImageSettings.append(makeShutterSettings(currentAutoShutterDuration, newIso))
//    }
    let rawFormat = capturePhotoOutput.availableRawPhotoPixelFormatTypes.first!
//    print("rawFormat: \(rawFormat)")
    let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: nil)//, bracketedSettings: bracketedStillImageSettings) //, processedFormat: [AVVideoCodecKey : AVVideoCodecType.hevc])
    
    if !settings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
        settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: settings.__availablePreviewPhotoPixelFormatTypes.first!]
    }
//    settings.isLensStabilizationEnabled = true
//    settings.isHighResolutionPhotoEnabled = true
    return settings
}

func getRAWQuickSettings(capturePhotoOutput: AVCapturePhotoOutput, iso: Float, shutterDuration: CMTime, withProcessedFormat: Bool) -> AVCapturePhotoSettings {
    let rawFormat = capturePhotoOutput.availableRawPhotoPixelFormatTypes.first!
    let makeShutterSettings = AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings
    var bracketedStillImageSettings = Array<AVCaptureManualExposureBracketedStillImageSettings>()
//    for _ in 0..<bracketCount {}
    bracketedStillImageSettings.append(makeShutterSettings(shutterDuration, iso))
    let settings = AVCapturePhotoBracketSettings(rawPixelFormatType: rawFormat,
                                                 processedFormat: withProcessedFormat ? [AVVideoCodecKey: AVVideoCodecType.hevc] : nil,
                                                 bracketedSettings: bracketedStillImageSettings)
//    settings.previewPhotoFormat = [AVVideoCodecKey: AVVideoCodecType.jpeg]
    if !settings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
        settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: settings.__availablePreviewPhotoPixelFormatTypes.first!,
                                       kCVPixelBufferWidthKey as String: 304,
                                       kCVPixelBufferHeightKey as String: 228]
    }
    return settings
}

func getProcessedQuickSettings(myCapturePhotoOutput: AVCapturePhotoOutput,
                            duration: CMTime,
                            iso: Float) -> AVCapturePhotoSettings {
    let settings =  AVCapturePhotoSettings(rawPixelFormatType: 0, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
    
    if !settings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
        settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: settings.__availablePreviewPhotoPixelFormatTypes.first!]
    }
    settings.isHighResolutionPhotoEnabled = true
    return settings
}

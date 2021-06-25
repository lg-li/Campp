import Foundation
import AVFoundation
import UIKit
import Photos
import Darwin
import Accelerate

class QuickProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    
    //    var rawImageFileURL: Array<URL>?
    var compressedFileData: Array<Data?> = Array()
    private var complete = false
    static var rawPhotoData: Array<Data> = Array()
    static var compiledPhoto: AVCapturePhoto?
    
    var focusValue : Float
    var isoValue : Int
    var shutterDuration: CMTime
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let logger: (StatusUpdate, Float?) -> Void
    
    private let completionHandler: (QuickProcessor) -> Void
    
    private let photoProcessingHandler: (Bool) -> Void
    
    private var maxPhotoProcessingTime: CMTime?
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (QuickProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void,
         logger: @escaping (StatusUpdate, Float?) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.logger = logger
        
        self.focusValue = 0.5
        self.isoValue = 200
        self.shutterDuration = CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000)
    }
    
    
    
    // Hold on to the separately delivered RAW file and compressed photo data until capture is finished.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { print("Error capturing photo: \(error!)"); return }
        
        // Mark That We're Processing a picture
        if (photo.isRawPhoto) {
            print("appending click")
            QuickProcessor.rawPhotoData.append(photo.fileDataRepresentation()!)
        }
        
        if (photo.photoCount == photo.resolvedSettings.expectedPhotoCount) {
            self.complete = true
        }
    }
    
    public static func clearForRestart() {
        QuickProcessor.rawPhotoData.removeAll()
        QuickProcessor.compiledPhoto = nil
    }
    
    private func didFinish() {
        if (complete) {
            self.completionHandler(self)
            self.logger(.BurstFinished, nil)
            QuickProcessor.clearForRestart()
        }
    }
    
    // After both RAW and compressed versions are delivered, add them to the Photos Library.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }
        
        guard !QuickProcessor.rawPhotoData.isEmpty else {
            print("No quick shot data, finishing early")
            didFinish()
            return
        }
        
        for i in 0..<QuickProcessor.rawPhotoData.count {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        options.uniformTypeIdentifier = self.requestedPhotoSettings.rawFileType?.rawValue
                        creationRequest.addResource(with: .photo,
                                                    data: QuickProcessor.rawPhotoData[i],
                                                    options: options)
                    }, completionHandler: { _, error in
                        if let error = error {
                            print("Error occurred while saving photo to photo library: \(error)")
                            return
                        }
                        print("Saved Quick Shot \(i)")
                        if i == QuickProcessor.rawPhotoData.count-1 {
                            self.didFinish()
                        }
                    })
                }
            }
        }
    }
    
    func handlePhotoLibraryError(success: Bool, error: Error?) {
    }
    
    func makeUniqueTempFileURL(extension type: String) -> URL {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let uniqueFilename = ProcessInfo.processInfo.globallyUniqueString
        let urlNoExt = temporaryDirectoryURL.appendingPathComponent(uniqueFilename)
        let url = urlNoExt.appendingPathExtension(type)
        return url
    }
}


extension QuickProcessor {
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        logger(.BurstStarted, nil)
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }
        
        // Show a spinner if processing time exceeds one second.
        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            photoProcessingHandler(true)
        }
    }
}

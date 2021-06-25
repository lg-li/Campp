//
//  RAWCaptureProcessor.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/9.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import Photos
import VideoToolbox
import Vision

class HDRCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    var compressedFileData: Data?
    
    static var hasHDRFinished: Bool = false;
    static var darkPhotoBurst = [AVCapturePhoto]();
    static var lightPhotoBurst = [AVCapturePhoto]();
    static var convertedDepthMap: Array<Float>?;
    
    static var bufferWidth: Int32 = 0;
    static var bufferHeight: Int32 = 0;
    static var bytesPerRow: Int32 = 0;
    static var depthMapWidth: Int32 = 0;
    static var depthMapHeight: Int32 = 0;
    static var whiteLevel: Int32 = 0;
    static var blackLevel: Int32 = 0;
    static var marginLeft: Int32 = 0;
    static var marginTop: Int32 = 0;
    
    static var whiteBalanceR: Float = 0.0;
    static var whiteBalanceG: Float = 0.0;
    static var whiteBalanceB: Float = 0.0;
    
    //    var focusValue : Float
    //    var isoValue : Int
    //    var shutterDuration: CMTime
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let logger: (StatusUpdate, Float?) -> Void
    
    private let completionHandler: (HDRCaptureDelegate) -> Void
    
    private let photoProcessingHandler: (Bool) -> Void
    
    private var maxPhotoProcessingTime: CMTime?
    
    private var refresh: (Bool) = true
    
    public static var currentReceivedPhotoCount = AtomicInteger(0)
    public static let totalPhotoCountExpceted = AtomicInteger(1)
    
    private static var processor: UnsafeMutableRawPointer? = nil;
    
    public static var depthPredictionCompletionExternalHandler: ((MLMultiArray) -> Void)?
    
    public enum ImageType {
        case DARK
        case LIGHT
    }
    
    private var imageType: ImageType
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (HDRCaptureDelegate) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void,
         logger: @escaping (StatusUpdate, Float?) -> Void,
         imageType: ImageType) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.logger = logger
        self.imageType = imageType
        //        self.focusValue = 0.5
        //        self.isoValue = 200
        //        self.shutterDuration = CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000)
    }
    
    static func setWhiteBalanceGains(r: Float, g: Float, b: Float) {
        HDRCaptureDelegate.whiteBalanceR = r;
        HDRCaptureDelegate.whiteBalanceG = g;
        HDRCaptureDelegate.whiteBalanceB = b;
    }
    
    // 拍摄文件回调
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            logger(.Error, nil);
            print("Error capturing photo: \(error!)"); return
                print(error.debugDescription)
        }
        
        if (photo.isRawPhoto) {
            print("Raw photo comes: \(HDRCaptureDelegate.currentReceivedPhotoCount.value)")
            HDRCaptureDelegate.darkPhotoBurst.append(photo)
            // 仅取第一张图片作为深度预测的样本
//            if HDRCaptureDelegate.currentReceivedPhotoCount.value == 0 {
//                DepthPredictor.predict(with: photo.previewPixelBuffer!, onComplete: depthPredictionDidComplete)
//            }
            HDRCaptureDelegate.currentReceivedPhotoCount.value += 1
        } else {
            print("Compressed photo comes: \(HDRCaptureDelegate.currentReceivedPhotoCount.value)")
            if (compressedFileData == nil) {
                compressedFileData = photo.fileDataRepresentation()!
            }
        }
        
        if (self.refresh) {
            HDRCaptureDelegate.hasHDRFinished = false
            self.refresh = false
        }
        
        // 若收到的帧数已经达到了目标曝光帧，则开始处理多帧合成操作
        if (photo.photoCount == photo.resolvedSettings.expectedPhotoCount) {
            if (HDRCaptureDelegate.currentReceivedPhotoCount.value == HDRCaptureDelegate.totalPhotoCountExpceted.value) {
                self.logger(.Launch, nil)
                print("曝光完成，合成 HDR 图像...")
                processHDR()
                HDRCaptureDelegate.hasHDRFinished = true
                self.refresh = true
                self.photoProcessingHandler(false)
            }
        }
    }
    
    private func didFinish() {
        self.logger(.CaptureFinished, nil)
        self.completionHandler(self)
    }
    
    // 在 HDR 处理完成后保存曝光帧RAW文件到相册
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error finishing capturing photo: \(error)")
            logger(.Error, nil)
            return
        }
        
        if !HDRCaptureDelegate.hasHDRFinished {
            print("HDR处理暂未完成，不执行保存操作。")
            didFinish()
            return
        }
        
        saveBurstStack(burstStack: HDRCaptureDelegate.darkPhotoBurst)
//        saveBurstStack(burstStack: RAWCaptureProcessor.lightPhotoBurst)
    }
    
    func saveBurstStack(burstStack: [AVCapturePhoto]) {
        for i in 0..<burstStack.count {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    self.didFinish()
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.rawFileType?.rawValue
                    creationRequest.addResource(with: .photo,
                                                data: burstStack[i].fileDataRepresentation()!,
                                                options: options)
                    
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving raw photo to photo library: \(error)")
                        return
                    }
                    print("Saved RAW Shot \(i+1)")
                    if i == burstStack.count-1 {
                        // 已完成所有保存工作
                        self.didFinish()
                        self.logger(.Saved, nil)
                    }
                })
                
            }
        }
    }
}

extension HDRCaptureDelegate {
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        logger(.CaptureStarted, nil)
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        print("WillCapturePhoto")
        willCapturePhotoAnimation()
        print("willCapturePhotoAnimation")
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

//  景深预测数据回调
extension HDRCaptureDelegate {
    public func depthPredictionDidComplete(heatmap: MLMultiArray) {
        guard HDRCaptureDelegate.depthPredictionCompletionExternalHandler != nil else {
            print("No depthPredictionCompletionExternalHandler defined.")
            return
        }
        
        let heatmap_w = heatmap.shape[1].intValue
        let heatmap_h = heatmap.shape[2].intValue
        
        print(heatmap.dataType.rawValue)
        // 提交深度数据到 Halide
        
        var convertedHeatmap: Array<Float32> = Array(repeating: 0.0, count: heatmap_w*heatmap_h)
        
        var minimumValue: Float32 = Float32.greatestFiniteMagnitude
        var maximumValue: Float32 = -Float32.greatestFiniteMagnitude
        
        for index in 0..<heatmap_w*heatmap_h {
            let confidence = heatmap[index].floatValue
            guard confidence > 0 else { continue }
            convertedHeatmap[index] = confidence
            if minimumValue > confidence {
                minimumValue = confidence
            }
            if maximumValue < confidence {
                maximumValue = confidence
            }
        }
        //  归一化
        let minmaxGap = maximumValue - minimumValue
        for index in 0..<heatmap_w*heatmap_h {
            convertedHeatmap[index] = (convertedHeatmap[index] - minimumValue) / minmaxGap
        }
        
        
        HDRCaptureDelegate.convertedDepthMap = convertedHeatmap
        HDRCaptureDelegate.depthMapWidth = Int32(heatmap_w)
        HDRCaptureDelegate.depthMapHeight = Int32(heatmap_h)
        // 提交深度数据到外部调用（）
        HDRCaptureDelegate.depthPredictionCompletionExternalHandler!(heatmap)
    }
}

extension HDRCaptureDelegate {
    
    private func unlockAllBuffersAddresses() {
        unlockBuffersAddressesInBurstStack(burstStack: HDRCaptureDelegate.darkPhotoBurst)
        unlockBuffersAddressesInBurstStack(burstStack: HDRCaptureDelegate.lightPhotoBurst)
    }
    
    private func unlockBuffersAddressesInBurstStack(burstStack: [AVCapturePhoto]) {
        for (index, currentPhoto) in burstStack.enumerated() {
            guard let currentPixelBuffer = currentPhoto.pixelBuffer else
            {print("NO PIXEL BUFF FOUND"); return;}
            print("Unlocking Address for Pic#" + String(index))
            CVPixelBufferUnlockBaseAddress(currentPixelBuffer, CVPixelBufferLockFlags.readOnly)
        }
    }
    
    @objc func save(image:UIImage, didFinishSavingWithError:NSError?,contextInfo:AnyObject) {
        if didFinishSavingWithError != nil {
            print("UIimg 保存失败")
        } else {
            print("UIimg 保存成功，现可删除processor引用")
            // 删除C++侧堆上processor引用
            wrapped_dispose_hdr_processor(HDRCaptureDelegate.processor)
        }
    }
    
    private func processHDR () {
        // Start timer
        let start = DispatchTime.now()
        var imageWidth = 0, imageHeight = 0;
        var metaData: [String : Any]? = nil;
        for (index, currentPhoto) in HDRCaptureDelegate.darkPhotoBurst.enumerated() {
            guard let currentPixelBuffer = currentPhoto.pixelBuffer else
            {print("NO PIXEL BUFF FOUND"); return;}
            CVPixelBufferLockBaseAddress(currentPixelBuffer, CVPixelBufferLockFlags.readOnly)
            
            if index == 0 {
                // 以首帧曝光帧获取宽高和标签数据等信息
                HDRCaptureDelegate.bufferWidth = Int32(CVPixelBufferGetWidth(currentPixelBuffer));
                HDRCaptureDelegate.bufferHeight = Int32(CVPixelBufferGetHeight(currentPixelBuffer));
                HDRCaptureDelegate.bytesPerRow = Int32(CVPixelBufferGetBytesPerRow(currentPixelBuffer));

                // DNG标签数据获取白平衡和margin等参数
                metaData = currentPhoto.metadata
                let metaDataDNG = currentPhoto.metadata["{DNG}"] as! [String : Any];
                print(currentPhoto.metadata)
                HDRCaptureDelegate.whiteLevel = metaDataDNG["WhiteLevel"] as! Int32;
                HDRCaptureDelegate.blackLevel = metaDataDNG["BlackLevel"] as! Int32;
                HDRCaptureDelegate.marginTop = (metaDataDNG["ActiveArea"] as! Array<Int32>)[0]
                HDRCaptureDelegate.marginLeft = (metaDataDNG["ActiveArea"] as! Array<Int32>)[1]
                // 真实图像大小
                imageWidth = Int(HDRCaptureDelegate.bufferWidth - HDRCaptureDelegate.marginLeft*2)
                imageHeight = Int(HDRCaptureDelegate.bufferHeight - HDRCaptureDelegate.marginTop*2)
                // 初始化processor饮用
                HDRCaptureDelegate.processor = wrapped_hdr_init(HDRCaptureDelegate.bufferWidth,
                                             HDRCaptureDelegate.bufferHeight,
                                             HDRCaptureDelegate.marginTop,
                                             HDRCaptureDelegate.marginLeft,
                                             HDRCaptureDelegate.blackLevel,
                                             HDRCaptureDelegate.whiteLevel,
                                             HDRCaptureDelegate.whiteBalanceR,
                                             HDRCaptureDelegate.whiteBalanceG,
                                             HDRCaptureDelegate.whiteBalanceB)
                
               /* 深度数据处理
                // 深度图转pixelbuffer
                var depthMapPixelBuffer: CVPixelBuffer? = nil;
                let ret = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, Int(HDRCaptureDelegate.depthMapWidth), Int(HDRCaptureDelegate.depthMapHeight),
                                                       kCVPixelFormatType_32AlphaGray, &(HDRCaptureDelegate.convertedDepthMap!), Int(HDRCaptureDelegate.depthMapWidth),
                                                       nil, nil, nil, &depthMapPixelBuffer);
                if ret != kCVReturnSuccess {
                    print("failed to load bytes to depthPixelBuffer!")
                }
                
                var depthMapCIImage = CIImage(cvPixelBuffer: depthMapPixelBuffer!)
                // resize depth map
                depthMapCIImage = depthMapCIImage.transformed(by: CGAffineTransform(
                        scaleX:CGFloat((imageWidth / Int(HDRCaptureDelegate.depthMapWidth))),
                        y: CGFloat((imageHeight / Int(HDRCaptureDelegate.depthMapHeight)))))
                
                // 将 depthmappixelbuffer 转为 CIImage 再转为 CGImage 再转为 UIImage 后保存到相册
//                let depthMapCGImage = CIContext().createCGImage(depthMapCIImage, from: depthMapCIImage.extent)
                let depthMapUIImage = UIImage(ciImage: depthMapCIImage)
                DispatchQueue.main.async {
                    UIImageWriteToSavedPhotosAlbum(depthMapUIImage, self, #selector(self.save(image:didFinishSavingWithError:contextInfo:)), nil)
                }
                
//                let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
//                var depthMapResizedPixelBuffer : CVPixelBuffer?
//                _ = CVPixelBufferCreate(kCFAllocatorDefault, Int(depthMapCIImage.extent.width), Int(depthMapCIImage.extent.height), kCVPixelFormatType_OneComponent8, attrs, &depthMapResizedPixelBuffer)

//                CIContext().render(depthMapCIImage, to: depthMapResizedPixelBuffer!)
////                let depthMapResizedPixelBuffer = UIImage.convertToBuffer(from: depthMapUIImage)!
//                let resizedWidth = CVPixelBufferGetWidth(depthMapResizedPixelBuffer!)
//                let resizedHeight = CVPixelBufferGetHeight(depthMapResizedPixelBuffer!)
//                CVPixelBufferLockBaseAddress(depthMapResizedPixelBuffer!, CVPixelBufferLockFlags.readOnly)
//                guard let depthMapResizedBaseAddress = CVPixelBufferGetBaseAddress(depthMapResizedPixelBuffer!) else {return}
//                let depthMapResizedPointer = depthMapResizedBaseAddress.assumingMemoryBound(to: Float.self)
//
                 
                wrapped_hdr_submit_depth_data(HDRCaptureDelegate.processor, &(HDRCaptureDelegate.convertedDepthMap!),
                                              Int32(HDRCaptureDelegate.depthMapWidth), Int32(HDRCaptureDelegate.depthMapHeight))*/
            }
            // bound 指针地址 （16-bit）
            guard let currentPicBaseAddress = CVPixelBufferGetBaseAddress(currentPixelBuffer) else {return}
            let currentBufferPointer = currentPicBaseAddress.assumingMemoryBound(to: UInt16.self)
            // 提交本曝光帧像素指针到 C++ 程序
            wrapped_hdr_submit_raw_data(HDRCaptureDelegate.processor, currentBufferPointer)
            print("Submitted Pic#" + String(index))
        }
        
        logger(.BurstStarted, nil)
        // HDR处理结果指针
        let processed_hdr_data = wrapped_hdr_process(HDRCaptureDelegate.processor)
        // 解锁所有曝光帧的内存地址
        unlockAllBuffersAddresses()
        // 通过字节数据构建 pixelbuffer
        var pixelBuffer: CVPixelBuffer? = nil;
        let ret = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, imageWidth, imageHeight,
                                               kCVPixelFormatType_24RGB, processed_hdr_data!, Int(imageWidth*3),
                                               nil, nil, nil, &pixelBuffer);
        if ret != kCVReturnSuccess {
            print("failed to load bytes to pixelBuffer!")
        }
        
        // 将 pixelbuffer 转为 CIImage 再转为CGImage 再转为 UIImage 后保存到相册
        let input = CIImage(cvPixelBuffer: pixelBuffer!, options: [CIImageOption.properties: metaData!])
        let cgImage = CIContext().createCGImage(input, from: input.extent)
        let outputToSave = UIImage(cgImage: cgImage!)
        print("ui image generated!")
        UIImageWriteToSavedPhotosAlbum(outputToSave, self, #selector(save(image:didFinishSavingWithError:contextInfo:)), nil)
        print("UIImageWriteToSavedPhotosAlbum called")
        let end = DispatchTime.now()
        logger(.BurstFinished, nil)
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        print("Processed HDR in \(timeInterval) seconds")
    }
    
    public static func clearForRestart() {
        // 重置各种参数
        HDRCaptureDelegate.bufferWidth = 0;
        HDRCaptureDelegate.bufferHeight = 0;
        HDRCaptureDelegate.depthMapWidth = 0;
        HDRCaptureDelegate.depthMapHeight = 0;
        HDRCaptureDelegate.whiteLevel = 0;
        HDRCaptureDelegate.blackLevel = 0;
        HDRCaptureDelegate.bytesPerRow = 0;
        HDRCaptureDelegate.currentReceivedPhotoCount.value = 0
        HDRCaptureDelegate.totalPhotoCountExpceted.value = 1
        HDRCaptureDelegate.marginTop = 0;
        HDRCaptureDelegate.marginLeft = 0;
        // 清空上次的曝光帧
        HDRCaptureDelegate.darkPhotoBurst.removeAll();
        HDRCaptureDelegate.lightPhotoBurst.removeAll();
    }
    
}

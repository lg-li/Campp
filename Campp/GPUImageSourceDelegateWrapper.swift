//
//  GPUImageWrappedCamera.swift
//  Campp
//
//  Created by Lingen Li on 2020/3/15.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import AVFoundation
import GPUImage2

public protocol CameraDelegate {
    func didCaptureBuffer(_ sampleBuffer: CMSampleBuffer)
}
public enum PhysicalCameraLocation {
    case backFacing
    case frontFacing
    
    // Documentation: "The front-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeLeft and the back-facing camera would always deliver buffers in AVCaptureVideoOrientationLandscapeRight."
    func imageOrientation() -> ImageOrientation {
        switch self {
        case .backFacing: return .portrait
        case .frontFacing: return .portrait
        }
    }
    
    func captureDevicePosition() -> AVCaptureDevice.Position {
        switch self {
        case .backFacing: return .back
        case .frontFacing: return .front
        }
    }
//    
//    func device() -> AVCaptureDevice? {
//        let devices = AVCaptureDevice.devices(for:AVMediaType.video)
//        for case let device in devices {
//            if (device.position == self.captureDevicePosition()) {
//                return device
//            }
//        }
//        
//        return AVCaptureDevice.default(for: AVMediaType.video)
//    }
}

public class GPUImageSourceDelegateWrapper: NSObject, ImageSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public var delegate: CameraDelegate?
    public var location: PhysicalCameraLocation = .backFacing
    public var captureSession:AVCaptureSession
    
    var supportsFullYUVRange:Bool = false
    let captureAsYUV:Bool
    var yuvConversionShader:ShaderProgram?
    
    let frameRenderingSemaphore = DispatchSemaphore(value:1)
    public init(session: AVCaptureSession) {
        self.captureSession = session
        self.captureAsYUV = true
        super.init()
    }
    //
    public func setSession(session: AVCaptureSession) {
        self.captureSession = session
    }
    
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // Not needed for camera inputs
    }
    
    public let targets = TargetContainer()
    
    public func setYUVVideoOutput(videoOutput: AVCaptureVideoDataOutput) {
        supportsFullYUVRange = false
        let supportedPixelFormats = videoOutput.availableVideoPixelFormatTypes
        for currentPixelFormat in supportedPixelFormats {
            if ((currentPixelFormat as NSNumber).int32Value == Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)) {
                supportsFullYUVRange = true
            }
        }
        
        if (supportsFullYUVRange) {
            yuvConversionShader = crashOnShaderCompileFailure("Camera"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))]
        } else {
            yuvConversionShader = crashOnShaderCompileFailure("Camera"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionVideoRangeFragmentShader)}
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange))]
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 加锁
        guard (frameRenderingSemaphore.wait(timeout:DispatchTime.now()) == DispatchTimeoutResult.success) else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let bufferWidth = CVPixelBufferGetWidth(cameraFrame)
        let bufferHeight = CVPixelBufferGetHeight(cameraFrame)
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        CVPixelBufferLockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        sharedImageProcessingContext.runOperationAsynchronously{
            let cameraFramebuffer:Framebuffer
            
            self.delegate?.didCaptureBuffer(sampleBuffer)
            if self.captureAsYUV {
                let luminanceFramebuffer:Framebuffer
                let chrominanceFramebuffer:Framebuffer
                if sharedImageProcessingContext.supportsTextureCaches() {
                    #if os(iOS)
                    var luminanceTextureRef:CVOpenGLESTexture? = nil
                    let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, cameraFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), 0, &luminanceTextureRef)
                    let luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef!)
                    glActiveTexture(GLenum(GL_TEXTURE4))
                    glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
                    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
                    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
                    luminanceFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation: self.location.imageOrientation(), size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true, overriddenTexture:luminanceTexture)
                    
                    var chrominanceTextureRef:CVOpenGLESTexture? = nil
                    let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, cameraFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), 1, &chrominanceTextureRef)
                    let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef!)
                    glActiveTexture(GLenum(GL_TEXTURE5))
                    glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
                    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
                    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
                    chrominanceFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation: self.location.imageOrientation(), size:GLSize(width:GLint(bufferWidth / 2), height:GLint(bufferHeight / 2)), textureOnly:true, overriddenTexture:chrominanceTexture)
                    #else
                    fatalError("Texture cache processing isn't available on macOS")
                    #endif
                } else {
                    glActiveTexture(GLenum(GL_TEXTURE4))
                    luminanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: self.location.imageOrientation(), size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
                    luminanceFramebuffer.lock()
                    
                    glBindTexture(GLenum(GL_TEXTURE_2D), luminanceFramebuffer.texture)
                    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(cameraFrame, 0))
                    
                    glActiveTexture(GLenum(GL_TEXTURE5))
                    chrominanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: self.location.imageOrientation(), size:GLSize(width:GLint(bufferWidth / 2), height:GLint(bufferHeight / 2)), textureOnly:true)
                    chrominanceFramebuffer.lock()
                    glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceFramebuffer.texture)
                    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), 0, GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(cameraFrame, 1))
                }
                
                cameraFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:luminanceFramebuffer.sizeForTargetOrientation(.portrait), textureOnly:false)
                
                let conversionMatrix:Matrix3x3
                if (self.supportsFullYUVRange) {
                    conversionMatrix = colorConversionMatrix601FullRangeDefault
                } else {
                    conversionMatrix = colorConversionMatrix601Default
                }
                convertYUVToRGB(shader:self.yuvConversionShader!, luminanceFramebuffer:luminanceFramebuffer, chrominanceFramebuffer:chrominanceFramebuffer, resultFramebuffer:cameraFramebuffer, colorConversionMatrix:conversionMatrix)
            } else {
                cameraFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: self.location.imageOrientation(), size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
                glBindTexture(GLenum(GL_TEXTURE_2D), cameraFramebuffer.texture)
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(cameraFrame))
            }
            CVPixelBufferUnlockBaseAddress(cameraFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            
            cameraFramebuffer.timingStyle = .videoFrame(timestamp:Timestamp(currentTime))
            self.updateTargetsWithFramebuffer(cameraFramebuffer)
            
            self.frameRenderingSemaphore.signal()
        }
        
    }
}

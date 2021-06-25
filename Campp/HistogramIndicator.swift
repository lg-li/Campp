//
//  HistogramIndicator.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/9.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import AVFoundation
import GPUImage2

// 自动曝光辅助：实时直方图
class HistogramIndicator {
    // GPU Image Source
    private static var gpuImageSourceDelegateWrapper: GPUImageSourceDelegateWrapper? = nil
    
    // 实时直方图计算/绘制
    private static var histogramRenderView: RenderView? = nil
    private static var gpuHistogram: Histogram =  GPUImage2.Histogram(type: .rgb)
    private static let gpuHistogramDisplay: HistogramDisplay = GPUImage2.HistogramDisplay()
    
    // 实时 GPU Luminance 计算
    private static let gpuLuminanceExtractor: AverageLuminanceExtractor = GPUImage2.AverageLuminanceExtractor()
    public static var currentLuminanace: Float = 0.5
    
    public static func setupImageSource(session: AVCaptureSession, videoOutput: AVCaptureVideoDataOutput) -> GPUImageSourceDelegateWrapper {
        gpuImageSourceDelegateWrapper = GPUImageSourceDelegateWrapper(session: session)
        gpuImageSourceDelegateWrapper!.setYUVVideoOutput(videoOutput: videoOutput)
        return gpuImageSourceDelegateWrapper!
    }
    
    // 构建直方图实时计算与亮度实时计算数据流
    public static func setupRealtimeHistogram(to: UIView) {
//        gpuHistogram = GPUImage2.Histogram(type:.rgb)
        gpuHistogram.downsamplingFactor = 256
        gpuHistogram.backgroundColor = .transparent
        gpuHistogramDisplay.overriddenOutputSize =  Size(width: 150.0, height: 75.0)
        gpuHistogramDisplay.backgroundColor = .transparent
        // 平均亮度实时计算，需设置为成员/静态变量否则将被回收
        gpuLuminanceExtractor.extractedLuminanceCallback = { luminance in
            currentLuminanace = luminance
//            print("luminance \(luminance)")
        }
        DispatchQueue.main.async {
            histogramRenderView = GPUImage2.RenderView(frame: to.bounds)
            histogramRenderView?.backgroundRenderColor = .transparent
            histogramRenderView?.layer.cornerRadius = 5
            histogramRenderView?.backgroundColor = .darkGray
            to.addSubview(histogramRenderView!)
            to.sizeToFit()
            // 实时直方图处理流水线
            gpuImageSourceDelegateWrapper! --> gpuHistogram --> gpuHistogramDisplay --> histogramRenderView!
            // 实时平均亮度数据流
            gpuImageSourceDelegateWrapper! --> gpuLuminanceExtractor;
        }
    }
}

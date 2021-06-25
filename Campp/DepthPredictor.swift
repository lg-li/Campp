//
//  DepthPredictor.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/9.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import Vision

class DepthPredictor {
    // 单目景深模型 FCRN
    private static let estimationModel = FCRN()
    private static var request: VNCoreMLRequest?
    private static var visionModel: VNCoreMLModel?
    private static var onComplete: ((MLMultiArray) -> Void)?
}

// 深度感知模型控制
extension DepthPredictor {
    
    // 单目深度感知模型
    static func setupDepthFCRNModel() {
        print("初始化深度预测FCRN模型...")
        if let visionModel = try? VNCoreMLModel(for: DepthPredictor.estimationModel.model) {
            DepthPredictor.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError()
        }
    }
    
    static func predict(with pixelBuffer: CVPixelBuffer, onComplete: @escaping ((MLMultiArray) -> Void)) {
        guard let request = request else {
            print("未初始化模型，操作非法!")
            fatalError()
        }
        print("预测深度...")
        DepthPredictor.onComplete = onComplete
        // vision framework configures the input size of image following our model's input configuration automatically
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    static func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNCoreMLFeatureValueObservation], let heatmap = observations.first?.featureValue.multiArrayValue {
            guard onComplete != nil else {
                print("未指定回调")
                return
            }
            print("调用深度预测回调...")
            onComplete!(heatmap)
//            let convertedHeatmap = convertTo2DArray(from: heatmap)
            //            DispatchQueue.main.async { [weak self] in
            //                // update result
            //                self?.drawingView.heatmap = convertedHeatmap
            //            }
        } else {
            // end of measure
            
        }
    }
}

extension DepthPredictor {
    static func convertTo2DArray(from heatmaps: MLMultiArray) -> Array<Array<Double>> {
        guard heatmaps.shape.count >= 3 else {
            print("heatmap's shape is invalid. \(heatmaps.shape)")
            return []
        }
        let _/*keypoint_number*/ = heatmaps.shape[0].intValue
        let heatmap_w = heatmaps.shape[1].intValue
        let heatmap_h = heatmaps.shape[2].intValue
        
        var convertedHeatmap: Array<Array<Double>> = Array(repeating: Array(repeating: 0.0, count: heatmap_w), count: heatmap_h)
        
        var minimumValue: Double = Double.greatestFiniteMagnitude
        var maximumValue: Double = -Double.greatestFiniteMagnitude
        
        for i in 0..<heatmap_w {
            for j in 0..<heatmap_h {
                let index = i*(heatmap_h) + j
                let confidence = heatmaps[index].doubleValue
                guard confidence > 0 else { continue }
                convertedHeatmap[j][i] = confidence
                
                if minimumValue > confidence {
                    minimumValue = confidence
                }
                if maximumValue < confidence {
                    maximumValue = confidence
                }
            }
        }
        //  归一化
        let minmaxGap = maximumValue - minimumValue
        
        for i in 0..<heatmap_w {
            for j in 0..<heatmap_h {
                convertedHeatmap[j][i] = (convertedHeatmap[j][i] - minimumValue) / minmaxGap
            }
        }
        
        return convertedHeatmap
    }
}

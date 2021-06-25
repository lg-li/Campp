//
//  ExposureStrategy.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/3.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation

let e: Float = 2.7182818
let suggestedMaxISO: Float = 40
let suggestedMaxShutterDuration = 0.2

public func getOptimizedShutterSecondsAndISO(currentISO: Float, deviceMinISO: Float, currentShutterSeconds: Double, currentPixelLuminance: Float, currentAccelerationScale: Double) -> (Double, Float) {
    let minShutterSeconds = 0.001
    // 计算当前抖动下最大的曝光时长
    let maxOptimizedShutterParamAlpha = 100 * (0.25 - minShutterSeconds);
    var maxOptimizedShutter = maxOptimizedShutterParamAlpha/currentAccelerationScale + minShutterSeconds
    if (maxOptimizedShutter > suggestedMaxShutterDuration) {
        maxOptimizedShutter = suggestedMaxShutterDuration
    }
    if currentISO <= suggestedMaxISO {
        print("returned optimizedShutter = \(currentShutterSeconds)")
        return (currentShutterSeconds, deviceMinISO)
    }
    // 选取合适的ISO
    let optimizedISO = sigmod(x: 1 - currentPixelLuminance + 0.5)*(suggestedMaxISO-deviceMinISO) + deviceMinISO
    
    // 反比例调整曝光时间
    var optimizedShutter = Double(currentISO / optimizedISO) * currentShutterSeconds / Double(currentPixelLuminance * 5)
    // 处理范围溢出情况
    if(optimizedShutter > maxOptimizedShutter) {
        optimizedShutter = maxOptimizedShutter
    } else if (optimizedShutter < minShutterSeconds) {
        optimizedShutter = minShutterSeconds
    }
    print("returned optimizedShutter = \(optimizedShutter)")
    return (optimizedShutter, optimizedISO)
}

public func sigmod(x: Float) -> Float {
    return 1/(1+pow(e, -x))
}

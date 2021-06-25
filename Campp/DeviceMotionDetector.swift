//
//  DeviceMotionDetector.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/9.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import CoreMotion

// 自动曝光辅助：稳定性检测
class DeviceMotionDetector {
    
    // 重力传感器
    private static let motionManager = CMMotionManager()
    public static var deviceAccelerationScale: Double = 0
    
    public static func setupMotionDetect() {
        if motionManager.isDeviceMotionAvailable {
            let queue = OperationQueue()
            motionManager.deviceMotionUpdateInterval = 1/100
            motionManager.startDeviceMotionUpdates(to: queue) {  (deviceMotion, error) in
                // 计算加速度强度
                let acceleration = deviceMotion!.userAcceleration
                var accelerationScale = acceleration.x*acceleration.x
                accelerationScale += acceleration.y*acceleration.y
                accelerationScale += acceleration.z*acceleration.z
                accelerationScale = sqrt(self.deviceAccelerationScale)
                self.deviceAccelerationScale = accelerationScale
                //                print("deviceAccelerationScale=\(self.deviceAccelerationScale)")
            }
        }
    }
}

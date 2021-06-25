/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The app's primary view controller that presents the camera interface.
 */

import UIKit
import AVFoundation
import Photos
import MediaPlayer
import Vision

import fluid_slider
import GPUImage2


class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, ItemSelectionViewControllerDelegate, AVAudioPlayerDelegate {
    
    private let semaphore = DispatchSemaphore(value: 1)
    private var spinner: UIActivityIndicatorView!
    
    private let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    @IBOutlet weak var manualAdjustStackView: UIStackView!
    
    private var autoWB = true
    @IBOutlet weak var autoWBButton: UIButton!
    
    private var autoFocus = true
    @IBOutlet weak var lockAutoFocusButton: UIButton!
    
    @IBOutlet weak var hiderView: UIView!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressPrompt: UILabel!
    @IBOutlet weak var progressBar: UIProgressView!
    
//    @IBOutlet weak var photoCountLabel: UILabel!
    private var photoCount: Int = 4
    
    private var controlsMode : ControlsMode = .shown
    @IBOutlet weak var controlsButton: UIButton!
    
    @IBOutlet weak var tintAdjustSlider: fluid_slider.Slider!
    var tint: Float = 0.0
    
    @IBOutlet weak var tempAdjustSlider: fluid_slider.Slider!
    var temperature: Float = 0.0
    
    @IBOutlet weak var focusAdjustSlider: fluid_slider.Slider!
    var focus: Double = 0.5
    
    @IBOutlet weak var isoAdjustSlider: fluid_slider.Slider!
    var iso: Float = 200
    
    @IBOutlet weak var shutterAdjustSlider: fluid_slider.Slider!
    var shutterDuration: CMTime = CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000)
    
    // 实时直方图UIView
    @IBOutlet weak var histogramView: UIView!
    
    @IBOutlet weak var depthHeatMap: HeatmapView!
    
    var myPlayer: AVAudioPlayer? = nil
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    private var isoSliderMin:Float = 0.0
    private var isoSliderMax: Float = 0.0
    private var tempSliderMin: Float = 3000.0
    private var tempSliderMax: Float = 8000.0
    private var tintSliderMin: Float = -150
    private var tintSliderMax: Float = 150
    
    private var minDurationSeconds: Double = 0
    private var maxDurationSeconds: Double = 0
    
    let sliderLabelTextAttributes: [NSAttributedString.Key : Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: UIColor.white]
    
    // MARK: View Controller Life Cycle
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.becomeFirstResponder()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    
    override var canBecomeFirstResponder : Bool {
        return true
    }
    
    override func remoteControlReceived(with event: UIEvent?) {
//        let rc = event!.subtype
        // self.photoCountLabel.text = "received remote control \(rc.rawValue)"
        
        self.capturePhoto(self.photoButton)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Disable the UI. Enable the UI later, if and only if the session starts running.
        cameraButton.isEnabled = false
//        recordButton.isEnabled = false
        photoButton.isEnabled = false
        // semanticSegmentationMatteDeliveryButton.isEnabled = false
        captureModeControl.isEnabled = false
        
        // Set up the video preview view.
        previewView.session = session
        
        /*
         Check the video authorization status. Video access is required and audio
         access is optional. If the user denies audio access, AVCam won't
         record audio during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
        
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
        }
        
        var defaultVideoDevice: AVCaptureDevice?
        
        if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            defaultVideoDevice = dualCameraDevice
        } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            // If a rear dual camera is not available, default to the rear wide angle camera.
            defaultVideoDevice = backCameraDevice
        } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            // If the rear wide angle camera isn't available, default to the front wide angle camera.
            defaultVideoDevice = frontCameraDevice
        }
        if let videoDevice = defaultVideoDevice {
            do {
                try videoDevice.lockForConfiguration()
                videoDevice.focusMode = .continuousAutoFocus //.locked
                videoDevice.exposureMode = .custom
                videoDevice.unlockForConfiguration()
                
                self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                //                self.focusSliderChanged(self.focusSlider)
                //                self.isoSliderChanged(self.isoSlider)
                //                self.shutterSliderChanged(self.shutterSlider)
            } catch {
                print("couldn't adjust sliders")
            }
        }
        
        /*
         初始化手动栏条
         */
        self.initSliderLims()
        self.initFluidSliders()
        // 初始化深度模型
        DepthPredictor.setupDepthFCRNModel()
        
//        // Play Shitty sound
//        guard let testPlayer = loadSound(filename: "silence") else {
//            print("Not able to load the sound")
//            return
//        }
//        testPlayer.delegate = self
//        testPlayer.volume = 0.8
//        testPlayer.numberOfLoops = -1
//        myPlayer = testPlayer
//        myPlayer?.play()
//        print("PLAYED")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    //    private func updatePhotoCount() {
    //        self.photoCountLabel.text = "HDR+ 曝光帧数: \(Int(self.photoCountStepper.value))"
    //        self.photoCount = Int(self.photoCountStepper.value)
    //    }
    
    // MARK: UI Handling
    //    @IBAction func stepperValueChanged(_ stepper: UIStepper) {
    //        self.updatePhotoCount()
    //    }
    
    @IBAction func openGallery(_ galleryButton: UIButton) {
        let galleryStoryBoard = UIStoryboard.init(name: "Gallery", bundle: nil)
        let galleryViewController = galleryStoryBoard.instantiateViewController(identifier: "GalleryViewController")
        print(self.navigationController ?? "NULL")
        DispatchQueue.main.async {
            self.present(galleryViewController, animated: true, completion: {
                print("Presented.")
            });
        }
    }
    
    @IBAction func controlsButtonPressed(_ sender: Any) {
        DispatchQueue.main.async {
            if (self.controlsMode == .hidden) {
                // Controls were hidden, show them
//                self.manualAdjustStackView.layer.opacity = 1.0
                UIView.animate(withDuration: 0.3, animations: {
                    //self.manualAdjustStackView.layer.opacity = 0.0

                    self.manualAdjustStackView.isHidden = false
                })
                self.controlsButton.setImage(UIImage(systemName: "wrench.fill"), for: .normal)
                self.controlsMode = .shown
            } else {
                // Controls were shown, hide them
//                self.manualAdjustStackView.layer.opacity = 1.0
                UIView.animate(withDuration: 0.3, animations: {
                    self.manualAdjustStackView.isHidden = true
//                    self.manualAdjustStackView.layer.opacity = 0.0
                })
                self.controlsButton.setImage(UIImage(systemName: "wrench"), for: .normal)
                self.controlsMode = .hidden
            }
        }
    }
    
    @IBAction func lockToggled(_ autoFocusButton: UIButton) {
        if (self.autoFocus) {
            self.autoFocus = false
            autoFocusButton.setTitle("对焦解锁", for: [])
        } else {
            self.autoFocus = true
            autoFocusButton.setTitle("对焦锁定", for: [])
        }
    }
    
    private func onFocusChanged(newFocus: Float) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setFocusModeLocked(lensPosition: newFocus)
            // self.focus = newFocus
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
            print("Couldn't lock for configuration", error)
        }
    }
    
    @IBAction func autoWBToggled(_ sender: Any) {
        if (self.autoWB) {
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                self.videoDeviceInput.device.whiteBalanceMode = .locked
                self.autoWB = false
                self.autoWBButton.setTitle("开启自动白平衡", for: [])
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                print("couldn't change WB mode to locked")
            }
        } else {
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                self.videoDeviceInput.device.whiteBalanceMode = .continuousAutoWhiteBalance
                self.autoWB = true
                self.autoWBButton.setTitle("关闭自动白平衡", for: [])
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                print("couldn't change WB mode to auto")
            }
        }
    }
    private func setDeviceWhiteBalance(newTint: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues) {
        do {
            let maxWB = self.videoDeviceInput.device.maxWhiteBalanceGain
            var newWB = self.videoDeviceInput.device.deviceWhiteBalanceGains(for: newTint)
            // 将白平衡 clamp 到范围中
            newWB.redGain = min(max(1, newWB.redGain), maxWB)
            newWB.greenGain = min(max(1, newWB.greenGain), maxWB)
            newWB.blueGain = min(max(1, newWB.blueGain), maxWB)
            
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setWhiteBalanceModeLocked(with: newWB)
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
            print("Couldn't lock for configuration", error)
        }
    }
    
    private func onTempChanged(newTemp: Float) {
        let wbGains = self.videoDeviceInput.device.deviceWhiteBalanceGains
        var tempTint = self.videoDeviceInput.device.temperatureAndTintValues(for: wbGains)
        tempTint.temperature = newTemp
        self.setDeviceWhiteBalance(newTint: tempTint)
    }
    
    private func onTintChanged(newTint: Float) {
        let wbGains = self.videoDeviceInput.device.deviceWhiteBalanceGains
        var tempTint = self.videoDeviceInput.device.temperatureAndTintValues(for: wbGains)
        tempTint.tint = newTint
        self.setDeviceWhiteBalance(newTint: tempTint)
    }
    
    private func onIsoChanged(newIso: Float) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            let duration = self.videoDeviceInput.device.exposureDuration
            self.videoDeviceInput.device.setExposureModeCustom(duration: duration, iso: newIso)
            // self.isoLabel.text = String(Int(slider.value))
            self.iso = newIso
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
            print("Couldn't lock for configuration when ISO changes", error)
        }
    }
    
    @IBAction func isoSliderChanged(_ slider: UISlider) {
        self.onIsoChanged(newIso: slider.value)
    }
    
    private func onShutterChanged(newShutterSliderVal: Float) {
        let device = self.videoDeviceInput.device
        var newDurationSeconds: Double = minDurationSeconds
        if newShutterSliderVal > 0 {
            let p = pow(Double(newShutterSliderVal), kExposureDurationPower) // Apply power function to expand slider's low-end range
            newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
            
        }
        if newDurationSeconds > maxDurationSeconds {
            newDurationSeconds = maxDurationSeconds
        }
        if newDurationSeconds < minDurationSeconds {
            newDurationSeconds = minDurationSeconds
        }
        do {
            let shuttuerDurationToSet = CMTimeMakeWithSeconds(newDurationSeconds, preferredTimescale: 1000*1000*1000)
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: shuttuerDurationToSet, iso: AVCaptureDevice.currentISO, completionHandler: nil)
            device.unlockForConfiguration()
            self.shutterDuration = shuttuerDurationToSet
        } catch {
            print("NextLevel, setExposureModeCustom failed to lock device for configuration")
        }
    }
    
    private func setDeviceShutterDurationAndISOTo(duration: CMTime, iso: Float) {
        let device = self.videoDeviceInput.device
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("WARNING: setExposureModeCustom failed to lock device for configuration")
        }
        
    }
    
    @IBAction func shutterSliderChanged(_ slider: UISlider) {
        onShutterChanged(newShutterSliderVal: slider.value)
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    private let loggerQueue = DispatchQueue(label: "logger queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        
        if setupResult != .success {
            return
        }
        session.beginConfiguration()
        
        /*
         Do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
         */
        session.sessionPreset = .photo
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            //            if let backCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            //                // iPhone 11/11 Pro/11 Pro Max
            //                print("Choosing builtInDualWideCamera...")
            //                defaultVideoDevice = backCameraDevice
            //            } else if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            //                // iPhone X/XS/XS Max
            //                print("Choosing builtInDualCamera...")
            //                defaultVideoDevice = dualCameraDevice
            //            } else
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // 没有双摄不支持景深啦
                print("Choosing back builtInWideAngleCamera...")
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // 后摄都坏了？怕不是组装机，只有前置摄像头咯
                print("Choosing front builtInWideAngleCamera...")
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                     You can manipulate UIView only on the main thread.
                     Note: As an exception to the above rule, it's not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the window scene's orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                    
                    self.initSliderLims()
                    self.updateSliders()
                    // self.updatePhotoCount()
                    
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
//        gpuImageSourceDelegateWrapper = GPUImageSourceDelegateWrapper(session: session)
        
        let videoOutput = AVCaptureVideoDataOutput()
//        gpuImageSourceDelegateWrapper?.setYUVVideoOutput(videoOutput: videoOutput)
        
        print("can add output: \(session.canAddOutput(photoOutput))")
        session.addOutput(videoOutput)
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            selectedSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
            portraitEffectsMatteDeliveryMode = photoOutput.isPortraitEffectsMatteDeliverySupported ? .on : .off
            photoQualityPrioritizationMode = .balanced
            //            bracketCount = photoOutput.maxBracketedCapturePhotoCount-1
            //            bracketCount = 1
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        // previewView.videoPreviewLayer.connection?.output.
        
        session.commitConfiguration()
        
        videoOutput.setSampleBufferDelegate(
            HistogramIndicator.setupImageSource(session: session, videoOutput: videoOutput),
            queue: DispatchQueue.global()
        )
        // 配置实时直方图绘制
        HistogramIndicator.setupRealtimeHistogram(to: self.histogramView)
        // 配置抖动检测
        DeviceMotionDetector.setupMotionDetect()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running, for example, if a phone or FaceTime call is still
             using audio or video. This failure is communicated by the session posting a
             runtime error notification. To avoid repeatedly failing to start the session,
             only try to restart the session in the error handler if you aren't
             trying to resume the session.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    private enum CaptureMode: Int {
        case photo = 0
        case movie = 1
    }
    
    @IBOutlet private weak var captureModeControl: UISegmentedControl!
    
    /// - Tag: EnableDisableModes
//    @IBAction private func toggleCaptureMode(_ captureModeControl: UISegmentedControl) {
//        captureModeControl.isEnabled = false
//
//        if captureModeControl.selectedSegmentIndex == CaptureMode.photo.rawValue {
//            recordButton.isEnabled = false
//
//            sessionQueue.async {
//                // Remove the AVCaptureMovieFileOutput from the session because it doesn't support capture of Live Photos.
//                self.session.beginConfiguration()
//                self.session.removeOutput(self.movieFileOutput!)
//                self.session.sessionPreset = .photo
//
//                DispatchQueue.main.async {
//                    captureModeControl.isEnabled = true
//                }
//
//                self.movieFileOutput = nil
//
//                if self.photoOutput.isLivePhotoCaptureSupported {
//                    self.photoOutput.isLivePhotoCaptureEnabled = true
//                }
//                if self.photoOutput.isDepthDataDeliverySupported {
//                    self.photoOutput.isDepthDataDeliveryEnabled = true
//                }
//
//                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
//                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
//                }
//
//                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
//                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
//                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
//
//                    DispatchQueue.main.async {
//                        //self.semanticSegmentationMatteDeliveryButton.isEnabled = (self.depthDataDeliveryMode == .on) ? true : false
//                    }
//                }
//
//                DispatchQueue.main.async {
//                    // self.semanticSegmentationMatteDeliveryButton.isHidden = false
//                }
//                self.session.commitConfiguration()
//            }
//        } else if captureModeControl.selectedSegmentIndex == CaptureMode.movie.rawValue {
//            // semanticSegmentationMatteDeliveryButton.isHidden = true
//
//            sessionQueue.async {
//                let movieFileOutput = AVCaptureMovieFileOutput()
//
//                if self.session.canAddOutput(movieFileOutput) {
//                    self.session.beginConfiguration()
//                    self.session.addOutput(movieFileOutput)
//                    self.session.sessionPreset = .high
//                    if let connection = movieFileOutput.connection(with: .video) {
//                        if connection.isVideoStabilizationSupported {
//                            connection.preferredVideoStabilizationMode = .auto
//                        }
//                    }
//                    self.session.commitConfiguration()
//
//                    DispatchQueue.main.async {
//                        captureModeControl.isEnabled = true
//                    }
//
//                    self.movieFileOutput = movieFileOutput
//
//                    DispatchQueue.main.async {
//                        self.recordButton.isEnabled = true
//
//                        /*
//                         For photo captures during movie recording, Speed quality photo processing is prioritized
//                         to avoid frame drops during recording.
//                         */
//                    }
//                }
//            }
//        }
//    }
    
    // MARK: Device Configuration
    
    @IBOutlet private weak var cameraButton: UIButton!
    
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
                                                                               mediaType: .video, position: .unspecified)
    
    /// - Tag: ChangeCamera
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        cameraButton.isEnabled = false
//        recordButton.isEnabled = false
        photoButton.isEnabled = false
        captureModeControl.isEnabled = false
        // semanticSegmentationMatteDeliveryButton.isEnabled = false
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                DispatchQueue.main.async {
                    self.focusAdjustSlider.isHidden = false
                }
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
                
            case .back:
                DispatchQueue.main.async {
                    self.focusAdjustSlider.isHidden = true
                }
                preferredPosition = .front
                preferredDeviceType = .builtInTrueDepthCamera
                
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                DispatchQueue.main.async {
                    self.focusAdjustSlider.isHidden = false
                }
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        //                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        //                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    /*
                     Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
                     `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
                     get set to false when a video device is disconnected from the session. After the new video device is
                     added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
                     */
                    self.photoOutput.isLivePhotoCaptureEnabled = false // self.photoOutput.isLivePhotoCaptureSupported
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = false // self.photoOutput.isPortraitEffectsMatteDeliverySupported
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
//                self.recordButton.isEnabled = self.movieFileOutput != nil
                self.photoButton.isEnabled = true
                self.captureModeControl.isEnabled = true
                // 根据变化后的参数重新配置sliders
                self.initSliderLims()
                self.initFluidSliders()
                //                self.semanticSegmentationMatteDeliveryButton.isEnabled = (self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty || self.depthDataDeliveryMode == .off) ? false : true
            }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        if (autoFocus) {
            let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
            focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: false)
        }
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.updateSliders()
                }
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Capturing Photos
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var activeDelegates = [Int64: AVCapturePhotoCaptureDelegate]()
    
    @IBOutlet private weak var photoButton: UIButton!
    
    // 拍摄照片
    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        self.photoButton.isUserInteractionEnabled = false
        
        let minIso = self.videoDeviceInput.device.activeFormat.minISO
        let maxIso = self.videoDeviceInput.device.activeFormat.maxISO
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            // 配置 HDR burst 曝光栈
            HDRCaptureDelegate.totalPhotoCountExpceted.value = self.photoCount
            // 配置深度数据预测外部回调
            HDRCaptureDelegate.depthPredictionCompletionExternalHandler = self.depthPredictionRequestDidComplete
            print("Taking \(self.photoCount) Photos...")
            let wbGains = self.videoDeviceInput.device.deviceWhiteBalanceGains
            let wbR = wbGains.redGain / wbGains.greenGain;
            let wbG: Float = 1.0;
            let wbB = wbGains.blueGain / wbGains.greenGain;
            HDRCaptureDelegate.setWhiteBalanceGains(r: wbR, g: wbG, b: wbB)
            // 图像类型
            let imageType = HDRCaptureDelegate.ImageType.DARK
            
            // 获取优化曝光设置
            let currentShutterSeconds =  CMTimeGetSeconds(self.shutterDuration)
            print("current shutter sec=\(currentShutterSeconds)")
            
            
            //********************************
            for p in 0..<self.photoCount {
                print("   #\(p): waiting for capture")
                self.semaphore.wait()
                print("   #\(p): starting on capture")
                
                let (optimizedShutterSeconds, optimizedISO) = getOptimizedShutterSecondsAndISO(
                    currentISO: self.iso,
                    deviceMinISO: minIso,
                    currentShutterSeconds: currentShutterSeconds,
                    currentPixelLuminance: HistogramIndicator.currentLuminanace,
                    currentAccelerationScale: DeviceMotionDetector.deviceAccelerationScale)
                let secondsFraction = self.realNum2fractionString(realNum: optimizedShutterSeconds)
                DispatchQueue.main.async {
                    self.progressPrompt.text = "快门\(secondsFraction)s / ISO\(optimizedISO) "
                }
                let optimizedShutterDuration = CMTimeMakeWithSeconds(optimizedShutterSeconds, preferredTimescale: 1000*1000*1000)
                // 锁定设备快门和ISO
                self.setDeviceShutterDurationAndISOTo(duration: optimizedShutterDuration, iso: optimizedISO)
                
                // 创建拍摄配置
                let photoSettings = getRAWQuickSettings(capturePhotoOutput: self.photoOutput,
                                                        iso: optimizedISO,
                                                        shutterDuration: optimizedShutterDuration,
                                                        withProcessedFormat: false)
                
                //                print("[Depth] isDepthDataDeliverySupported = \(self.photoOutput.isDepthDataDeliverySupported)")
                //                // 设置景深数据是否支持
                //                photoSettings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                
                if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                    photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
                }
                
                let processor = HDRCaptureDelegate(with: photoSettings, willCapturePhotoAnimation: {
                    // 拍摄时显示闪屏动画
                    DispatchQueue.main.async {
                        self.previewView.videoPreviewLayer.opacity = 0
                        UIView.animate(withDuration: 0.15) {
                            self.previewView.videoPreviewLayer.opacity = 0.8
                        }
                    }
                }, completionHandler: { photoCaptureProcessor in
                    // 拍摄结束时，删除对delegate的引用以使其被释放回收
                    self.activeDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                    print("   #\(p): releasing signal of #\(photoCaptureProcessor.requestedPhotoSettings.uniqueID)")
                    self.semaphore.signal()
                }, photoProcessingHandler: { animate in
                    // 显示处理动画
                    DispatchQueue.main.async {
                        if animate {
                            self.spinner.hidesWhenStopped = true
                            self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                            self.spinner.startAnimating()
                        } else {
                            self.spinner.stopAnimating()
                        }
                    }
                },
                   logger: self.logger,
                   imageType: imageType
                )
                print("   #\(p): adding uniqueID #\(processor.requestedPhotoSettings.uniqueID)")
                // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
                self.activeDelegates[processor.requestedPhotoSettings.uniqueID] = processor
                self.photoOutput.capturePhoto(with: photoSettings,
                                              delegate: processor)
            }
            //            ********************************
        }
    }
    
    private enum ControlsMode {
        case shown
        case hidden
    }
    
    private enum DepthDataDeliveryMode {
        case on
        case off
    }
    
    private enum PortraitEffectsMatteDeliveryMode {
        case on
        case off
    }
    
    private var depthDataDeliveryMode: DepthDataDeliveryMode = .off
    
    private var portraitEffectsMatteDeliveryMode: PortraitEffectsMatteDeliveryMode = .off
    
    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .quality
    
    // @IBOutlet weak var semanticSegmentationMatteDeliveryButton: UIButton!
    
    //    @IBAction func toggleSemanticSegmentationMatteDeliveryMode(_ semanticSegmentationMatteDeliveryButton: UIButton) {
    //        let itemSelectionViewController = ItemSelectionViewController(delegate: self,
    //                                                                      identifier: semanticSegmentationTypeItemSelectionIdentifier,
    //                                                                      allItems: photoOutput.availableSemanticSegmentationMatteTypes,
    //                                                                      selectedItems: selectedSemanticSegmentationMatteTypes,
    //                                                                      allowsMultipleSelection: true)
    //
    //        presentItemSelectionViewController(itemSelectionViewController)
    //
    //    }
    
    // MARK: ItemSelectionViewControllerDelegate
    
    let semanticSegmentationTypeItemSelectionIdentifier = "SemanticSegmentationTypes"
    
    private func presentItemSelectionViewController(_ itemSelectionViewController: ItemSelectionViewController) {
        let navigationController = UINavigationController(rootViewController: itemSelectionViewController)
        navigationController.navigationBar.barTintColor = .black
        navigationController.navigationBar.tintColor = view.tintColor
        present(navigationController, animated: true, completion: nil)
    }
    
    func itemSelectionViewController(_ itemSelectionViewController: ItemSelectionViewController,
                                     didFinishSelectingItems selectedItems: [AVSemanticSegmentationMatte.MatteType]) {
        let identifier = itemSelectionViewController.identifier
        
        if identifier == semanticSegmentationTypeItemSelectionIdentifier {
            sessionQueue.async {
                self.selectedSemanticSegmentationMatteTypes = selectedItems
            }
        }
    }
    
    private var inProgressLivePhotoCapturesCount = 0
    
    @IBOutlet var capturingLivePhotoLabel: UILabel!
    
    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
//    @IBOutlet private weak var recordButton: UIButton!
    
    @IBOutlet private weak var resumeButton: UIButton!
    
//    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
//        guard let movieFileOutput = self.movieFileOutput else {
//            return
//        }
//
//        /*
//         Disable the Camera button until recording finishes, and disable
//         the Record button until recording starts or finishes.
//
//         See the AVCaptureFileOutputRecordingDelegate methods.
//         */
//        cameraButton.isEnabled = false
////        recordButton.isEnabled = false
//        captureModeControl.isEnabled = false
//
//        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
//
//        sessionQueue.async {
//            if !movieFileOutput.isRecording {
//                if UIDevice.current.isMultitaskingSupported {
//                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
//                }
//
//                // Update the orientation on the movie file output video connection before recording.
//                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
//                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
//
//                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
//
//                if availableVideoCodecTypes.contains(.hevc) {
//                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
//                }
//
//                // Start recording video to a temporary file.
//                let outputFileName = NSUUID().uuidString
//                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
//                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
//            } else {
//                movieFileOutput.stopRecording()
//            }
//        }
//    }
    
    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
//            self.recordButton.isEnabled = true
//            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }
    
    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
//            self.recordButton.isEnabled = true
            self.captureModeControl.isEnabled = true
//            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureVideo"), for: [])
        }
    }
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            let isSemanticSegmentationMatteEnabled = !self.photoOutput.enabledSemanticSegmentationMatteTypes.isEmpty
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
//                self.recordButton.isEnabled = isSessionRunning && self.movieFileOutput != nil
                self.photoButton.isEnabled = isSessionRunning
                self.captureModeControl.isEnabled = isSessionRunning
                // self.semanticSegmentationMatteDeliveryButton.isEnabled = isSessionRunning && isSemanticSegmentationMatteEnabled
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        // FOR WHEN THINGS MAGICALLY CHANGE
        let isoObservation = observe(\.videoDeviceInput.device.iso, options: .new) { _, change in
            guard let newIso = change.newValue else { return }
            self.updateIsoSlider(newIso)
        }
        keyValueObservations.append(isoObservation)
        
        let shutterObservation = observe(\.videoDeviceInput.device.exposureDuration, options: .new) { _, change in
            guard let newShutter = change.newValue else { return }
            self.updateShutterSlider(newShutter, self.videoDeviceInput.device)
        }
        keyValueObservations.append(shutterObservation)
        
        let focusObservation = observe(\.videoDeviceInput.device.lensPosition, options: .new) { _, change in
            guard let newFocus = change.newValue else { return }
            self.updateFocusSlider(newFocus)
        }
        keyValueObservations.append(focusObservation)
        
        let wbObservation = observe(\.videoDeviceInput.device.deviceWhiteBalanceGains, options: .new) { _, change in
            let newWB = self.videoDeviceInput.device.deviceWhiteBalanceGains
            let tempTint = self.videoDeviceInput.device.temperatureAndTintValues(for: newWB)
            self.updateTempSlider(tempTint.temperature)
            self.updateTintSlider(tempTint.tint)
        }
        keyValueObservations.append(wbObservation)
        
        //        NotificationCenter.default.addObserver(self,
        //                                               selector: #selector(subjectAreaDidChange),
        //                                               name: .AVCaptureDeviceSubjectAreaDidChange,
        //                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleSystemPressure
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios you want to enable the user to resume the session.
         For example, if music playback is initiated from Control Center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in Control Center will not automatically resume the session.
         Also note that it's not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                // Fade-in a button to enable the user to try to resume the session running.
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
}

// 日志操作
extension CameraViewController {
    /*
     logger
     */
    private func logger(_ status: StatusUpdate, _ partial: Float?) {
        loggerQueue.async {
            let part = (partial ?? 0.0)
            let percentage =
                (part + Float(HDRCaptureDelegate.currentReceivedPhotoCount.value)) /
                    Float(HDRCaptureDelegate.totalPhotoCountExpceted.value)
            
            let n = Int(HDRCaptureDelegate.currentReceivedPhotoCount.value + 1)
            let d = Int(HDRCaptureDelegate.totalPhotoCountExpceted.value)
            
            var uiUpdates: () -> Void = {}
                
                switch(status) {
                case .BurstStarted:
                    uiUpdates =  {
                        self.progressBar.progress = 0.3
                        self.progressLabel.text = "合成 HDR 图像"
                    }
                    break
                case .BurstFinished:
                    uiUpdates =  {
                        self.progressBar.progress = 0.6
                        self.progressLabel.text = "HDR 图像合成完毕"
                    }
                    break
                case .Launch:
                    uiUpdates = {
                        self.view.bringSubviewToFront(self.hiderView)
                        self.hiderView.isHidden = false
                        self.view.bringSubviewToFront(self.progressBar)
                        self.view.bringSubviewToFront(self.progressLabel)
                        self.progressBar.isHidden = false
                        self.progressLabel.isHidden = false
                        self.progressBar.progress = 0.0
                        self.progressLabel.text = "请稍等"
                        
                        self.manualAdjustStackView.isHidden = true
                        self.controlsButton.setImage(UIImage(systemName: "wrench"), for: .normal)
                        self.controlsMode = .hidden
                    }
                    print("Launched... ")
                    break
                    
                case .CaptureStarted:
                    uiUpdates =  {
                        self.view.bringSubviewToFront(self.hiderView)
                        self.hiderView.isHidden = false
                        self.view.bringSubviewToFront(self.progressBar)
                        self.view.bringSubviewToFront(self.progressLabel)
                        self.progressBar.isHidden = false
                        self.progressLabel.isHidden = false
                        
                        self.progressBar.progress = percentage
    //                    self.progressLabel.text = "拍摄 \(n)/\(d)"
                    }
                    print("Starting Capture: \(percentage*95) %")
                    break
                    
                case .CaptureProgress:
                    uiUpdates =  {
                        self.progressBar.progress = percentage
                        self.progressLabel.text = "聚合拍摄帧 \(n)/\(d)"
                    }
                    print("Aggregating Capture: \(percentage*95) %")
                    break
                    
                case .CaptureFinished:
                    uiUpdates =  {
                        self.progressBar.progress = percentage
    //                    self.progressLabel.text = "完成拍摄 \(n)/\(d)"
                    }
                    print("Finished a single capture \(n)/\(d)")
                    break
                    
                case .Saving:
                    uiUpdates =  {
                        self.progressBar.progress = 0.85
                        self.progressLabel.text = "保存图像..."
                    }
                    print("Saving progress")
                    break
                case .Saved:
                    uiUpdates =  {
                        self.progressBar.progress = 1.0
                        self.hiderView.isHidden = true
                        self.progressBar.isHidden = true
                        self.progressLabel.isHidden = true
                        self.progressLabel.text = "Saved!"
                        self.photoButton.isUserInteractionEnabled = true
                    }
                    HDRCaptureDelegate.clearForRestart()
                    
                    print("Saved!")
                    break
                case .Error:
                    uiUpdates =  {
                        self.progressLabel.text = "Error, trying again"
                    }
                    break
                }
                
                // Run UI Updates on main thread
                DispatchQueue.main.sync {
                    print("Doing UI Updates for Status: \(status)")
                    uiUpdates()
                }
            }
        }
}

// Slider 操作
extension CameraViewController {
    
    private func getFractionAttributedString(string: String) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.black])
    }
    
    private func setSliderAttributes(slider: fluid_slider.Slider, minString: String, maxString: String, textForFractionFunc: @escaping (CGFloat) -> (NSAttributedString), triggerFunc: ((fluid_slider.Slider) -> ())?) {
        slider.attributedTextForFraction = textForFractionFunc
        slider.setMinimumLabelAttributedText(NSAttributedString(string: minString, attributes: sliderLabelTextAttributes))
        slider.setMaximumLabelAttributedText(NSAttributedString(string: maxString, attributes: sliderLabelTextAttributes))
        slider.shadowOffset = CGSize(width: 0, height: 0)
        slider.shadowBlur = 0
        slider.shadowColor = UIColor(white: 0, alpha: 0)
        slider.contentViewColor = UIColor(red: 80/255.0, green: 80/255.0, blue: 80/255.0, alpha: 0.35)
        slider.valueViewColor = .systemYellow
        slider.fraction = 0.5
        slider.didBeginTracking = triggerFunc
        slider.didEndTracking = triggerFunc
    }
    
    private func updateLabelPosition(slider: fluid_slider.Slider, fraction: CGFloat, textName: String, textMin: String, textMax: String) {
        // 若不在主线程更新UI将导致程序崩溃
        DispatchQueue.main.async {
            if(fraction < 0.3) {
                slider.setMinimumLabelAttributedText(
                    NSAttributedString(string: textMin, attributes: self.sliderLabelTextAttributes))
                slider.setMaximumLabelAttributedText(
                    NSAttributedString(string: textName, attributes: self.sliderLabelTextAttributes))
            } else {
                slider.setMinimumLabelAttributedText(
                    NSAttributedString(string: textName, attributes: self.sliderLabelTextAttributes))
                slider.setMaximumLabelAttributedText(
                    NSAttributedString(string: textMax, attributes: self.sliderLabelTextAttributes))
            }
        }
    }
    
    private func initFluidSliders() {
        // Tint
        let tintName = "调色", tintMin = "-150", tintMax = "+150"
        setSliderAttributes(slider: tintAdjustSlider, minString: tintName, maxString: tintMax,
                            textForFractionFunc: { fraction in
                                self.updateLabelPosition(slider: self.tintAdjustSlider,
                                                         fraction: fraction,
                                                         textName: tintName, textMin: tintMin, textMax: tintMax)
                                let formatter = NumberFormatter()
                                formatter.maximumIntegerDigits = 3
                                formatter.maximumFractionDigits = 0
                                let num = ((Float(fraction) - 0.5) * 300)
                                let string = (num > 0 ? "+":"") + (formatter.string(from: num as NSNumber) ?? "N/A")
                                return self.getFractionAttributedString(string: string)
        },
                            triggerFunc: { [weak self] _ in
                                // self?.setLabelHidden(false, animated: true)
                                self?.onTintChanged(newTint:
                                    (Float(self?.tintAdjustSlider?.fraction ?? 0) - 0.5) * 300
                                )
        })
        
        // Focus
        let focusName = "对焦", focusMin = "0", focusMax = "1"
        setSliderAttributes(slider: focusAdjustSlider, minString: focusMin, maxString: focusMax,
                            textForFractionFunc: { fraction in
                                self.updateLabelPosition(slider: self.focusAdjustSlider,
                                                         fraction: fraction,
                                                         textName: focusName, textMin: focusMin, textMax: focusMax)
                                let formatter = NumberFormatter()
                                formatter.maximumIntegerDigits = 1
                                formatter.maximumFractionDigits = 1
                                let string = formatter.string(from: fraction as NSNumber) ?? "N/A"
                                return self.getFractionAttributedString(string: string)
        },
                            triggerFunc: { [weak self] _ in
                                self?.onFocusChanged(newFocus: Float(self?.focusAdjustSlider?.fraction ?? 0))
        })
        
        // Shutter
        let device = self.videoDeviceInput.device
        minDurationSeconds = max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), kExposureMinimumDuration)
        // minDurationSeconds += 0.000001
        maxDurationSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        let exposureDurationRange = maxDurationSeconds - minDurationSeconds
        let shutterName = "快门", shutterMin = realNum2fractionString(realNum: minDurationSeconds), shutterMax = realNum2fractionString(realNum: maxDurationSeconds)
        setSliderAttributes(slider: shutterAdjustSlider,
                            minString: shutterMin,
                            maxString: shutterMax,
                            textForFractionFunc: { fraction in
                                self.updateLabelPosition(slider: self.shutterAdjustSlider,
                                                         fraction: fraction, textName: shutterName, textMin: shutterMin, textMax: shutterMax)
                                if fraction <= 0 {
                                    return self.getFractionAttributedString(string: self.realNum2fractionString(realNum: self.minDurationSeconds))
                                }
                                let p = pow(Double(fraction), self.kExposureDurationPower) // Apply power function to expand slider's low-end range
                                let newDurationSeconds = Double(p) * exposureDurationRange + self.minDurationSeconds; // Scale from 0-1 slider range to actual duration
                                return self.getFractionAttributedString(string: self.realNum2fractionString(realNum: newDurationSeconds))
        }, triggerFunc: { [weak self] _ in
            if self != nil && self?.shutterAdjustSlider != nil {
                self?.checkSliderBound(slider: self!.shutterAdjustSlider)
                self?.onShutterChanged(newShutterSliderVal: Float(self?.shutterAdjustSlider?.fraction ?? 1e-06))
            }
        })
        
        // Temp
        let tempFormatter = NumberFormatter()
        tempFormatter.maximumIntegerDigits = 4
        tempFormatter.maximumFractionDigits = 0
        let tempName = "色温", tempMin = "3000", tempMax = "8000"
        setSliderAttributes(slider: tempAdjustSlider, minString: tempMin, maxString: tempMax,
                            textForFractionFunc: { fraction in
                                self.updateLabelPosition(slider: self.tempAdjustSlider,
                                                         fraction: fraction, textName: tempName, textMin: tempMin, textMax: tempMax)
                                let num = (Float(fraction) * 5000) + 3000
                                let string = tempFormatter.string(from: num as NSNumber) ?? "N/A"
                                return self.getFractionAttributedString(string: string)
        },
                            triggerFunc: { [weak self] _ in
                                if self != nil && self?.shutterAdjustSlider != nil {
                                    self?.checkSliderBound(slider: self!.shutterAdjustSlider)
                                    self?.onTempChanged(newTemp: (Float(self?.tempAdjustSlider?.fraction ?? 0) * 5000 + 3000))
                                }
        })
        
        
        // ISO
        let isoName = "ISO"
        let isoFormatter = NumberFormatter()
        isoFormatter.maximumIntegerDigits = 6
        isoFormatter.maximumFractionDigits = 0
        setSliderAttributes(slider: isoAdjustSlider,
                            minString: String(round(self.isoSliderMin)),
                            maxString: String(round(self.isoSliderMax)),
                            textForFractionFunc: { fraction in
                                self.updateLabelPosition(slider: self.isoAdjustSlider,
                                                         fraction: fraction, textName: isoName, textMin: String(round(self.isoSliderMin)), textMax: String(round(self.isoSliderMax)))
                                
                                let num = self.convertSliderValue2IsoValue(sliderVal: Float(fraction))
                                let string = isoFormatter.string(from: num as NSNumber) ?? "N/A"
                                return self.getFractionAttributedString(string: string)
        },
                            triggerFunc: { [weak self] _ in
                                self?.onIsoChanged(newIso: self?.convertSliderValue2IsoValue(sliderVal: Float(self?.isoAdjustSlider?.fraction ?? 0)) ?? 50)
        })
    }
    
    private func convertSliderValue2IsoValue(sliderVal: Float) -> Float {
        return (Float(sliderVal) * (isoSliderMax - isoSliderMin)) + isoSliderMin
    }
    
    private func checkSliderBound(slider: fluid_slider.Slider) {
        if slider.fraction < 0 {
            slider.fraction = 0
        }
        if slider.fraction > 1 {
            slider.fraction = 1
        }
    }
    
    private func realNum2fractionString (realNum: Double) -> String {
        if realNum < 1 && realNum != 0{
            let digits = max(0, 2 + Int(floor(log10(realNum))))
            return String(format: "1/%.*f", digits, 1/realNum)
        } else {
            return String(format: "%.2f", realNum)
        }
    }
    
    private func initSliderLims() {
        guard let device = self.videoDeviceInput?.device
            else {
                print("Couldn't init sliders")
                return
        }
        self.isoSliderMax = device.activeFormat.maxISO
        self.isoSliderMin = device.activeFormat.minISO
        
        // self.tintSlider.isEnabled = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        tintAdjustSlider.isEnabled = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        self.tempAdjustSlider.isEnabled = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        self.tempSliderMin = 3000
        self.tempSliderMax = 8000
        print("isoSliderMax:", isoSliderMax, ";isoSliderMin", isoSliderMin)
        isoAdjustSlider.setMinimumLabelAttributedText(NSAttributedString(string: String(round(self.isoSliderMin)), attributes: sliderLabelTextAttributes))
        isoAdjustSlider.setMaximumLabelAttributedText(NSAttributedString(string: String(round(self.isoSliderMax)), attributes: sliderLabelTextAttributes))
    }
    
    private func updateSliderFractionInMainThread(slider: fluid_slider.Slider, fraction: CGFloat, isAsync: Bool = true) {
        if isAsync {
            DispatchQueue.main.async {
                slider.fraction = fraction
            }
        } else {
            DispatchQueue.main.sync {
                slider.fraction = fraction
            }
        }
    }
    
    private func updateTempSlider(_ currentTemp: Float) {
        self.temperature = currentTemp
        self.updateSliderFractionInMainThread(slider: tempAdjustSlider, fraction: CGFloat((currentTemp - self.tempSliderMin) / 5000))
    }
    
    private func updateTintSlider(_ currentTint: Float) {
        self.tint = currentTint
        //        tintAdjustSlider.fraction =
        self.updateSliderFractionInMainThread(slider: tintAdjustSlider, fraction: CGFloat((currentTint - self.tintSliderMin) / 300))
    }
    
    private func updateFocusSlider(_ currentFocus: Float) {
        self.focus = Double(currentFocus)
        //        focusAdjustSlider.fraction = CGFloat(currentFocus)
        self.updateSliderFractionInMainThread(slider: focusAdjustSlider, fraction: CGFloat(currentFocus))
    }
    
    private func updateShutterSlider (_ currentShutter: CMTime, _ device: AVCaptureDevice) {
        let currentSeconds = currentShutter.seconds
        let minDurationSeconds = max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        
        let range = maxDurationSeconds - minDurationSeconds
        if range == 0 {
            return
        }
        let sliderVal = (currentSeconds - minDurationSeconds) / range
        var p = 0.0
        if sliderVal > 0 && kExposureDurationPower > 0 {
            p = pow(sliderVal, 1/kExposureDurationPower) // Apply power function to expand slider's low-end range
        }
        if p < 0 {
            p = 0
        }
        if p > 1 {
            p = 1
        }
//        print("bf currentSeconds=", currentSeconds, ";sliderVal=", sliderVal)
        // self.shutterAdjustSlider.fraction = CGFloat(p)
        self.shutterDuration = CMTimeMakeWithSeconds(currentSeconds, preferredTimescale: 1000*1000*1000)
        self.updateSliderFractionInMainThread(slider: shutterAdjustSlider, fraction: CGFloat(p))
//        print("aft currentSeconds=", currentSeconds, ";sliderVal=", sliderVal)
    }
    
    private func updateIsoSlider(_ currentIso: Float) {
        // Adjust ISO
        //        isoAdjustSlider.fraction = CGFloat((currentIso - isoSliderMin) / (isoSliderMax - isoSliderMin))
        
        self.iso = currentIso
        self.updateSliderFractionInMainThread(slider: isoAdjustSlider, fraction: CGFloat((currentIso - isoSliderMin) / (isoSliderMax - isoSliderMin)))
    }
    
    private func updateSliders() {
        guard let device = self.videoDeviceInput?.device
            else {
                print("Couldn't update sliders")
                return
        }
        let currentFocus = device.lensPosition
        let currentShutter = device.exposureDuration
        let currentIso = device.iso
        let tempTint = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        
        self.updateFocusSlider(currentFocus)
        self.updateShutterSlider(currentShutter, device)
        self.updateIsoSlider(currentIso)
        self.updateTempSlider(tempTint.temperature)
        self.updateTintSlider(tempTint.tint)
    }
}

// 深度数据回调
extension CameraViewController {
    public func depthPredictionRequestDidComplete(heatmap: MLMultiArray) {
        let convertedHeatmap = DepthPredictor.convertTo2DArray(from: heatmap)
        DispatchQueue.main.async { [weak self] in
            // 显示深度热力图
            self?.depthHeatMap.heatmap = convertedHeatmap
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}


extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}



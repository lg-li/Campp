import Foundation

public enum StatusUpdate {
    case BurstStarted
    case BurstFinished
    case Launch
    case CaptureStarted
    case CaptureProgress
    case CaptureFinished
    case Saving
    case Saved
    
    case Error
}

public enum Slider {
    case iso
    case shutterDuration
    case focus
}

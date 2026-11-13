import ARKit
import AVFoundation

/// The phone's flashlight, driven through the same camera ARKit is using so
/// tracking keeps working in the dark.
enum Torch {
    static var device: AVCaptureDevice? {
        ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera
            ?? AVCaptureDevice.default(for: .video)
    }

    static var available: Bool { device?.hasTorch == true }

    /// Returns true when the torch is now in the requested state.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard let d = device, d.hasTorch else { return false }
        do {
            try d.lockForConfiguration()
            defer { d.unlockForConfiguration() }
            if on {
                try d.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                d.torchMode = .off
            }
            return true
        } catch {
            print("Site Tape: torch failed: \(error)")
            return false
        }
    }
}

import AVFoundation
import SwiftUI

enum CameraFlashMode: CaseIterable, Sendable, Equatable {
    case off
    case auto
    case on

    var next: CameraFlashMode {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var systemImageName: String {
        switch self {
        case .off: return "bolt.slash"
        case .auto: return "bolt"
        case .on: return "bolt.fill"
        }
    }

    var accessibilityLabelKey: LocalizedStringKey {
        switch self {
        case .off: return "camera_flash_off_a11y"
        case .auto: return "camera_flash_auto_a11y"
        case .on: return "camera_flash_on_a11y"
        }
    }
}

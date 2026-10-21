//
//  TorchMode.swift
//  SwiftScanKit
//
//  Created by Jason on 2018/11/29.
//  Copyright © 2018 Jason. All rights reserved.
//

import AVFoundation
import UIKit

enum TorchMode: Sendable {
    case on
    case off
    
    /// Torch mode image.
    @MainActor var image: UIImage {
        switch self {
        case .on:
            return imageNamed("flashOn")
        case .off:
            return imageNamed("flashOff")
        }
    }
    
    /// Returns `AVCaptureTorchMode` value.
    var captureTorchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .on:
            return .on
        case .off:
            return .off
        }
    }
}


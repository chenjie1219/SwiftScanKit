# SwiftScanKit

**English** · [简体中文](README.zh-CN.md)

Native QR and barcode scanning and image generation for iOS, with no third-party runtime dependencies.

## Features

- Scan QR codes and barcodes with a ready-to-use UIKit controller.
- Choose framed or full-screen scanning with line or grid animations.
- Customize colors, hints and supported code types; use the low-light torch control.
- Generate QR codes with optional logos and Code 128 images.

**Requirements:** iOS 15+ · Swift 6.4 · Xcode 27.1+

## Installation

### Swift Package Manager

Add the package in Xcode and select the **SwiftScanKit** product, or declare:

```swift
.package(url: "https://github.com/chenjie1219/SwiftScanKit.git", from: "2.0.0")
```

### CocoaPods

```ruby
pod 'SwiftScanKit', '~> 2.0'
```

Run `pod install` and open the generated `.xcworkspace`. Both options use `import SwiftScanKit`.

## Camera permission

Add a camera usage description to your app’s `Info.plist`. Scanning requires a physical device.

```xml
<key>NSCameraUsageDescription</key>
<string>Use the camera to scan QR codes and barcodes.</string>
```

## Scanning

From a view controller with a navigation controller:

```swift
import UIKit
import SwiftScanKit

let scanner = ScannerVC()
scanner.title = "Scan"
scanner.onScan = { [weak self] code in
    print(code)
    self?.navigationController?.popViewController(animated: true)
}
scanner.onError = { error in
    print(error.localizedDescription)
}
navigationController?.pushViewController(scanner, animated: true)
```

Use `scanner.scanRegion = .fullScreen` for full-screen scanning, or keep the default framed region. Set `scanner.animationStyle = .grid` for the grid animation.

Each scan returns one result and stops. To scan again on the same screen, call `scanner.restartScanning()`.

## Image generation

```swift
let qr = UIImage.generateQRCode("https://example.com", 900)
let barcode = UIImage.generateCode128("123456789", CGSize(width: 900, height: 300))
```

Dimensions are output pixels. Both methods return an optional `UIImage`.

## Demo

Open `SwiftScanKit.xcodeproj` and run the **SwiftScanKitDemo** scheme to try scanning styles and image generation.

## License

[MIT](LICENSE)

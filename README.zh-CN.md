# SwiftScanKit

[English](README.md) · **简体中文**

iOS 原生二维码、条形码扫描与图片生成组件，无第三方运行时依赖。

## 特性

- 使用 UIKit 扫描控制器，快速接入二维码和条形码识别。
- 支持框内、全屏扫描，以及线条、网格动画。
- 自定义颜色、提示和识别码制，暗光下可使用手电筒。
- 生成带可选 Logo 的二维码及 Code 128 条形码。

**环境要求：** iOS 15+ · Swift 6.4 · Xcode 27.1+

## 安装

### Swift Package Manager

在 Xcode 中添加包并选择 **SwiftScanKit** 产品，或声明：

```swift
.package(url: "https://github.com/chenjie1219/SwiftScanKit.git", from: "2.0.0")
```

### CocoaPods

```ruby
pod 'SwiftScanKit', '~> 2.0'
```

执行 `pod install` 并打开生成的 `.xcworkspace`。两种方式均使用 `import SwiftScanKit`。

## 相机权限

在应用的 `Info.plist` 中添加相机用途说明。扫码需要使用真机。

```xml
<key>NSCameraUsageDescription</key>
<string>使用相机识别二维码和条形码。</string>
```

## 扫码

在包含导航控制器的页面中使用：

```swift
import UIKit
import SwiftScanKit

let scanner = ScannerVC()
scanner.title = "扫一扫"
scanner.onScan = { [weak self] code in
    print(code)
    self?.navigationController?.popViewController(animated: true)
}
scanner.onError = { error in
    print(error.localizedDescription)
}
navigationController?.pushViewController(scanner, animated: true)
```

设置 `scanner.scanRegion = .fullScreen` 使用全屏识别，默认使用框内识别。设置 `scanner.animationStyle = .grid` 使用网格动画。

每轮识别返回一个结果后停止。在当前页面继续扫描时，调用 `scanner.restartScanning()`。

## 生成图片

```swift
let qr = UIImage.generateQRCode("https://example.com", 900)
let barcode = UIImage.generateCode128("123456789", CGSize(width: 900, height: 300))
```

尺寸单位为输出像素，两种方法均返回可选的 `UIImage`。

## 示例

打开 `SwiftScanKit.xcodeproj`，运行 **SwiftScanKitDemo** scheme，体验扫码样式与图片生成。

## 许可证

[MIT](LICENSE)

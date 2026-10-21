import CoreImage.CIFilterBuiltins
import UIKit

extension UIImage {
    /// Generates an opaque QR image with a white quiet zone and high error correction.
    ///
    /// `width` is the output width in pixels, rounded down. Modules always occupy whole
    /// pixels. Returns `nil` for empty/oversized messages, dimensions that cannot fit
    /// the code, or images exceeding 8,192 pixels per side or 16,777,216 total pixels.
    /// Logos retain their aspect ratio and occupy at most one fifth of the symbol.
    public class func generateQRCode(
        _ text: String,
        _ width: CGFloat,
        _ fillImage: UIImage? = nil,
        _ color: UIColor? = nil
    ) -> UIImage? {
        guard !text.isEmpty, text.utf8.count <= 3_057,
              let size = CodeImageRenderer.pixelSize(CGSize(width: width, height: width)) else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }

        return CodeImageRenderer.render(
            output, size: size, color: color ?? .black, quietZone: 4,
            squareModules: true, logo: fillImage
        )
    }

    /// Generates an opaque Code 128 image with a white quiet zone.
    ///
    /// Code 128 accepts ASCII text. Non-ASCII input returns `nil` instead of encoding
    /// unrelated UTF-8 bytes. `size` uses pixels, rounded down; bars use whole pixels.
    /// Invalid sizes, insufficient width and the same bitmap limits as QR return `nil`.
    public class func generateCode128(
        _ text: String,
        _ size: CGSize,
        _ color: UIColor? = nil
    ) -> UIImage? {
        guard !text.isEmpty, let pixels = CodeImageRenderer.pixelSize(size),
              text.utf8.count <= Int(pixels.width),
              let data = text.data(using: .ascii, allowLossyConversion: false) else {
            return nil
        }

        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = data
        filter.quietSpace = 0
        filter.barcodeHeight = 1
        guard let output = filter.outputImage else { return nil }

        return CodeImageRenderer.render(
            output, size: pixels, color: color ?? .black, quietZone: 10,
            squareModules: false
        )
    }
}

private enum CodeImageRenderer {
    // CIContext is thread-safe. Mutable filters and bitmap contexts belong to each call.
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let maximumDimension: CGFloat = 8_192
    private static let maximumPixels: CGFloat = 16_777_216

    static func pixelSize(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1 else {
            return nil
        }
        let pixels = CGSize(width: size.width.rounded(.down), height: size.height.rounded(.down))
        guard pixels.width <= maximumDimension, pixels.height <= maximumDimension,
              pixels.width * pixels.height <= maximumPixels else { return nil }
        return pixels
    }

    static func render(
        _ image: CIImage,
        size: CGSize,
        color: UIColor,
        quietZone: CGFloat,
        squareModules: Bool,
        logo: UIImage? = nil
    ) -> UIImage? {
        let extent = image.extent.integral
        guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite else { return nil }

        let scale = (size.width / (extent.width + quietZone * 2)).rounded(.down)
        guard scale >= 1 else { return nil }

        let symbolSize = CGSize(
            width: extent.width * scale,
            height: squareModules ? extent.height * scale : size.height
        )
        guard symbolSize.height <= size.height else { return nil }
        let symbolRect = CGRect(
            x: ((size.width - symbolSize.width) / 2).rounded(.down),
            y: ((size.height - symbolSize.height) / 2).rounded(.down),
            width: symbolSize.width, height: symbolSize.height
        )

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let tint = CIFilter.falseColor()
        tint.inputImage = image
        tint.color0 = CIColor(red: red, green: green, blue: blue, alpha: alpha)
        tint.color1 = CIColor.white

        guard let coloredImage = tint.outputImage,
              let source = context.createCGImage(coloredImage, from: extent),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        bitmap.setFillColor(UIColor.white.cgColor)
        bitmap.fill(CGRect(origin: .zero, size: size))
        bitmap.interpolationQuality = .none
        bitmap.setShouldAntialias(false)
        bitmap.draw(source, in: symbolRect)

        if let logo, logo.size.width > 0, logo.size.height > 0,
           logo.size.width.isFinite, logo.size.height.isFinite {
            drawLogo(logo, in: bitmap, canvasHeight: size.height, symbol: symbolRect, moduleSize: scale)
        }

        guard let rendered = bitmap.makeImage() else { return nil }
        return UIImage(cgImage: rendered, scale: 1, orientation: .up)
    }

    private static func drawLogo(
        _ logo: UIImage,
        in bitmap: CGContext,
        canvasHeight: CGFloat,
        symbol: CGRect,
        moduleSize: CGFloat
    ) {
        let side = (symbol.width / 5 / moduleSize).rounded(.down) * moduleSize
        guard side > moduleSize * 2 else { return }
        let backing = CGRect(
            x: (symbol.midX - side / 2).rounded(.down),
            y: (symbol.midY - side / 2).rounded(.down),
            width: side, height: side
        )
        let content = backing.insetBy(dx: moduleSize, dy: moduleSize)
        let ratio = min(content.width / logo.size.width, content.height / logo.size.height)
        let logoSize = CGSize(width: logo.size.width * ratio, height: logo.size.height * ratio)
        let logoRect = CGRect(
            x: content.midX - logoSize.width / 2,
            y: content.midY - logoSize.height / 2,
            width: logoSize.width, height: logoSize.height
        )

        bitmap.saveGState()
        defer { bitmap.restoreGState() }
        // UIImage drawing uses UIKit's top-left coordinate system, including orientation.
        bitmap.translateBy(x: 0, y: canvasHeight)
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.setFillColor(UIColor.white.cgColor)
        bitmap.fill(backing)
        bitmap.interpolationQuality = .high
        UIGraphicsPushContext(bitmap)
        defer { UIGraphicsPopContext() }
        logo.draw(in: logoRect)
    }
}

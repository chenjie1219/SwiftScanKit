import AVFoundation

extension AVMetadataObject.ObjectType {
    /// Machine-readable formats only. Limit the scanner's metadata to your own use case when possible.
    public static let supportedBarcodeTypes: [AVMetadataObject.ObjectType] = {
        var types: [AVMetadataObject.ObjectType] = [
            .aztec, .code128, .code39, .code39Mod43, .code93, .dataMatrix,
            .ean13, .ean8, .interleaved2of5, .itf14, .pdf417, .qr, .upce
        ]
        if #available(iOS 15.4, *) {
            types += [.codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited, .microQR, .microPDF417]
        }
        return types
    }()
}

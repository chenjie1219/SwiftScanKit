import AVFoundation
import Vision

/// Supplemental decoding for linear barcodes, with immutable capabilities shared across requests.
final class BarcodeDecoder: Sendable {
    struct Configuration: Sendable {
        let metadataTypes: [VNBarcodeSymbology: AVMetadataObject.ObjectType]
        let symbologies: [VNBarcodeSymbology]
    }

    struct Result: Sendable {
        let value: String
        let type: AVMetadataObject.ObjectType
    }

    // Retaining a capture buffer preserves its storage until Vision finishes; neither queue mutates it.
    private struct Frame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
    }

    private static let symbologiesByType: [AVMetadataObject.ObjectType: VNBarcodeSymbology] = {
        var types: [AVMetadataObject.ObjectType: VNBarcodeSymbology] = [
            .code128: .code128, .code39: .code39, .code39Mod43: .code39Checksum,
            .code93: .code93, .ean13: .ean13, .ean8: .ean8, .upce: .upce,
            .interleaved2of5: .i2of5, .itf14: .itf14
        ]
        if #available(iOS 15.4, *) {
            types[.codabar] = .codabar
            types[.gs1DataBar] = .gs1DataBar
            types[.gs1DataBarExpanded] = .gs1DataBarExpanded
            types[.gs1DataBarLimited] = .gs1DataBarLimited
        }
        return types
    }()

    private let queue = DispatchQueue(label: "com.swiftscankit.barcode", qos: .userInitiated)
    private let revision: Int
    private let supportedSymbologies: Set<VNBarcodeSymbology>

    init() {
        let request = VNDetectBarcodesRequest()
        revision = VNDetectBarcodesRequest.supportedRevisions.last ?? VNDetectBarcodesRequest.currentRevision
        request.revision = revision
        supportedSymbologies = Set((try? request.supportedSymbologies()) ?? [])
    }

    static func supportsAny(of metadataTypes: [AVMetadataObject.ObjectType]) -> Bool {
        metadataTypes.contains { symbologiesByType[$0] != nil }
    }

    func configuration(for metadataTypes: [AVMetadataObject.ObjectType]) -> Configuration? {
        var types: [VNBarcodeSymbology: AVMetadataObject.ObjectType] = [:]
        for type in metadataTypes {
            if let symbology = Self.symbologiesByType[type], supportedSymbologies.contains(symbology) {
                types[symbology] = type
            }
        }
        return types.isEmpty ? nil : Configuration(metadataTypes: types, symbologies: Array(types.keys))
    }

    /// The owner admits at most one request at a time. The buffer is unrotated and unmirrored.
    func decode(_ pixelBuffer: CVPixelBuffer, region: CGRect, configuration: Configuration,
                completion: @escaping @Sendable (Result?) -> Void) {
        let frame = Frame(pixelBuffer: pixelBuffer)
        queue.async { [self] in
            let result: Result? = autoreleasepool {
                let request = VNDetectBarcodesRequest()
                // Assign revision first: changing it resets the requested symbologies.
                request.revision = revision
                request.symbologies = configuration.symbologies
                // AV metadata uses a top-left origin; Vision's natural-image ROI uses a bottom-left origin.
                request.regionOfInterest = CGRect(x: region.minX, y: 1 - region.maxY,
                                                  width: region.width, height: region.height)
                let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: .up, options: [:])
                do { try handler.perform([request]) }
                catch { return nil }
                for observation in request.results ?? [] {
                    if let value = observation.payloadStringValue, !value.isEmpty,
                       let type = configuration.metadataTypes[observation.symbology] {
                        return Result(value: value, type: type)
                    }
                }
                return nil
            }
            completion(result)
        }
    }
}

import UIKit
import SwiftScanKit

final class GenerateCodeVC: UIViewController {
    @IBOutlet weak var QRCodeView: UIImageView!
    @IBOutlet weak var barCodeView: UIImageView!
    private var generationTask: Task<Void, Never>?
    private var renderedSize = CGSize.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        for imageView in [QRCodeView, barCodeView].compactMap({ $0 }) {
            imageView.contentMode = .scaleAspectFit
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = traitCollection.displayScale
        let size = CGSize(width: (QRCodeView.bounds.width * scale).rounded(.down),
                          height: (barCodeView.bounds.height * scale).rounded(.down))
        guard size.width > 0, size.height > 0, renderedSize != size else { return }
        renderedSize = size
        generationTask?.cancel()
        let logo = UIImage(named: "avatar")
        let barcodeWidth = (barCodeView.bounds.width * scale).rounded(.down)
        generationTask = Task { [weak self] in
            let images = await Self.generateImages(size: size, barcodeWidth: barcodeWidth, logo: logo)
            guard !Task.isCancelled, let self else { return }
            QRCodeView.image = images.0
            barCodeView.image = images.1
        }
    }

    @concurrent
    private nonisolated static func generateImages(size: CGSize, barcodeWidth: CGFloat,
                                                   logo: UIImage?) async -> (UIImage?, UIImage?) {
        guard !Task.isCancelled else { return (nil, nil) }
        let qr = UIImage.generateQRCode("https://u.wechat.com/EOgrqGHTuducITFPPMgka4M", size.width, logo, .orange)
        guard !Task.isCancelled else { return (nil, nil) }
        let barcode = UIImage.generateCode128("4234115", CGSize(width: barcodeWidth, height: size.height), .blue)
        return (qr, barcode)
    }

    deinit { generationTask?.cancel() }
}

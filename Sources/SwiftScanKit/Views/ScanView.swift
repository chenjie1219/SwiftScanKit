import UIKit

/// The detection area is independent of the scanning line's visual path.
public enum ScanRegion: Sendable {
    case scanFrame
    case fullScreen
}

/// Camera overlay and the source of the camera's visible region of interest.
final class ScanView: UIView {
    var scanRegion: ScanRegion = .scanFrame { didSet { updateAppearance() } }
    var animationStyle: ScanAnimationStyle = .default { didSet { updateAppearance() } }
    var color: UIColor = .red { didSet { updateColors() } }
    var tips = "" { didSet { tipsLabel.text = tips; setNeedsLayout() } }
    var onScanRectChange: (() -> Void)?
    private(set) var scanRect = CGRect.zero

    private let contentView = UIView()
    private let dimmingLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let cornersLayer = CAShapeLayer()
    private let animationImageView = UIImageView()
    private let scanBand = ScanBand()
    private let tipsLabel = UILabel()
    private let animation = ScanAnimation()
    private var wantsAnimation = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.lineWidth = 0.2
        cornersLayer.fillColor = UIColor.clear.cgColor
        cornersLayer.lineWidth = 2
        [dimmingLayer, borderLayer, cornersLayer].forEach(layer.addSublayer)
        contentView.clipsToBounds = true
        addSubview(contentView)
        contentView.addSubview(animationImageView)
        animationImageView.layer.addSublayer(scanBand.layer)
        tipsLabel.textColor = .white
        tipsLabel.font = .preferredFont(forTextStyle: .footnote)
        tipsLabel.adjustsFontForContentSizeCategory = true
        tipsLabel.numberOfLines = 0
        tipsLabel.textAlignment = .center
        addSubview(tipsLabel)
        if #available(iOS 17, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
                (self: Self, _: UITraitCollection) in self.updateColors()
            }
        }
        updateAppearance()
        updateColors()
    }

    private func updateAppearance() {
        let showsBand = scanRegion == .fullScreen && animationStyle == .grid
        animationImageView.image = showsBand ? nil : imageNamed(animationStyle == .grid ? "ScanNet" : "ScanLine")
            .withRenderingMode(.alwaysTemplate)
        scanBand.layer.isHidden = !showsBand
        setNeedsLayout()
    }

    private func updateColors() {
        let resolved = color.resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornersLayer.strokeColor = resolved.cgColor
        animationImageView.tintColor = color
        scanBand.updateColor(resolved)
        CATransaction.commit()
    }

    @available(iOS, introduced: 15, deprecated: 17, message: "Color appearance changes use trait registration on iOS 17 and later.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { updateColors() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = bounds.inset(by: safeAreaInsets)
        let tipsHeight = tips.isEmpty ? 0 : min(
            tipsLabel.sizeThatFits(CGSize(width: max(0, available.width - 32), height: .greatestFiniteMagnitude)).height,
            max(0, available.height / 3)
        )
        let reservedHeight: CGFloat = tips.isEmpty ? 0 : tipsHeight + 20
        let side = max(0, min(available.width * 0.6, available.height - reservedHeight))
        let showsScanFrame = scanRegion == .scanFrame
        let rect = showsScanFrame
            ? CGRect(x: available.midX - side / 2, y: available.minY + (available.height - reservedHeight - side) / 2,
                     width: side, height: side)
            : bounds
        let geometryChanged = scanRect != rect
        scanRect = rect
        let travel = showsScanFrame ? scanRect.height : max(0, min(300, available.height * 0.4))
        let imageHeight: CGFloat
        if animationStyle == .default { imageHeight = 12 }
        else if showsScanFrame { imageHeight = scanRect.height }
        else { imageHeight = min(64, travel * 0.45) }
        let animationRect: CGRect
        if showsScanFrame {
            animationRect = scanRect
        } else {
            let width = max(0, available.width * 0.88)
            // Center the visible line, accounting for the grid's upward trailing band.
            let lineOffset = animationStyle == .grid ? imageHeight - 0.5 : imageHeight / 2
            animationRect = CGRect(x: bounds.midX - width / 2, y: bounds.midY - travel / 2 - lineOffset,
                                   width: width, height: travel + imageHeight)
        }
        let animationGeometryChanged = contentView.frame != animationRect

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimmingLayer.isHidden = !showsScanFrame
        borderLayer.isHidden = !showsScanFrame
        cornersLayer.isHidden = !showsScanFrame
        if showsScanFrame && (geometryChanged || dimmingLayer.path?.boundingBox != bounds) {
            let dimming = UIBezierPath(rect: bounds)
            dimming.append(UIBezierPath(rect: scanRect))
            dimmingLayer.path = dimming.cgPath
            borderLayer.path = UIBezierPath(rect: scanRect).cgPath
            cornersLayer.path = cornerPath()
        }
        contentView.frame = animationRect
        let tipsY = showsScanFrame ? scanRect.maxY + 20 : max(available.minY, available.maxY - tipsHeight - 24)
        tipsLabel.frame = CGRect(x: available.minX + 16, y: tipsY,
                                 width: max(0, available.width - 32), height: tipsHeight)
        CATransaction.commit()

        let imageFrame = CGRect(x: 0, y: showsScanFrame ? -imageHeight - 20 : 0,
                                width: animationRect.width, height: imageHeight)
        if animationGeometryChanged || animationImageView.frame != imageFrame {
            animation.stop(on: animationImageView.layer)
            animationImageView.frame = imageFrame
        }
        if !showsScanFrame && animationStyle == .grid { scanBand.updateSize(imageFrame.size) }
        if wantsAnimation && window != nil {
            animation.start(on: animationImageView.layer,
                            distance: showsScanFrame ? travel + imageHeight + 40 : travel,
                            duration: showsScanFrame ? 2 : 3.6, fadesAtEnds: !showsScanFrame)
        }
        if geometryChanged { onScanRectChange?() }
    }

    private func cornerPath() -> CGPath {
        let rect = scanRect
        let length = min(20, max(0, rect.width / 2))
        let path = CGMutablePath()
        for (x, y, dx, dy) in [(rect.minX, rect.minY, CGFloat(1), CGFloat(1)),
                               (rect.maxX, rect.minY, -1, 1),
                               (rect.minX, rect.maxY, 1, -1),
                               (rect.maxX, rect.maxY, -1, -1)] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            animation.stop(on: animationImageView.layer)
        } else {
            updateColors()
            setNeedsLayout()
        }
    }

    func startAnimation() {
        wantsAnimation = true
        setNeedsLayout()
    }

    func stopAnimation() {
        wantsAnimation = false
        animation.stop(on: animationImageView.layer)
    }
}

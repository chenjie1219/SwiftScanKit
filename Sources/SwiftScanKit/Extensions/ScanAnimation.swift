import UIKit

/// Core Animation drives each overlay independently without a main-thread display link.
@MainActor
final class ScanAnimation {
    private let key = "SwiftScanKit.scan"

    func start(on layer: CALayer, distance: CGFloat, duration: CFTimeInterval = 2, fadesAtEnds: Bool = false) {
        guard distance > 0 else { return }
        if let current = layer.animation(forKey: key),
           current.duration == duration,
           (current is CAAnimationGroup) == fadesAtEnds {
            let movement = (current as? CABasicAnimation)
                ?? ((current as? CAAnimationGroup)?.animations?.first as? CABasicAnimation)
            if (movement?.toValue as? NSNumber)?.doubleValue == Double(distance) { return }
        }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 0
        animation.toValue = distance
        animation.duration = duration
        let repeating: CAAnimation
        if fadesAtEnds {
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.08, 0.92, 1]
            opacity.duration = duration
            let group = CAAnimationGroup()
            group.animations = [animation, opacity]
            group.duration = duration
            repeating = group
        } else {
            repeating = animation
        }
        repeating.repeatCount = .infinity
        repeating.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(repeating, forKey: key)
    }

    func stop(on layer: CALayer) {
        layer.removeAnimation(forKey: key)
    }
}

/// A short square grid and its leading edge, rendered entirely by Core Animation.
@MainActor
final class ScanBand {
    let layer = CALayer()
    private let glow = CAGradientLayer()
    private let grid = CAShapeLayer()
    private let gridFade = CAGradientLayer()
    private let edge = CALayer()
    private let horizontalFade = CAGradientLayer()
    private var previousSize = CGSize.zero

    init() {
        layer.masksToBounds = true
        layer.addSublayer(glow)
        layer.addSublayer(grid)
        layer.addSublayer(edge)
        layer.mask = horizontalFade
        grid.fillColor = nil
        grid.lineWidth = 0.5
        grid.mask = gridFade
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.locations = [0, 0.4, 0.8, 1]
        gridFade.startPoint = CGPoint(x: 0.5, y: 0)
        gridFade.endPoint = CGPoint(x: 0.5, y: 1)
        gridFade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.08).cgColor,
                           UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.black.cgColor]
        gridFade.locations = [0, 0.2, 0.7, 1]
        horizontalFade.startPoint = CGPoint(x: 0, y: 0.5)
        horizontalFade.endPoint = CGPoint(x: 1, y: 0.5)
        horizontalFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor,
                                UIColor.black.cgColor, UIColor.clear.cgColor]
        horizontalFade.locations = [0, 0.14, 0.86, 1]
    }

    func updateColor(_ color: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let alpha = color.cgColor.alpha
        glow.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(alpha * 0.015).cgColor,
                       color.withAlphaComponent(alpha * 0.1).cgColor, color.withAlphaComponent(alpha * 0.28).cgColor]
        grid.strokeColor = color.withAlphaComponent(alpha * 0.58).cgColor
        edge.backgroundColor = color.cgColor
    }

    func updateSize(_ proposedSize: CGSize) {
        let size = proposedSize.width.isFinite && proposedSize.height.isFinite && proposedSize.width > 0 && proposedSize.height > 0
            ? proposedSize : .zero
        guard size != previousSize else { return }
        previousSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.frame = CGRect(origin: .zero, size: size)
        guard size != .zero else { grid.path = nil; return }
        glow.frame = layer.bounds
        grid.frame = layer.bounds
        gridFade.frame = layer.bounds
        horizontalFade.frame = layer.bounds
        edge.frame = CGRect(x: 0, y: max(0, size.height - 1), width: size.width, height: 1)
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 1))
            x += 4
        }
        var y = size.height - 1
        while y >= 0 {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y -= 4
        }
        grid.path = path
    }
}

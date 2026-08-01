// DictusKeyboard/Vendored/Views/KeyOverlayView.swift
// Vendored from giellakbd-ios Keyboard/Views/KeyOverlayView.swift
// Stripped: No external dependencies to remove

import UIKit

@MainActor
final class KeyOverlayView: UIView {
    private class KeyOverlayShadowView: UIView {}

    private let ghostKeyView: GhostKeyView
    private let theme: Theme

    let overlayContentView: UIView
    private var shadowView: KeyOverlayShadowView?

    private var path: CGPath!

    init(ghostKeyView: GhostKeyView, key: KeyDefinition, theme: Theme) {
        self.ghostKeyView = ghostKeyView

        self.theme = theme
        overlayContentView = UIView(frame: ghostKeyView.bounds)
        overlayContentView.clipsToBounds = false
        overlayContentView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect(x: 0, y: 0, width: ghostKeyView.frame.width, height: ghostKeyView.frame.height * 2))
        self.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        addSubview(overlayContentView)

        overlayContentView.topAnchor
            .constraint(equalTo: topAnchor, constant: theme.popupCornerRadius)
            .enable(priority: .required)

        overlayContentView.bottomAnchor
            .constraint(greaterThanOrEqualTo: bottomAnchor, constant: -ghostKeyView.frame.height - theme.popupCornerRadius)
            .enable(priority: .defaultHigh)

        overlayContentView.leftAnchor
            .constraint(equalTo: leftAnchor, constant: theme.popupCornerRadius)
            .enable(priority: .required)

        overlayContentView.rightAnchor
            .constraint(equalTo: rightAnchor, constant: -theme.popupCornerRadius)
            .enable(priority: .required)

        overlayContentView.heightAnchor
            .constraint(greaterThanOrEqualToConstant: ghostKeyView.frame.height - theme.popupCornerRadius * 2)
            .enable(priority: .defaultHigh)

        overlayContentView.widthAnchor
            .constraint(greaterThanOrEqualToConstant: ghostKeyView.frame.width)
            .enable(priority: .required)

        overlayContentView.backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    func addShadow() {
        guard self.shadowView == nil else { return }
        guard let superview = self.superview else { return }

        let shadowView = KeyOverlayShadowView()
        self.shadowView = shadowView
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.backgroundColor = UIColor.black
        superview.insertSubview(shadowView, belowSubview: self)

        shadowView.fill(superview: overlayContentView)
        shadowView.layer.shadowColor = UIColor(white: 0.0, alpha: 1.0).cgColor
        shadowView.layer.shadowOffset = CGSize(width: 0, height: theme.popupCornerRadius / 2.0)
        shadowView.layer.shadowOpacity = 1.0
        shadowView.layer.shadowRadius = 12.0
        shadowView.clipsToBounds = false
    }

    override func didMoveToSuperview() {
        shadowView?.removeFromSuperview()
        shadowView = nil

        addShadow()
        super.didMoveToSuperview()
    }

    override func removeFromSuperview() {
        shadowView?.removeFromSuperview()
        super.removeFromSuperview()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: CGRect) {
        guard self.superview != nil else { return }

        let path = createPath()
        let bezier = UIBezierPath(cgPath: path)

        theme.popupColor.setFill()
        bezier.fill()
        theme.popupBorderColor.setStroke()
        bezier.stroke()

        let mask = CAShapeLayer()
        mask.path = path
        layer.mask = mask
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    fileprivate struct PopupPathPoint {
        let radius: CGFloat
        let point: CGPoint
    }

    func createPath() -> CGPath {
        let points = getOverlayPoints()
        let path = CGMutablePath()

        path.move(to: CGPoint(x: frame.midX, y: 0.0))
        for (index, point) in points.enumerated() where index < points.count - 1 {
            path.addArc(tangent1End: point.point, tangent2End: points[index + 1].point, radius: point.radius)
        }
        path.closeSubpath()

        return path
    }

    private func getOverlayPoints() -> [PopupPathPoint] {
        let bubbleHeight = overlayContentView.frame.height + theme.popupCornerRadius * 2

        let topCenter = CGPoint(x: self.bounds.midX, y: 0.0).withRadius(theme.popupCornerRadius)
        let topLeft = CGPoint.zero.withRadius(theme.popupCornerRadius)

        let letterBottomLeft = CGPoint(x: 0, y: bubbleHeight).withRadius(theme.popupCornerRadius)
        let letterBottomRight = CGPoint(x: self.frame.width, y: bubbleHeight).withRadius(theme.popupCornerRadius)

        let topRight = CGPoint(x: self.frame.width, y: 0.0).withRadius(theme.popupCornerRadius)

        let shouldShowRoundedRect = self.bounds.maxY < bubbleHeight
        let shouldShowRegularBubble = bounds.width < ghostKeyView.frame.width * 2

        let contentViewFrameInKeyboardView = ghostKeyView.convert(ghostKeyView.contentView.frame, to: superview)

        if shouldShowRoundedRect {
            return [
                topCenter,
                topLeft,
                letterBottomLeft,
                letterBottomRight,
                topRight,
                topCenter
            ]
        } else if shouldShowRegularBubble {
            let y = overlayContentView.frame.height + theme.popupCornerRadius * 3

            let keyTopLeft = CGPoint(x: contentViewFrameInKeyboardView.minX - frame.minX, y: y).withRadius(theme.popupCornerRadius)
            let keyTopRight = CGPoint(x: contentViewFrameInKeyboardView.maxX - frame.minX, y: y).withRadius(theme.popupCornerRadius)
            let bottomLeft = CGPoint(x: contentViewFrameInKeyboardView.minX - frame.minX, y: self.bounds.maxY).withRadius(theme.keyCornerRadius)
            let bottomRight = CGPoint(x: contentViewFrameInKeyboardView.maxX - frame.minX, y: self.bounds.maxY).withRadius(theme.keyCornerRadius)

            return [
                topCenter,
                topLeft,
                letterBottomLeft,
                keyTopLeft,
                bottomLeft,
                bottomRight,
                keyTopRight,
                letterBottomRight,
                topRight,
                topCenter
            ]
        } else {
            var bubbleConnectionCornerRadius: CGFloat = theme.popupCornerRadius
            var keyRadius: CGFloat = theme.keyCornerRadius

            let spaceBetweenBubbleBottomAndKeyBottom = self.frame.height - bubbleHeight

            if spaceBetweenBubbleBottomAndKeyBottom < 0 {
                // Unexpected; do nothing.
            } else if spaceBetweenBubbleBottomAndKeyBottom <= keyRadius {
                bubbleConnectionCornerRadius = 0
                keyRadius = spaceBetweenBubbleBottomAndKeyBottom
            } else if spaceBetweenBubbleBottomAndKeyBottom < keyRadius + bubbleConnectionCornerRadius {
                bubbleConnectionCornerRadius = spaceBetweenBubbleBottomAndKeyBottom - keyRadius
            }

            let leftRadius = contentViewFrameInKeyboardView.minX - frame.minX < theme.popupCornerRadius
                ? 0
                : theme.popupCornerRadius
            let rightRadius = contentViewFrameInKeyboardView.maxX - frame.minX > self.frame.width - theme.popupCornerRadius
                ? 0
                : theme.popupCornerRadius
            return [
                topCenter,
                topLeft,
                CGPoint(x: 0, y: bubbleHeight).withRadius(leftRadius),
                CGPoint(x: contentViewFrameInKeyboardView.minX - frame.minX, y: bubbleHeight).withRadius(bubbleConnectionCornerRadius),
                CGPoint(x: contentViewFrameInKeyboardView.minX - frame.minX, y: self.bounds.maxY).withRadius(keyRadius),
                CGPoint(x: contentViewFrameInKeyboardView.maxX - frame.minX, y: self.bounds.maxY).withRadius(keyRadius),
                CGPoint(x: contentViewFrameInKeyboardView.maxX - frame.minX, y: bubbleHeight).withRadius(bubbleConnectionCornerRadius),
                CGPoint(x: self.frame.width, y: bubbleHeight).withRadius(rightRadius),
                topRight,
                topCenter
            ]
        }
    }
}

private extension CGPoint {
    func withRadius(_ radius: CGFloat) -> KeyOverlayView.PopupPathPoint {
        return KeyOverlayView.PopupPathPoint(radius: radius, point: self)
    }
}

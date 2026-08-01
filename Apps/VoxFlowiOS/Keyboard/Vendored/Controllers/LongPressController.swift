// DictusKeyboard/Vendored/Controllers/LongPressController.swift
// Vendored from giellakbd-ios Keyboard/Controllers/LongPressController.swift
// Stripped: Bundle.top reference replaced with Bundle.main for image loading

import UIKit
import Shared

@MainActor
protocol LongPressOverlayDelegate: AnyObject {
    func longpress(didCreateOverlayContentView contentView: UIView)
    func longpressDidCancel()
    func longpress(didSelectKey key: KeyDefinition)

    func longpressFrameOfReference() -> CGRect
    func longpressKeySize() -> CGSize
}

@MainActor
protocol LongPressCursorMovementDelegate: AnyObject {
    func longpress(movedCursor: Int)
    func longpressDidCancel()
}

@MainActor
protocol LongPressBehaviorProvider {
    func touchesBegan(_ point: CGPoint)
    func touchesMoved(_ point: CGPoint)
    func touchesEnded(_ point: CGPoint)
}

@MainActor
final class LongPressCursorMovementController: NSObject, LongPressBehaviorProvider {
    public weak var delegate: LongPressCursorMovementDelegate?

    /// Initial touch point when trackpad mode activates.
    private var baselinePoint: CGPoint?

    /// Dead zone in points -- absorbs finger jitter after activation.
    /// 8pt matches the feel from the SwiftUI reference implementation.
    private let deadZone: CGFloat = 8.0

    /// Base delta in points per character movement.
    /// Smaller = more sensitive. 12pt provides good balance between precision and speed.
    private let baseDelta: CGFloat = 12.0

    /// Maximum speed multiplier for acceleration.
    private let maxSpeedMultiplier: CGFloat = 3.0

    /// Distance in points at which maximum speed is reached.
    private let accelerationRange: CGFloat = 120.0

    /// Whether the dead zone has been crossed (activation confirmed).
    private var isActive = false

    /// Accumulated fractional movement for sub-delta precision.
    private var accumulatedMovement: CGFloat = 0.0

    /// Rate limiter: minimum time between cursor moves to avoid overwhelming textDocumentProxy.
    /// textDocumentProxy.adjustTextPosition is IPC -- too many calls causes lag.
    private var lastMoveTime: TimeInterval = 0
    private let minMoveInterval: TimeInterval = 0.016  // ~60Hz max

    public func touchesBegan(_ point: CGPoint) {
        if baselinePoint == nil {
            baselinePoint = point
            isActive = false
            accumulatedMovement = 0
        }
    }

    public func touchesMoved(_ point: CGPoint) {
        guard let baseline = baselinePoint else { return }

        let dx = point.x - baseline.x

        // Phase 1: Dead zone -- absorb jitter
        if !isActive {
            if abs(dx) > deadZone {
                isActive = true
                // Haptic confirmation that trackpad mode is fully active
                HapticFeedback.trackpadActivated()
                // Reset baseline to edge of dead zone so movement starts from zero
                baselinePoint = CGPoint(
                    x: baseline.x + (dx > 0 ? deadZone : -deadZone),
                    y: baseline.y
                )
                accumulatedMovement = 0
            }
            return
        }

        // Phase 2: Active cursor movement with acceleration
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastMoveTime >= minMoveInterval else { return }

        let currentDx = point.x - (baselinePoint?.x ?? baseline.x)

        // Acceleration: move faster the further from baseline
        let distance = abs(currentDx)
        let speedMultiplier = min(maxSpeedMultiplier, 1.0 + (distance / accelerationRange) * (maxSpeedMultiplier - 1.0))

        // Calculate how many characters to move
        accumulatedMovement += (currentDx / baseDelta) * speedMultiplier
        let charsToMove = Int(accumulatedMovement)

        if charsToMove != 0 {
            delegate?.longpress(movedCursor: charsToMove)
            accumulatedMovement -= CGFloat(charsToMove)
            lastMoveTime = now
            // Reset baseline to current position for continuous tracking
            baselinePoint = point
        }
    }

    public func touchesEnded(_ point: CGPoint) {
        baselinePoint = nil
        isActive = false
        accumulatedMovement = 0
        delegate?.longpressDidCancel()
    }
}

@MainActor
class LongPressOverlayController: NSObject,
    LongPressBehaviorProvider,
    UICollectionViewDelegate,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    class LongpressCollectionView: UICollectionView {}

    private let deadZone: CGFloat = 20.0

    private let key: KeyDefinition
    private let theme: Theme
    let longpressValues: [KeyDefinition]

    private var baselinePoint: CGPoint?
    private var collectionView: UICollectionView?

    private let reuseIdentifier = "longpressCell"

    private var selectedKey: KeyDefinition? {
        didSet {
            if selectedKey?.type != oldValue?.type {
                collectionView?.reloadData()
            }
        }
    }

    weak var delegate: LongPressOverlayDelegate?
    private let labelFont: UIFont

    init(key: KeyDefinition, page: KeyboardPage, theme: Theme, longpressValues: [KeyDefinition]) {
        self.key = key
        self.theme = theme
        self.longpressValues = longpressValues
        switch page {
        case .normal:
            labelFont = theme.popupLongpressLowerKeyFont
        default:
            labelFont = theme.popupLongpressCapitalKeyFont
        }
    }

    private func setup() {
        collectionView = LongpressCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView?.register(LongpressKeyCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        collectionView?.translatesAutoresizingMaskIntoConstraints = false
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.backgroundColor = .clear

        if let delegate = self.delegate {
            delegate.longpress(didCreateOverlayContentView: collectionView!)
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func touchesBegan(_ point: CGPoint) {
        if baselinePoint == nil {
            baselinePoint = point
            setup()
        }
        pointUpdated(point)
    }

    public func touchesMoved(_ point: CGPoint) {
        if baselinePoint == nil {
            baselinePoint = point
            setup()
        }
        pointUpdated(point)
    }

    public func touchesEnded(_ point: CGPoint) {
        pointUpdated(point)

        if let selectedKey = self.selectedKey {
            delegate?.longpress(didSelectKey: selectedKey)
        } else {
            delegate?.longpressDidCancel()
        }
    }

    private func longPressTouchPoint(at point: CGPoint,
                                     cellSize: CGSize,
                                     view collectionView: UICollectionView,
                                     parentView: UIView) -> CGPoint {
        func pointInCollectionView(with point: CGPoint) -> CGPoint {
            let bounds = collectionView.bounds
            let halfWidth = cellSize.width / 2.0
            let halfHeight = cellSize.height / 2.0
            let heightOffset: CGFloat = collectionView.shouldUseiPadLayout ? 0 : -halfHeight

            var x = point.x
            let minX = bounds.minX
            let maxX = bounds.maxX

            if x <= minX {
                x = minX + halfWidth
            } else if x >= maxX {
                x = maxX - halfWidth
            }

            var y = point.y + heightOffset
            let minY = collectionView.bounds.minY
            let maxY = collectionView.bounds.maxY

            if y <= minY {
                y = minY + halfHeight
            } else if y >= maxY {
                y = maxY - halfHeight
            }

            return CGPoint(x: x, y: y)
        }

        let selectionBox: CGRect = collectionView.frame.insetBy(dx: -cellSize.width, dy: -cellSize.height)

        let convertedPoint = parentView.convert(point, to: collectionView)
        if selectionBox.contains(convertedPoint) {
            return pointInCollectionView(with: convertedPoint)
        }

        return point
    }

    private func pointUpdated(_ point: CGPoint) {
        let cellSize = delegate?.longpressKeySize() ?? CGSize(width: 20, height: 30.0)
        let bigFrame = delegate!.longpressFrameOfReference()
        var superView: UIView? = collectionView

        repeat {
            superView = superView?.superview
        } while superView?.bounds != bigFrame && superView != nil

        guard let wholeView = superView else { return }
        guard let collectionView = self.collectionView else { return }

        let point = longPressTouchPoint(at: point, cellSize: cellSize, view: collectionView, parentView: wholeView)

        if let indexPath = collectionView.indexPathForItem(at: point) {
            selectedKey = longpressValues[indexPath.row + Int(ceil(Double(longpressValues.count) / 2.0)) * indexPath.section]
        } else {
            selectedKey = nil
        }
    }

    func numberOfSections(in _: UICollectionView) -> Int {
        return longpressValues.count > theme.popupLongpressKeysPerRow ? 2 : 1
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if longpressValues.count > theme.popupLongpressKeysPerRow {
            return section == 0 ? Int(ceil(Double(longpressValues.count) / 2.0)) : Int(floor(Double(longpressValues.count) / 2.0))
        }
        return longpressValues.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
                                                            for: indexPath) as? LongpressKeyCell else {
            fatalError("Unable to cast to LongpressKeyCell")
        }
        cell.configure(theme: theme)
        let key = longpressValues[indexPath.row + Int(ceil(Double(longpressValues.count) / 2.0)) * indexPath.section]

        // Font scaled to match the reduced longpressKeySize height (#69).
        cell.label.font = labelFont.withSize(labelFont.pointSize * 0.8)

        func setupKeyboardModeCell(imageName: String) {
            // Use Bundle.main instead of Bundle.top (Divvun-specific)
            cell.imageView.image = UIImage(named: imageName, in: Bundle.main, compatibleWith: collectionView.traitCollection)
        }

        if case let .input(string, _) = key.type {
            cell.label.text = string
            cell.imageView.image = nil
        } else if case .normalKeyboard = key.type {
            setupKeyboardModeCell(imageName: "keyboard-mode-normal")
        } else if case .splitKeyboard = key.type {
            setupKeyboardModeCell(imageName: "keyboard-mode-split")
        } else if case .sideKeyboardLeft = key.type {
            setupKeyboardModeCell(imageName: "keyboard-mode-left")
        } else if case .sideKeyboardRight = key.type {
            setupKeyboardModeCell(imageName: "keyboard-mode-right")
        }

        if key.type == selectedKey?.type {
            cell.select(theme: theme)
        } else {
            cell.deselect(theme: theme)
        }

        return cell
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt _: IndexPath) -> CGSize {
        return delegate?.longpressKeySize() ?? CGSize(width: 20, height: 30.0)
    }

    func collectionView(_: UICollectionView,
                        layout _: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumLineSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout _: UICollectionViewLayout,
                        insetForSectionAt _: Int) -> UIEdgeInsets {
        let cellSize = delegate?.longpressKeySize() ?? CGSize(width: 20.0, height: 30.0)
        let cellWidth = cellSize.width
        let numberOfCells = CGFloat(longpressValues.count)

        guard numberOfCells <= 1 else { return .zero }

        let edgeInsets = (collectionView.frame.size.width - (numberOfCells * cellWidth)) / (numberOfCells + 1)
        return UIEdgeInsets(top: 0, left: edgeInsets, bottom: 0, right: edgeInsets)
    }

    class LongpressKeyCell: UICollectionViewCell {
        let label: UILabel
        let imageView: UIImageView

        private(set) var isSelectedKey: Bool = false

        func select(theme: Theme) {
            label.textColor = theme.activeTextColor
            label.backgroundColor = theme.longPressActiveColor
            imageView.tintColor = theme.activeTextColor
            isSelectedKey = true
        }

        func deselect(theme: Theme) {
            label.textColor = theme.textColor
            label.backgroundColor = theme.popupColor
            imageView.tintColor = theme.textColor
            isSelectedKey = false
        }

        override init(frame: CGRect) {
            label = UILabel(frame: frame)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.clipsToBounds = true

            imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit

            super.init(frame: frame)

            addSubview(label)
            addSubview(imageView)
            imageView.fill(superview: self)
            label.fill(superview: self)
        }

        func configure(theme: Theme) {
            label.layer.cornerRadius = theme.keyCornerRadius
            imageView.tintColor = theme.textColor
        }

        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

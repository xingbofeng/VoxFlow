// DictusKeyboard/Vendored/Views/GiellaKeyboardView.swift
// Vendored from giellakbd-ios Keyboard/Views/GiellaKeyboardView.swift
// Stripped: No external dependencies to remove (no Sentry in this file)

import UIKit
import Shared

@MainActor
protocol GiellaKeyboardViewDelegate: AnyObject {
    func didSwipeKey(_ key: KeyDefinition)
    func didTriggerKey(_ key: KeyDefinition)
    func didTriggerDoubleTap(forKey key: KeyDefinition)
    func didTriggerHoldKey(_ key: KeyDefinition)
    func didMoveCursor(_ movement: Int)
}

@MainActor
@objc protocol GiellaKeyboardViewKeyboardKeyDelegate {
    @objc func didTriggerKeyboardButton(sender: UIView, forEvent event: UIEvent)
}

@MainActor
protocol GiellaKeyboardViewProvider {
    var page: KeyboardPage { get set }
    func update()
    func remove()
    var topAnchor: NSLayoutYAxisAnchor { get }
    var bottomAnchor: NSLayoutYAxisAnchor { get }
    var leftAnchor: NSLayoutXAxisAnchor { get }
    var rightAnchor: NSLayoutXAxisAnchor { get }
}

final internal class GiellaKeyboardView: UIView,
    GiellaKeyboardViewProvider,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout,
    LongPressOverlayDelegate,
    LongPressCursorMovementDelegate
{
    private static let pauseBeforeRepeatTimeInterval: TimeInterval = 0.5
    private static let keyRepeatTimeInterval: TimeInterval = 0.1
    private var theme: Theme

    private let definition: KeyboardDefinition

    weak var delegate: (GiellaKeyboardViewDelegate & GiellaKeyboardViewKeyboardKeyDelegate)?

    private var ghostKeyView: GhostKeyView?

    private var currentPage: [[KeyDefinition]] {
        return keyDefinitionsForPage(page)
    }

    private func keyDefinitionsForPage(_ page: KeyboardPage) -> [[KeyDefinition]] {
        guard let layout = definition.currentDeviceLayout else {
            return []
        }
        switch page {
        case .symbols1:
            return layout.symbols1
        case .symbols2:
            return layout.symbols2
        case .shifted, .capslock:
            return layout.shifted
        default:
            return layout.normal
        }
    }

    public var page: KeyboardPage = .normal {
        didSet {
            update()
        }
    }

    private let reuseIdentifier = "cell"
    private let collectionView: UICollectionView
    private let layout = UICollectionViewFlowLayout()

    private var longpressController: LongPressBehaviorProvider?
    private var currentlyLongpressedKey: KeyDefinition?

    private var keyboardButtonFrame: CGRect? {
        didSet {
            if let keyboardButtonExtraButton = keyboardButtonExtraButton {
                keyboardButtonExtraButton.removeFromSuperview()
                self.keyboardButtonExtraButton = nil
            }
            if let keyboardButtonFrame = keyboardButtonFrame {
                keyboardButtonExtraButton = UIButton(frame: keyboardButtonFrame)
                keyboardButtonExtraButton?.backgroundColor = .clear
                keyboardButtonExtraButton?.isAccessibilityElement = true
                keyboardButtonExtraButton?.accessibilityLabel = NSLocalizedString("accessibility.nextKeyboard", comment: "")
            }
            if let keyboardButtonExtraButton = keyboardButtonExtraButton {
                addSubview(keyboardButtonExtraButton)
                keyboardButtonExtraButton.addTarget(delegate,
                                                    action: #selector(GiellaKeyboardViewKeyboardKeyDelegate.didTriggerKeyboardButton),
                                                    for: UIControl.Event.allEvents)
            }
        }
    }

    private var keyboardButtonExtraButton: UIButton?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private(set) lazy var longpressGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(GiellaKeyboardView.touchesFoundLongpress))
        recognizer.cancelsTouchesInView = false
        // Ensure touchesBegan is delivered immediately to the view, without waiting
        // for the gesture recognizer to fail. This prevents iOS from delaying touch
        // delivery at screen edges where system gesture disambiguation can add ~100ms.
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }()

    required init(definition: KeyboardDefinition, theme: Theme) {
        self.definition = definition
        self.theme = theme

        collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)

        super.init(frame: CGRect.zero)
        update()

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(KeyCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        collectionView.isUserInteractionEnabled = false
        collectionView.isScrollEnabled = false

        addSubview(collectionView)
        collectionView.topAnchor.constraint(equalTo: topAnchor).enable()
        collectionView.bottomAnchor.constraint(equalTo: bottomAnchor).enable()
        collectionView.leftAnchor.constraint(equalTo: leftAnchor).enable()
        collectionView.rightAnchor.constraint(equalTo: rightAnchor).enable()
        collectionView.backgroundColor = .clear

        addGestureRecognizer(longpressGestureRecognizer)

        // Pre-warm the local haptic generator so first touch has zero latency
        hapticFeedback.prepare()

        isMultipleTouchEnabled = true
    }

    func updateTheme(theme: Theme) {
        self.theme = theme
        update()
    }

    /// Current label for the adaptive accent key. Updated by the bridge after each keystroke.
    /// Defaults to apostrophe (the most useful non-letter character in French).
    var accentKeyLabel: String = "'"

    public func update() {
        backgroundColor = theme.backgroundColor
        keyboardButtonFrame = nil
        calculateRows()
    }

    /// Update the accent key label and refresh its cell.
    /// Called by DictusKeyboardBridge after every keystroke to keep the accent key's
    /// displayed character in sync with context (accent after vowel, apostrophe otherwise).
    func updateAccentKeyLabel(_ label: String) {
        guard label != accentKeyLabel else { return }
        accentKeyLabel = label
        // Update the accent key cell directly without reloadItems.
        // reloadItems triggers a collection view layout pass which causes iOS to
        // recalculate the keyboard height — shrinking keys on top-row taps because
        // the popup overlay extends above bounds.
        for section in 0..<currentPage.count {
            for row in 0..<currentPage[section].count {
                if case .input(_, let alt) = currentPage[section][row].type, alt == "accent" {
                    let indexPath = IndexPath(row: row, section: section)
                    if let cell = collectionView.cellForItem(at: indexPath) as? KeyCell {
                        let key = KeyDefinition(type: .input(key: accentKeyLabel, alternate: nil))
                        cell.configure(page: page, key: key, theme: theme, traits: self.traitCollection)
                    }
                    return
                }
            }
        }
    }

    func remove() {
        delegate = nil
        removeFromSuperview()
    }

    // MARK: - Overlay handling

    private(set) var overlays: [KeyType: KeyOverlayView] = [:]

    override var bounds: CGRect {
        didSet {
            update()
        }
    }

    private func ensureValidKeyView(at indexPath: IndexPath) -> Bool {
        guard collectionView.cellForItem(at: indexPath)?.subviews.first?.subviews.first?.subviews.first != nil else {
            return false
        }
        return true
    }

    private func applyOverlayConstraints(to overlay: KeyOverlayView, ghostKeyView: GhostKeyView) {
        guard let superview = superview else {
            return
        }

        overlay.heightAnchor
            .constraint(greaterThanOrEqualTo: ghostKeyView.heightAnchor)
            .enable(priority: .defaultHigh)

        overlay.widthAnchor.constraint(
            greaterThanOrEqualTo: ghostKeyView.widthAnchor,
            constant: theme.popupCornerRadius * 2)
            .enable(priority: .required)

        // REMOVED (#69): topAnchor constraint caused Auto Layout to shrink keyboard
        // keys when top-row popups extended above bounds. The overlay renders above
        // bounds safely because clipsToBounds = false on all ancestor views.

        let offset: CGFloat = 0.5
        overlay.bottomAnchor.constraint(equalTo: ghostKeyView.contentView.bottomAnchor, constant: offset)
            .enable(priority: .defaultHigh)

        overlay.centerXAnchor.constraint(equalTo: ghostKeyView.centerXAnchor)
            .enable(priority: .defaultHigh)

        overlay.leftAnchor.constraint(greaterThanOrEqualTo: ghostKeyView.leftAnchor)
            .enable(priority: .defaultHigh)
        overlay.leftAnchor
            .constraint(greaterThanOrEqualTo: superview.leftAnchor)
            .enable(priority: .required)

        overlay.rightAnchor.constraint(lessThanOrEqualTo: ghostKeyView.rightAnchor)
            .enable(priority: .defaultHigh)
        overlay.rightAnchor
            .constraint(lessThanOrEqualTo: superview.rightAnchor)
            .enable(priority: .required)
    }

    private func showOverlay(forKeyAtIndexPath indexPath: IndexPath) {
        guard let keyCell = collectionView.cellForItem(at: indexPath) as? KeyCell,
              let keyView = keyCell.keyView,
              ensureValidKeyView(at: indexPath) else {
            return
        }
        let key = currentPage[indexPath.section][indexPath.row]
        removeAllOverlays()

        ghostKeyView = GhostKeyView(keyView: keyView, in: self)
        guard let ghostKeyView = ghostKeyView else {
            return
        }

        ghostKeyView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(ghostKeyView)

        ghostKeyView.leftAnchor.constraint(equalTo: self.leftAnchor, constant: ghostKeyView.frame.minX).enable(priority: .required)
        ghostKeyView.topAnchor.constraint(equalTo: self.topAnchor, constant: ghostKeyView.frame.minY).enable(priority: .required)
        ghostKeyView.widthAnchor.constraint(equalToConstant: ghostKeyView.frame.width).enable(priority: .required)
        ghostKeyView.heightAnchor.constraint(equalToConstant: ghostKeyView.frame.height).enable(priority: .required)

        let overlay = KeyOverlayView(ghostKeyView: ghostKeyView, key: key, theme: theme)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(overlay)

        applyOverlayConstraints(to: overlay, ghostKeyView: ghostKeyView)
        overlays[key.type] = overlay

        overlay.clipsToBounds = false

        let keyLabelContainerView = UIView()
        keyLabelContainerView.backgroundColor = .clear
        keyLabelContainerView.translatesAutoresizingMaskIntoConstraints = false

        // Emoji key popup: show SF Symbol (monochrome) instead of colored emoji glyph.
        let isEmojiKey: Bool
        if case let .input(title, _) = key.type, title == "\u{1F600}" {
            isEmojiKey = true
        } else {
            isEmojiKey = false
        }

        let keyLabelHeight = longpressKeySize().height
        overlay.overlayContentView.addSubview(keyLabelContainerView)

        if isEmojiKey {
            let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            let imageView = UIImageView(image: UIImage(systemName: "face.smiling", withConfiguration: config))
            imageView.tintColor = theme.textColor
            imageView.contentMode = .center
            imageView.translatesAutoresizingMaskIntoConstraints = false
            keyLabelContainerView.addSubview(imageView)
            imageView.centerXAnchor.constraint(equalTo: keyLabelContainerView.centerXAnchor).isActive = true
            imageView.centerYAnchor.constraint(equalTo: keyLabelContainerView.centerYAnchor).isActive = true
        } else {
            let keyLabel = UILabel(frame: .zero)
            keyLabel.clipsToBounds = false
            if case let .input(title, _) = key.type {
                keyLabel.text = title
            }
            keyLabel.textColor = theme.textColor
            switch page {
            case .normal:
                keyLabel.font = theme.popupLowerKeyFont
            default:
                keyLabel.font = theme.popupCapitalKeyFont
            }
            keyLabel.textAlignment = .center
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            keyLabelContainerView.addSubview(keyLabel)
            keyLabel.centerIn(superview: keyLabelContainerView)
        }

        keyLabelContainerView.heightAnchor.constraint(equalToConstant: keyLabelHeight).enable(priority: .required)
        keyLabelContainerView.fill(superview: overlay.overlayContentView)

        // NOTE: Do NOT call superview?.setNeedsLayout() here.
        // The overlay has its own constraints and will layout correctly.
        // Forcing the parent (kbInputView) to relayout causes the keyboard
        // height to expand on top-row key taps because the overlay extends
        // above bounds and iOS resolves the height constraint upward.
    }

    func removeOverlay(forKey key: KeyDefinition) {
        ghostKeyView?.removeFromSuperview()
        ghostKeyView = nil
        overlays[key.type]?.removeFromSuperview()
        overlays[key.type] = nil
    }

    func removeAllOverlays() {
        ghostKeyView?.removeFromSuperview()
        ghostKeyView = nil
        for overlay in overlays.values {
            overlay.removeFromSuperview()
        }
        overlays = [:]
    }

    // MARK: - LongPressOverlayDelegate

    func longpress(didCreateOverlayContentView contentView: UIView) {
        hapticFeedback.impactOccurred()

        if overlays.first?.value.overlayContentView == nil {
            if let activeKey = activeKey {
                showOverlay(forKeyAtIndexPath: activeKey.indexPath)
            }
        }

        guard let overlayContentView = self.overlays.first?.value.overlayContentView else {
            return
        }

        overlayContentView.subviews.forEach { $0.removeFromSuperview() }
        overlayContentView.addSubview(contentView)
        contentView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentView.fill(superview: overlayContentView)

        if activeKey != nil,
            let longpressValues = (self.longpressController as? LongPressOverlayController)?.longpressValues {
            let count = longpressValues.count

            let widthConstant: CGFloat
            if count > theme.popupLongpressKeysPerRow {
                widthConstant = longpressKeySize().width * ceil(CGFloat(count) / 2.0) + theme.keyHorizontalMargin
            } else {
                widthConstant = longpressKeySize().width * CGFloat(count) + theme.keyHorizontalMargin
            }

            let heightConstant: CGFloat

            if count > theme.popupLongpressKeysPerRow {
                heightConstant = longpressKeySize().height * 2
            } else {
                heightConstant = longpressKeySize().height
            }

            contentView.widthAnchor.constraint(equalToConstant: widthConstant).enable(priority: .required)
            contentView.heightAnchor.constraint(equalToConstant: heightConstant).enable(priority: .required)
        } else {
            let constant = longpressKeySize().height
            contentView.heightAnchor.constraint(equalToConstant: constant).enable(priority: .required)
        }
        contentView.layoutIfNeeded()
    }

    func longpressDidCancel() {
        longpressController = nil
        currentlyLongpressedKey = nil
        collectionView.alpha = 1.0
        if shouldUseiPadLayout, let activeKey = activeKey {
            switch activeKey.key.type {
            case .spacebar(name: _):
                break
            default:
                delegate?.didTriggerKey(activeKey.key)
            }
        }
    }

    func longpress(didSelectKey key: KeyDefinition) {
        delegate?.didTriggerKey(key)
        longpressController = nil
        currentlyLongpressedKey = nil
    }

    func longpressFrameOfReference() -> CGRect {
        return bounds
    }

    func longpressKeySize() -> CGSize {
        switch currentlyLongpressedKey?.type {
        case .returnkey(name: _):
            return CGSize(width: 50, height: 35)
        case .keyboardMode:
            return CGSize(width: 75, height: 53)
        default:
            break
        }

        let width = bounds.size.width / CGFloat(currentPage.first?.count ?? 10)
        // Reduce height to 60% so first-row popups stay within keyboard bounds (#69).
        var height = ((bounds.size.height / CGFloat(currentPage.count)) - theme.popupCornerRadius * 2) * 0.6
        height = max(24.0, height)
        return CGSize(
            width: width,
            height: height
        )
    }

    // MARK: - LongPressCursorMovementDelegate

    func longpress(movedCursor: Int) {
        delegate?.didMoveCursor(movedCursor)
    }

    // MARK: - Input handling

    struct KeyTriggerTiming {
        let time: TimeInterval
        let key: KeyDefinition

        static let doubleTapTime: TimeInterval = 0.4
    }

    var keyTriggerTiming: KeyTriggerTiming?
    var keyRepeatTimer: Timer?
    var dismissOverlayTimer: Timer?

    /// Tracks how many times the key repeat timer has fired during the current hold.
    /// Used to switch from character-level to word-level deletion after threshold.
    private var deleteRepeatCount: Int = 0

    /// After this many character deletions, switch to word-level deletion.
    private static let wordModeThreshold = 10

    struct ActiveKey: Hashable {
        static func == (lhs: GiellaKeyboardView.ActiveKey, rhs: GiellaKeyboardView.ActiveKey) -> Bool {
            return lhs.key.type == rhs.key.type
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(key.type)
        }

        let key: KeyDefinition
        let indexPath: IndexPath
    }

    var activeKey: ActiveKey? {
        willSet {
            dismissOverlayTimer?.invalidate()
            dismissOverlayTimer = nil

            if let activeKey = activeKey,
                let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                newValue?.indexPath != activeKey.indexPath {
                cell.keyView?.active = false
            }
            if newValue == nil, let activeKey = activeKey {
                dismissOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { [weak self] _ in
                    self?.removeOverlay(forKey: activeKey.key)
                })
                keyRepeatTimer?.invalidate()
                keyRepeatTimer = nil
                deleteRepeatCount = 0
            }

            if let key = newValue, key.key.type.supportsRepeatTrigger, keyRepeatTimer == nil {
                keyRepeatTimer = makeKeyRepeatTimer(timeInterval: GiellaKeyboardView.pauseBeforeRepeatTimeInterval)
            }
        }
        didSet {
            if let activeKey = activeKey,
                let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                activeKey.indexPath != oldValue?.indexPath {
                cell.keyView?.active = true
                if case .input = activeKey.key.type, !shouldUseiPadLayout {
                    showOverlay(forKeyAtIndexPath: activeKey.indexPath)
                }
            }
        }
    }

    private func makeKeyRepeatTimer(timeInterval: TimeInterval) -> Timer {
        return Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(GiellaKeyboardView.keyRepeatTimerDidTrigger),
            userInfo: nil,
            repeats: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        // Fire haptic on touchDown for ALL keys (not just triggersOnTouchDown).
        // The delegate's didTriggerKey() may fire on touchUp for input keys,
        // but the user should FEEL the tap immediately on finger contact.
        hapticFeedback.prepare()
        HapticFeedback.keyTapped()

        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesBegan(touch.location(in: collectionView))
            return
        }

        if let key = activeKey?.key {
            if key.type.triggersOnTouchUp {
                if let delegate = delegate {
                    delegate.didTriggerKey(key)
                }
            }
            activeKey = nil
        }

        handleTouches(touches)
    }

    private func handleTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            let touchPoint = clampedPoint(touch.location(in: collectionView))
            if let indexPath = collectionView.indexPathForItem(at: touchPoint) {
                let key = currentPage[indexPath.section][indexPath.row]

                if key.type.supportsDoubleTap {
                    let timeInterval = Date.timeIntervalSinceReferenceDate
                    if let keyTriggerTiming = keyTriggerTiming {
                        if max(0.0, timeInterval - keyTriggerTiming.time) < KeyTriggerTiming.doubleTapTime {
                            if let delegate = delegate {
                                delegate.didTriggerDoubleTap(forKey: key)
                                self.keyTriggerTiming = nil
                                return
                            }
                        }
                    }
                    keyTriggerTiming = KeyTriggerTiming(time: timeInterval, key: key)
                }

                if !key.type.isInputKey {
                    removeAllOverlays()
                }

                if key.type.triggersOnTouchDown {
                    if let delegate = delegate {
                        delegate.didTriggerKey(key)
                    }
                }

                let isSymbolsKey = key.type == .symbols || key.type == .shiftSymbols
                let shouldSetActiveKey = (key.type.triggersOnTouchUp ||
                                         key.type.supportsRepeatTrigger ||
                                         key.type.triggersOnTouchDown) && !isSymbolsKey

                if shouldSetActiveKey {
                    activeKey = ActiveKey(key: key, indexPath: indexPath)
                }
            }
        }
    }

    /// Clamp a touch point into the collection view's content area.
    ///
    /// WHY: `indexPathForItem(at:)` returns nil if the point is even 1pt outside any
    /// cell's frame. Edge keys (a, q, p, m) have their outer edge flush with the screen,
    /// but the user's finger center can land slightly outside. Clamping the point inward
    /// by a small margin ensures `indexPathForItem` finds the intended edge cell.
    ///
    /// This approach is simpler and more reliable than iterating visibleCells, because
    /// it uses the same layout engine that `indexPathForItem` uses internally.
    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        let margin: CGFloat = 4.0
        return CGPoint(
            x: min(max(point.x, margin), collectionView.bounds.width - margin),
            y: min(max(point.y, margin), collectionView.bounds.height - margin)
        )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesMoved(touch.location(in: collectionView))
            return
        }

        if let activeKey = activeKey,
            let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
            let swipeKeyView = cell.keyView,
            swipeKeyView.isSwipeKey,
            let touchLocation = touches.first?.location(in: cell.superview) {
            let deadZone: CGFloat = 20.0
            let delta: CGFloat = 60.0
            let yOffset = touchLocation.y - cell.center.y

            var percentage: CGFloat = 0.0
            if yOffset > deadZone {
                if yOffset - deadZone > delta {
                    percentage = 1.0
                } else {
                    percentage = (yOffset - deadZone) / delta
                }
            }
            swipeKeyView.percentageAlternative = percentage
            return
        }

        if activeKey != nil {
            for touch in touches {
                let movePoint = clampedPoint(touch.location(in: collectionView))
                if let indexPath = collectionView.indexPathForItem(at: movePoint) {
                    let key = currentPage[indexPath.section][indexPath.row]
                    activeKey = ActiveKey(key: key, indexPath: indexPath)
                } else {
                    activeKey = nil
                }
            }
        }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        longpressController = nil
        activeKey = nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesEnded(touch.location(in: collectionView))
            removeAllOverlays()
            activeKey = nil
            return
        }

        if let activeKey = activeKey {
            if activeKey.key.type.triggersOnTouchUp {
                if let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                    let swipeKeyView = cell.keyView,
                    swipeKeyView.isSwipeKey,
                    swipeKeyView.percentageAlternative > 0.5 {
                    delegate?.didSwipeKey(activeKey.key)
                } else {
                    delegate?.didTriggerKey(activeKey.key)
                }
            }
        }

        if activeKey != nil {
            activeKey = nil
        }
    }

    private func showKeyboardModeOverlay(_ longpressGestureRecognizer: UILongPressGestureRecognizer, key: KeyDefinition) {
        let longpressValues = keyboardModeDefinitions()
        let longpressController = LongPressOverlayController(key: key, page: page, theme: theme, longpressValues: longpressValues)
        longpressController.delegate = self

        self.longpressController = longpressController
        longpressController.touchesBegan(
            longpressGestureRecognizer.location(in: collectionView))
    }

    private func keyboardModeDefinitions() -> [KeyDefinition] {
        if shouldUseiPadLayout {
            return [
                KeyDefinition(type: .sideKeyboardLeft),
                KeyDefinition(type: .normalKeyboard),
                KeyDefinition(type: .sideKeyboardRight),
                KeyDefinition(type: .splitKeyboard)
            ]
        } else {
            return [
                KeyDefinition(type: .sideKeyboardLeft),
                KeyDefinition(type: .normalKeyboard),
                KeyDefinition(type: .sideKeyboardRight)
            ]
        }
    }

    @objc func touchesFoundLongpress(_ longpressGestureRecognizer: UILongPressGestureRecognizer) {
        let longpressPoint = clampedPoint(longpressGestureRecognizer.location(in: collectionView))
        if let indexPath = collectionView.indexPathForItem(at: longpressPoint),
            longpressController == nil {
            let key = currentPage[indexPath.section][indexPath.row]
            currentlyLongpressedKey = key
            switch key.type {
            case let .input(string, _):
                guard let longpressValues = longpressKeys(for: string),
                    longpressGestureRecognizer.state == .began else {
                        break
                }
                let longpressController = LongPressOverlayController(
                    key: key,
                    page: page,
                    theme: theme,
                    longpressValues: longpressValues)
                longpressController.delegate = self

                self.longpressController = longpressController
                let location = longpressGestureRecognizer.location(in: collectionView)
                longpressController.touchesBegan(location)
            case .keyboardMode:
                if longpressGestureRecognizer.state == .began {
                    showKeyboardModeOverlay(longpressGestureRecognizer, key: key)
                }

            case .spacebar:
                if longpressGestureRecognizer.state == .began {
                    let longpressController = LongPressCursorMovementController()
                    longpressController.delegate = self
                    self.longpressController = longpressController
                    collectionView.alpha = 0.4
                    // Initialize baseline so touchesMoved can compute deltas
                    let startPoint = longpressGestureRecognizer.location(in: collectionView)
                    longpressController.touchesBegan(startPoint)
                }
            case .backspace:
                break
            case .returnkey(name: _):
                if longpressGestureRecognizer.state == .began {
                    showKeyboardModeOverlay(longpressGestureRecognizer, key: key)
                }
            default:
                delegate?.didTriggerHoldKey(key)
            }
        }
    }

    @objc func keyRepeatTimerDidTrigger() {
        if let activeKey = activeKey, activeKey.key.type.supportsRepeatTrigger {
            deleteRepeatCount += 1

            if deleteRepeatCount > Self.wordModeThreshold {
                // Word-level deletion after threshold
                delegate?.didTriggerHoldKey(activeKey.key)
            } else {
                // Character-level deletion
                delegate?.didTriggerKey(activeKey.key)
            }

            // Haptic feedback on each deletion
            HapticFeedback.keyTapped()

            increaseKeyRepeatRateIfNeeded()
        }
    }

    private func increaseKeyRepeatRateIfNeeded() {
        guard let timer = keyRepeatTimer else { return }

        // Stage 1 -> Stage 2: After initial pause (0.5s), switch to character repeat (0.1s)
        if timer.timeInterval == GiellaKeyboardView.pauseBeforeRepeatTimeInterval {
            keyRepeatTimer?.invalidate()
            keyRepeatTimer = makeKeyRepeatTimer(timeInterval: GiellaKeyboardView.keyRepeatTimeInterval)
        }
        // Stage 2 -> Stage 3: After word mode threshold, speed up to 0.05s for faster word deletion
        else if deleteRepeatCount == Self.wordModeThreshold + 1 && timer.timeInterval == GiellaKeyboardView.keyRepeatTimeInterval {
            keyRepeatTimer?.invalidate()
            keyRepeatTimer = makeKeyRepeatTimer(timeInterval: 0.1)
        }
    }

    private func longpressKeys(for key: String) -> [KeyDefinition]? {
        // Case-insensitive lookup: AccentedCharacters.mappings uses lowercase keys,
        // but on shifted/capslock pages the key string is uppercase ("E" not "e").
        let longpressKeys = self.definition
        .longPress[key.lowercased()]?
        .compactMap({
            KeyDefinition(type: .input(key: $0, alternate: nil))
        })

        guard var keys = longpressKeys else {
            return nil
        }

        // Apply case transformation for shifted/capslock pages
        // so that long-pressing "E" shows uppercase accents (E, E, E, E)
        if page == .shifted || page == .capslock {
            keys = keys.map { keyDef in
                if case let .input(char, alt) = keyDef.type {
                    return KeyDefinition(type: .input(key: char.uppercased(), alternate: alt))
                }
                return keyDef
            }
        }

        if shouldUseiPadLayout == false {
            let originalKey = KeyDefinition(type: .input(key: key, alternate: nil))
            if keys.contains(where: { (keyDefinition) -> Bool in
                keyDefinition.type == originalKey.type
            }) {
                // Already contains this key. Do nothing.
            } else {
                keys = [originalKey] + keys
            }
        }

        return keys
    }

    // MARK: - CollectionView

    private var rowNumberOfUnits: [CGFloat]!

    private func calculateRows() {
        var mutableWidths = [CGFloat]()

        for row in currentPage {
            let numberOfUnits = row.reduce(0.0) { (sum, key) -> CGFloat in
                sum + key.size.width
            }
            mutableWidths.append(numberOfUnits)
        }

        rowNumberOfUnits = mutableWidths

        collectionView.reloadData()
    }

    func numberOfSections(in _: UICollectionView) -> Int {
        return currentPage.count
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return currentPage[section].count
    }

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        let key = currentPage[indexPath.section][indexPath.row]

        if key.type == .keyboard {
            keyboardButtonFrame = cell.frame
        }

        if let keyCell = cell as? KeyCell,
           let activeKey = activeKey,
           activeKey.indexPath == indexPath {
            keyCell.keyView?.active = true
        } else if let keyCell = cell as? KeyCell {
            keyCell.keyView?.active = false
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
                                                            for: indexPath) as? KeyCell else {
            fatalError("Unable to cast to KeyCell")
        }
        var key = currentPage[indexPath.section][indexPath.row]

        // For the adaptive accent key, substitute the display label with the current
        // dynamic value (accent after vowel, apostrophe otherwise). Pass nil for
        // alternate so the sentinel "accent" is NOT rendered as a visible label.
        // The original key in currentPage still has alternate: "accent" for identification.
        if case .input(_, let alt) = key.type, alt == "accent" {
            key = KeyDefinition(type: .input(key: accentKeyLabel, alternate: nil))
        }

        cell.configure(page: page, key: key, theme: theme, traits: self.traitCollection)

        if let swipeKeyView = cell.keyView, swipeKeyView.isSwipeKey {
            swipeKeyView.percentageAlternative = 0.0
        }

        return cell
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let key = currentPage[indexPath.section][indexPath.row]

        let width = key.size.width * ((bounds.size.width - 1) / rowNumberOfUnits[indexPath.section])
        let height = bounds.size.height / CGFloat(currentPage.count)
        return CGSize(width: width, height: height)
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumLineSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    final class KeyCell: UICollectionViewCell {
        var keyView: KeyView?

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.clipsToBounds = false
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentView.fill(superview: self)
        }

        func configure(page: KeyboardPage, key: KeyDefinition, theme: Theme, traits: UITraitCollection) {
            contentView.subviews.forEach { view in
                view.removeFromSuperview()
            }
            keyView = nil

            if case .spacer = key.type {
                let emptyview = UIView(frame: .zero)
                emptyview.translatesAutoresizingMaskIntoConstraints = false
                emptyview.backgroundColor = .clear
                contentView.addSubview(emptyview)
                emptyview.fill(superview: contentView)
            } else {
                let keyView = KeyView(page: page, key: key, theme: theme, traits: traits)
                if let accessibilityLabel = key.accessibilityLabel(for: page) {
                    keyView.isAccessibilityElement = true
                    keyView.accessibilityLabel = accessibilityLabel
                }
                keyView.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(keyView)
                keyView.fill(superview: contentView)
                self.keyView = keyView
            }
        }

        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

// GhostKeyView: used to remember the position of a key that was tapped on the keyboard
// Needed because the collectionView forgets the position of keys after they've been tapped,
// and the overlay view needs this to be accurately drawn
@MainActor
final class GhostKeyView: UIView {
    let contentView: UIView

    init(keyView: KeyView, in parentView: UIView) {
        let translatedFrame = keyView.convert(keyView.frame, to: parentView)
        contentView = UIView(frame: keyView.contentView.convert(keyView.contentView.frame, to: parentView))

        contentView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: translatedFrame)

        self.addSubview(contentView)

        contentView.centerXAnchor.constraint(equalTo: self.centerXAnchor).enable(priority: .required)
        contentView.centerYAnchor.constraint(equalTo: self.centerYAnchor).enable(priority: .required)
        contentView.widthAnchor.constraint(equalToConstant: contentView.frame.width).enable(priority: .required)
        contentView.heightAnchor.constraint(equalToConstant: contentView.frame.height).enable(priority: .required)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

import UIKit

/// The New dictation key's shortcuts, in the tray's fixed order (Settings › Experiments ›
/// New dictation key shows or hides each).
nonisolated enum WormaTrayItem: String, CaseIterable, Sendable {
    case gif
    case clipboard
    case translate
    case style
    case language
    case settings

    var symbol: String {
        switch self {
        case .gif: "photo.stack"
        case .clipboard: "list.clipboard"
        case .translate: "translate"
        case .style: "textformat"
        case .language: "globe"
        case .settings: "gearshape"
        }
    }

    var title: String {
        switch self {
        case .gif: String(localized: "GIFs")
        case .clipboard: String(localized: "Clipboard")
        case .translate: String(localized: "Translate")
        case .style: String(localized: "Style")
        case .language: String(localized: "Language")
        case .settings: String(localized: "Settings")
        }
    }
}

/// Settings › Experiments › New dictation key, laid over the suggestion strip: a chevron at
/// the end beside the Hex key, and while open a row of shortcuts in place of the suggestions
/// (or a style's or language's chips). Closed, only the chevron takes touches.
///
/// Motion follows the strip's: chips spring in from the chevron (0.35 s, damping 0.85, a short
/// stagger) and leave toward it (0.15 s) before the words come back; the chevron turns rather
/// than swapping its image. Reduce Motion keeps only a 0.15 s crossfade.
@MainActor
final class WormaDictationTrayView: UIView {
    enum Page: Equatable {
        case items([WormaTrayItem])
        case styles
        case languages
    }

    /// The chevron's slot, a full touch target beside the Hex key.
    static let chevronWidth: CGFloat = 44
    /// After a page change, chips ignore taps this long, so a quick second tap doesn't land
    /// on whatever chip took the first one's place.
    static let pageGuard: TimeInterval = 0.25

    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { rebuild(animated: false) } } }
    var hexOnLeading = false { didSet { if hexOnLeading != oldValue { turnChevron(animated: false); setNeedsLayout() } } }
    var textCenterY: CGFloat = 19 { didSet { if textCenterY != oldValue { setNeedsLayout() } } }
    var chipHeight: CGFloat = 30 { didSet { if chipHeight != oldValue { setNeedsLayout() } } }
    var hidesChevron = false {
        didSet {
            guard hidesChevron != oldValue else { return }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.chevron.alpha = self.hidesChevron ? 0 : 1
                self.divider.alpha = self.dividerAlpha
            }
        }
    }
    /// What the chips show as chosen.
    var isTranslating = false { didSet { if isTranslating != oldValue { refreshSelection() } } }
    var style: DictationStyle = .polished { didSet { if style != oldValue { refreshSelection() } } }
    /// Automatic (nil) first, then the quick choices, with their names.
    var languages: [(id: String?, name: String)] = []
    var language: String? { didSet { if language != oldValue { refreshSelection() } } }

    var onChevron: (() -> Void)?
    var onItem: ((WormaTrayItem) -> Void)?
    var onStyle: ((DictationStyle) -> Void)?
    var onLanguage: ((String?) -> Void)?
    /// A chip or the chevron went down (click and haptic, as a key's).
    var onKeyDown: (() -> Void)?

    private(set) var page: Page?
    var isOpen: Bool { page != nil }
    private let chevron = UIButton(type: .custom)
    /// The strip's divider on the chevron's other side, so it sits centred in a cell of its
    /// own between the words and the Hex key. Closed only: open, the words' dividers are gone.
    private let divider = UIView()
    private let scroller = UIScrollView()
    private var chips: [UIButton] = []
    private var chipValues: [AnyHashable?] = []
    private var guardUntil: TimeInterval = 0

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        chevron.configuration = .plain()
        chevron.configurationUpdateHandler = { [weak self] button in self?.style(button, selected: false) }
        chevron.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        chevron.addTarget(self, action: #selector(keyDown), for: .touchDown)
        addSubview(chevron)
        divider.isUserInteractionEnabled = false
        addSubview(divider)
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = false
        scroller.delaysContentTouches = false
        scroller.isHidden = true
        addSubview(scroller)
        turnChevron(animated: false)
        rebuild(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Opens a page, or closes with nil. `completion` runs once the chips have left, so the
    /// words can come back after them rather than under them.
    func show(_ page: Page?, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard page != self.page else {
            completion?()
            return
        }
        let wasOpen = isOpen
        self.page = page
        turnChevron(animated: animated)
        UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.divider.alpha = self.dividerAlpha
        }
        updateAccessibility()
        guard let page else {
            leave(chips, animated: animated) { [weak self] in
                guard let self, !self.isOpen else { return }
                self.scroller.isHidden = true
                completion?()
            }
            chips = []
            chipValues = []
            return
        }
        let old = chips
        chips = []
        if wasOpen {
            guardUntil = CACurrentMediaTime() + Self.pageGuard
            leave(old, animated: animated, slide: -8, completion: nil)
        }
        scroller.contentOffset = .zero
        scroller.isHidden = false
        rebuild(animated: animated)
        completion?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        isOpen ? bounds.contains(point) : chevron.alpha > 0.01 && chevron.frame.contains(point)
    }

    // MARK: - Chips

    private var dividerAlpha: CGFloat { isOpen || hidesChevron ? 0 : 1 }

    private func rebuild(animated: Bool) {
        divider.backgroundColor = palette.stripDivider
        chips.forEach { $0.removeFromSuperview() }
        var made: [(UIButton, AnyHashable?)] = []
        switch page {
        case .items(let items):
            made = items.map { item in
                let chip = makeChip(symbol: item.symbol, title: nil) { [weak self] in self?.onItem?(item) }
                chip.accessibilityLabel = item.title
                return (chip, AnyHashable(item))
            }
        case .styles:
            made = DictationStyle.allCases.map { option in
                (makeChip(symbol: nil, title: option.label) { [weak self] in self?.onStyle?(option) }, AnyHashable(option))
            }
        case .languages:
            made = languages.map { entry in
                (makeChip(symbol: nil, title: entry.name) { [weak self] in self?.onLanguage?(entry.id) }, entry.id.map(AnyHashable.init))
            }
        case nil:
            break
        }
        chips = made.map(\.0)
        chipValues = made.map(\.1)
        chips.forEach(scroller.addSubview)
        refreshSelection()
        updateAccessibility()
        setNeedsLayout()
        layoutIfNeeded()
        if animated { enter(chips) }
    }

    private func isSelected(_ value: AnyHashable?) -> Bool {
        switch page {
        case .items: value == AnyHashable(WormaTrayItem.translate) && isTranslating
        case .styles: value == AnyHashable(style)
        case .languages: value == language.map(AnyHashable.init)
        case nil: false
        }
    }

    private func refreshSelection() {
        for (chip, value) in zip(chips, chipValues) {
            let selected = isSelected(value)
            chip.isSelected = selected
            chip.accessibilityTraits = selected ? [.button, .selected] : .button
            if case .items = page, value == AnyHashable(WormaTrayItem.translate) {
                chip.accessibilityValue = isTranslating ? String(localized: "On") : String(localized: "Off")
            }
            chip.setNeedsUpdateConfiguration()
        }
    }

    private func makeChip(symbol: String?, title: String?, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        if let symbol {
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium))
        }
        if let title {
            config.attributedTitle = AttributedString(title)
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        config.background.cornerRadius = 0
        let chip = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            guard let self, CACurrentMediaTime() >= self.guardUntil else { return }
            action()
        })
        chip.configurationUpdateHandler = { [weak self] button in self?.style(button, selected: button.isSelected) }
        chip.addTarget(self, action: #selector(keyDown), for: .touchDown)
        chip.addTarget(self, action: #selector(pressIn(_:)), for: [.touchDown, .touchDragEnter])
        chip.addTarget(self, action: #selector(pressOut(_:)), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
        return chip
    }

    /// A capsule behind a chip while it's chosen or held, as the strip's words get.
    private func style(_ button: UIButton, selected: Bool) {
        guard var config = button.configuration else { return }
        let held = button.isHighlighted
        let color = selected ? palette.selectText : palette.stripText
        config.baseForegroundColor = color
        if let title = config.attributedTitle.map({ String($0.characters) }) {
            var text = AttributedString(title)
            text.font = UIFont.systemFont(ofSize: 17, weight: selected ? .medium : .regular)
            text.foregroundColor = color
            config.attributedTitle = text
        }
        config.background.backgroundColor = selected ? palette.selectFill : (held ? palette.stripPillPressedFill : .clear)
        config.background.cornerRadius = pillHeight / 2
        config.background.backgroundInsets = pillInsets(for: button)
        // An icon chip is the strip's full height: its symbol sits on the words' line.
        if config.image != nil, button !== chevron {
            let offset = textCenterY - button.frame.midY
            config.contentInsets.top = max(0, 2 * offset)
            config.contentInsets.bottom = max(0, -2 * offset)
        }
        button.configuration = config
    }

    private var pillHeight: CGFloat { min(chipHeight, bounds.height) }

    /// Icons fill their whole share of the strip for the touch, with a capsule of the chip's
    /// height (about as wide) drawn in the middle.
    private func pillInsets(for button: UIButton) -> NSDirectionalEdgeInsets {
        let h = min(pillHeight, button.bounds.height)
        let top = max(0, min(button.bounds.height - h, textCenterY - h / 2 - button.frame.minY))
        let bottom = max(0, button.bounds.height - top - h)
        let width = button.configuration?.image != nil ? h + 16 : button.bounds.width
        let horizontal = max(0, (button.bounds.width - width) / 2)
        return NSDirectionalEdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal)
    }

    @objc private func keyDown() { onKeyDown?() }

    @objc private func pressIn(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc private func pressOut(_ sender: UIButton) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            sender.transform = .identity
        }
    }

    // MARK: - Motion

    /// Toward the chevron, in points along x.
    private var towardChevron: CGFloat { hexOnLeading ? -1 : 1 }

    private func enter(_ entering: [UIButton]) {
        if reduceMotion {
            entering.forEach { $0.alpha = 0 }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction]) {
                entering.forEach { $0.alpha = 1 }
            }
            return
        }
        let order = hexOnLeading ? entering : entering.reversed()
        for (index, chip) in order.enumerated() {
            chip.alpha = 0
            chip.transform = CGAffineTransform(translationX: 12 * towardChevron, y: 0).scaledBy(x: 0.85, y: 0.85)
            UIView.animate(
                withDuration: 0.35,
                delay: 0.06 + Double(index) * 0.02,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                chip.alpha = 1
                chip.transform = .identity
            }
        }
    }

    private func leave(_ leaving: [UIButton], animated: Bool, slide: CGFloat? = nil, completion: (() -> Void)?) {
        guard animated, !leaving.isEmpty else {
            leaving.forEach { $0.removeFromSuperview() }
            completion?()
            return
        }
        leaving.forEach { $0.isUserInteractionEnabled = false }
        let dx = slide ?? 10 * towardChevron
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            for chip in leaving {
                chip.alpha = 0
                if !self.reduceMotion {
                    chip.transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: 0.9, y: 0.9)
                }
            }
        } completion: { _ in
            leaving.forEach { $0.removeFromSuperview() }
            completion?()
        }
    }

    /// One chevron that turns: closed it points into the strip, away from the key; open, back.
    private func turnChevron(animated: Bool) {
        if chevron.configuration?.image == nil {
            var config = chevron.configuration ?? .plain()
            config.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            chevron.configuration = config
        }
        let mirror = CGAffineTransform(scaleX: hexOnLeading ? -1 : 1, y: 1)
        let target = isOpen ? mirror.rotated(by: .pi) : mirror
        guard animated, !reduceMotion else {
            chevron.transform = target
            return
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.chevron.transform = target
        }
    }

    private func updateAccessibility() {
        chevron.accessibilityLabel = switch page {
        case nil: String(localized: "Dictation shortcuts")
        case .items: String(localized: "Close shortcuts")
        case .styles, .languages: String(localized: "Back to shortcuts")
        }
        accessibilityElements = chips + [chevron]
        if isOpen { UIAccessibility.post(notification: .layoutChanged, argument: chips.first) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = Self.chevronWidth
        let transform = chevron.transform
        chevron.transform = .identity
        // Centred on the words' line by its frame, not insets, which its turn would flip.
        chevron.frame = CGRect(x: hexOnLeading ? 0 : bounds.width - w, y: textCenterY - bounds.height / 2, width: w, height: bounds.height)
        chevron.transform = transform
        let lineH = min(24, chipHeight, bounds.height - 2)
        divider.frame = CGRect(x: hexOnLeading ? w : bounds.width - w - 1, y: textCenterY - lineH / 2, width: 1, height: lineH)
        let area = CGRect(x: hexOnLeading ? w : 0, y: 0, width: max(0, bounds.width - w), height: bounds.height)
        scroller.frame = area
        let h = pillHeight
        // Icons share the strip evenly and take its whole height (a button's own fitting
        // width can overflow it); text chips that don't fit scroll.
        let spread = page.map { if case .items = $0 { true } else { false } } ?? false
        let gap: CGFloat = spread ? 0 : 4
        let widths = spread && !chips.isEmpty
            ? Array(repeating: area.width / CGFloat(chips.count), count: chips.count)
            : chips.map { max(h + 8, $0.sizeThatFits(CGSize(width: area.width, height: h)).width) }
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, chips.count - 1))
        var x = total < area.width && !spread ? (area.width - total) / 2 : 0
        let y = spread ? 0 : max(0, textCenterY - h / 2)
        let chipH = spread ? bounds.height : h
        for (chip, width) in zip(chips, widths) {
            let transform = chip.transform
            chip.transform = .identity
            chip.frame = CGRect(x: x, y: y, width: width, height: chipH)
            chip.transform = transform
            chip.setNeedsUpdateConfiguration()
            x += width + gap
        }
        scroller.contentSize = CGSize(width: max(area.width, x - gap), height: bounds.height)
    }

    @objc private func chevronTapped() { onChevron?() }
}

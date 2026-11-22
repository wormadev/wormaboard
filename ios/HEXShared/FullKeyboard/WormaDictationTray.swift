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
/// the end beside the mic, and while open a row of shortcuts in place of the suggestions
/// (or a style's or language's chips). Closed, only the chevron takes touches.
@MainActor
final class WormaDictationTrayView: UIView {
    enum Page: Equatable {
        case items([WormaTrayItem])
        case styles
        case languages
    }

    static let chevronWidth: CGFloat = 32

    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { rebuild() } } }
    var hexOnLeading = false { didSet { if hexOnLeading != oldValue { rebuild() } } }
    var textCenterY: CGFloat = 19 { didSet { if textCenterY != oldValue { setNeedsLayout() } } }
    var chipHeight: CGFloat = 30 { didSet { if chipHeight != oldValue { setNeedsLayout() } } }
    var hidesChevron = false { didSet { chevron.isHidden = hidesChevron } }
    /// What the chips show as chosen.
    var isTranslating = false { didSet { if isTranslating != oldValue { rebuild() } } }
    var style: DictationStyle = .polished { didSet { if style != oldValue { rebuild() } } }
    /// Automatic (nil) first, then the quick choices, with their names.
    var languages: [(id: String?, name: String)] = [] { didSet { rebuild() } }
    var language: String? { didSet { if language != oldValue { rebuild() } } }

    var onChevron: (() -> Void)?
    var onItem: ((WormaTrayItem) -> Void)?
    var onStyle: ((DictationStyle) -> Void)?
    var onLanguage: ((String?) -> Void)?

    private(set) var page: Page?
    var isOpen: Bool { page != nil }
    private let chevron = UIButton(type: .system)
    private let scroller = UIScrollView()
    private var chips: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        chevron.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        addSubview(chevron)
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = false
        scroller.delaysContentTouches = false
        addSubview(scroller)
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ page: Page?) {
        guard page != self.page else { return }
        self.page = page
        scroller.contentOffset = .zero
        rebuild()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        isOpen ? bounds.contains(point) : !chevron.isHidden && chevron.frame.contains(point)
    }

    private func rebuild() {
        let pointsAway = !isOpen
        // Closed it points into the strip, away from the key; open, back toward it.
        let symbol = (pointsAway != hexOnLeading) ? "chevron.left" : "chevron.right"
        chevron.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        chevron.tintColor = palette.stripText
        chevron.accessibilityLabel = isOpen ? String(localized: "Close shortcuts") : String(localized: "Dictation shortcuts")

        chips.forEach { $0.removeFromSuperview() }
        chips = []
        switch page {
        case .items(let items):
            chips = items.map { item in
                let chip = makeChip(symbol: item.symbol, title: nil, selected: item == .translate && isTranslating) { [weak self] in
                    self?.onItem?(item)
                }
                chip.accessibilityLabel = item.title
                if item == .translate { chip.accessibilityValue = isTranslating ? String(localized: "On") : String(localized: "Off") }
                return chip
            }
        case .styles:
            chips = DictationStyle.allCases.map { option in
                makeChip(symbol: nil, title: option.label, selected: option == style) { [weak self] in self?.onStyle?(option) }
            }
        case .languages:
            chips = languages.map { entry in
                makeChip(symbol: nil, title: entry.name, selected: entry.id == language) { [weak self] in self?.onLanguage?(entry.id) }
            }
        case nil:
            break
        }
        chips.forEach(scroller.addSubview)
        scroller.isHidden = !isOpen
        setNeedsLayout()
    }

    private func makeChip(symbol: String?, title: String?, selected: Bool, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        if let symbol {
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        }
        if let title {
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15.5, weight: selected ? .medium : .regular)]))
        }
        config.baseForegroundColor = selected ? palette.selectText : palette.stripText
        config.background.backgroundColor = selected ? palette.selectFill : .clear
        config.background.cornerRadius = 9
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        let chip = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        chip.accessibilityTraits = selected ? [.button, .selected] : .button
        return chip
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = Self.chevronWidth
        chevron.frame = CGRect(x: hexOnLeading ? 0 : bounds.width - w, y: 0, width: w, height: bounds.height)
        let area = CGRect(x: hexOnLeading ? w : 0, y: 0, width: max(0, bounds.width - w), height: bounds.height)
        scroller.frame = area
        let h = min(chipHeight, bounds.height)
        let y = max(0, textCenterY - h / 2)
        // Icons share the strip evenly (a button's own fitting width can overflow it); text
        // chips that don't fit scroll.
        let spread = page.map { if case .items = $0 { true } else { false } } ?? false
        let gap: CGFloat = spread ? 0 : 4
        let widths = spread && !chips.isEmpty
            ? Array(repeating: area.width / CGFloat(chips.count), count: chips.count)
            : chips.map { max(h + 8, $0.sizeThatFits(CGSize(width: area.width, height: h)).width) }
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, chips.count - 1))
        let step = spread && total < area.width && !chips.isEmpty ? (area.width - total) / CGFloat(chips.count) : 0
        var x = total < area.width && !spread ? (area.width - total) / 2 : step / 2
        for (chip, width) in zip(chips, widths) {
            chip.frame = CGRect(x: x, y: y, width: width, height: h)
            x += width + gap + step
        }
        scroller.contentSize = CGSize(width: max(area.width, x - gap - step / 2), height: bounds.height)
    }

    @objc private func chevronTapped() { onChevron?() }
}

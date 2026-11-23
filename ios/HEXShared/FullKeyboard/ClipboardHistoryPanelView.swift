import UIKit
import UniformTypeIdentifiers

/// Settings › Experiments › Clipboard history's list: it covers the keys as the emoji panel
/// does, with ABC (back to the keys) and Clear all on the strip's line and the copies below,
/// newest first: texts, image thumbnails and named files. Tapping a text inserts it; an image or
/// file goes back on the clipboard to paste. Its ✕ forgets it. Clear all asks once more first.
@MainActor
final class ClipboardHistoryPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    var metrics = KeyboardMetrics.portrait { didSet { if metrics != oldValue { setNeedsLayout() } } }
    var horizontalInset: CGFloat = 0 { didSet { if horizontalInset != oldValue { setNeedsLayout() } } }
    var onInsert: ((ClipboardItem) -> Void)?
    var onRemove: ((ClipboardItem) -> Void)?
    var onClear: (() -> Void)?
    var onLetters: (() -> Void)?
    var onKeyDown: (() -> Void)?

    private(set) var items: [ClipboardItem]
    private let history: ClipboardHistory
    private var thumbnails: [String: UIImage] = [:]
    private let lettersChip = UIButton(type: .custom)
    private let clearChip = UIButton(type: .custom)
    private let table = UITableView(frame: .zero, style: .plain)
    private var confirmingClear = false

    init(items: [ClipboardItem], history: ClipboardHistory) {
        self.items = items
        self.history = history
        super.init(frame: .zero)
        lettersChip.configuration = Self.chip(title: "ABC")
        lettersChip.accessibilityLabel = String(localized: "Back to the keys")
        lettersChip.addTarget(self, action: #selector(handleLetters), for: .touchUpInside)
        clearChip.configuration = Self.chip(title: String(localized: "Clear all"))
        clearChip.addTarget(self, action: #selector(handleClear), for: .touchUpInside)
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 44
        table.register(UITableViewCell.self, forCellReuseIdentifier: "copy")
        for view in [table, lettersChip, clearChip] as [UIView] { addSubview(view) }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func chip(title: String) -> UIButton.Configuration {
        var chip = UIButton.Configuration.plain()
        chip.title = title
        chip.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        chip.background.cornerRadius = 15
        return chip
    }

    func setItems(_ items: [ClipboardItem]) {
        self.items = items
        table.reloadData()
    }

    private func applyPalette() {
        for button in [lettersChip, clearChip] {
            var chip = button.configuration
            chip?.baseForegroundColor = palette.textMuted
            chip?.background.backgroundColor = palette.chipFill
            button.configuration = chip
        }
        table.separatorColor = palette.separator
        table.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let band = metrics.stripLineBand
        let chipH = min(30, band.height)
        let chipY = metrics.stripTop + band.top + (band.height - chipH) / 2
        let left = horizontalInset + metrics.side
        let right = bounds.width - horizontalInset - metrics.side
        let lettersW = lettersChip.sizeThatFits(CGSize(width: bounds.width, height: chipH)).width
        lettersChip.frame = CGRect(x: left, y: chipY, width: lettersW, height: chipH)
        let clearW = clearChip.sizeThatFits(CGSize(width: bounds.width, height: chipH)).width
        clearChip.frame = CGRect(x: right - clearW, y: chipY, width: clearW, height: chipH)
        let top = metrics.stripTop + metrics.stripHeight
        table.frame = CGRect(x: horizontalInset, y: top, width: bounds.width - 2 * horizontalInset, height: max(0, bounds.height - top))
    }

    // MARK: - Actions

    @objc private func handleLetters() {
        onKeyDown?()
        onLetters?()
    }

    /// The first tap asks "Clear all?" for three seconds; a second one in that time clears.
    @objc private func handleClear() {
        onKeyDown?()
        guard confirmingClear else {
            confirmingClear = true
            setClearTitle(String(localized: "Clear all?"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.confirmingClear else { return }
                self.confirmingClear = false
                self.setClearTitle(String(localized: "Clear all"))
            }
            return
        }
        confirmingClear = false
        onClear?()
    }

    private func setClearTitle(_ title: String) {
        var chip = clearChip.configuration
        chip?.title = title
        clearChip.configuration = chip
        setNeedsLayout()
    }

    @objc private func handleRemove(_ sender: UIButton) {
        guard items.indices.contains(sender.tag) else { return }
        onKeyDown?()
        onRemove?(items[sender.tag])
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "copy", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = palette.textBase
        content.textProperties.font = .systemFont(ofSize: 16)
        content.textProperties.numberOfLines = 2
        switch item.kind {
        case .text:
            content.text = item.text
        case .image:
            content.text = String(localized: "Image")
            content.image = thumbnail(for: item)
            content.imageProperties.maximumSize = CGSize(width: 56, height: 56)
            content.imageProperties.cornerRadius = 6
        case .file:
            content.text = item.name ?? String(localized: "File")
            content.secondaryText = item.type.flatMap { UTType($0)?.localizedDescription }
            content.secondaryTextProperties.color = palette.textMuted
            content.image = UIImage(systemName: "doc")
            content.imageProperties.tintColor = palette.textMuted
        }
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.selectedBackgroundView = UIView()
        cell.selectedBackgroundView?.backgroundColor = palette.selectFill
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
        remove.tintColor = palette.textMuted
        remove.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        remove.tag = indexPath.row
        remove.accessibilityLabel = String(localized: "Remove")
        remove.addTarget(self, action: #selector(handleRemove(_:)), for: .touchUpInside)
        cell.accessoryView = remove
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard items.indices.contains(indexPath.row) else { return }
        onKeyDown?()
        onInsert?(items[indexPath.row])
    }

    /// Images are shown small; the thumbnail is made once per item.
    private func thumbnail(for item: ClipboardItem) -> UIImage? {
        guard let file = item.file else { return nil }
        if let cached = thumbnails[file] { return cached }
        let image = history.data(of: item).flatMap(UIImage.init(data:))?
            .preparingThumbnail(of: CGSize(width: 112, height: 112))
        thumbnails[file] = image
        return image
    }
}

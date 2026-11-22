import UIKit

/// The GIF search's results above the strip: one sideways row of KLIPY stills, a quiet line
/// when there's nothing to show, and KLIPY's attribution. Small JPG stills rather
/// than animations keep the keyboard far under its memory ceiling; at most four load at once,
/// their cache is capped, and all of it goes with the view.
@MainActor
final class GifResultsView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    static let maxLoads = 4
    static let attributionHeight: CGFloat = 16

    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyPalette() } } }
    /// What the row says instead of GIFs: loading, nothing found, or why it failed.
    var message: String? { didSet { refreshMessage() } }
    var onPick: ((Int) -> Void)?
    /// Fetches a still's bytes (the gated KLIPY client).
    var loadStill: ((URL) async throws -> Data)?

    private(set) var items: [KlipyGif] = []
    private let layout = UICollectionViewFlowLayout()
    private let collection: UICollectionView
    private let messageLabel = UILabel()
    private let attribution = UILabel()
    private let images = NSCache<NSURL, UIImage>()
    private var waiting: [URL] = []
    private var loading: [URL: Task<Void, Never>] = [:]

    override init(frame: CGRect) {
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 4
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        images.totalCostLimit = 4_000_000
        images.countLimit = 60
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.delaysContentTouches = false
        collection.isPrefetchingEnabled = false
        collection.hideEdgeEffects()
        collection.dataSource = self
        collection.delegate = self
        collection.register(GifCell.self, forCellWithReuseIdentifier: GifCell.reuseID)
        addSubview(collection)
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        addSubview(messageLabel)
        attribution.text = String(localized: "Powered by KLIPY")
        attribution.font = .systemFont(ofSize: 10, weight: .semibold)
        attribution.textAlignment = .right
        addSubview(attribution)
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setItems(_ items: [KlipyGif]) {
        cancelLoads()
        self.items = items
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
        refreshMessage()
    }

    /// Stops every load and drops every still, for a memory warning or the view's end.
    func purge() {
        cancelLoads()
        images.removeAllObjects()
    }

    private func cancelLoads() {
        for task in loading.values { task.cancel() }
        loading = [:]
        waiting = []
    }

    private func refreshMessage() {
        messageLabel.text = message
        messageLabel.isHidden = message == nil
        collection.alpha = message == nil ? 1 : 0.35
    }

    private func applyPalette() {
        messageLabel.textColor = palette.textMuted
        attribution.textColor = palette.textMuted
        collection.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rowHeight = max(1, bounds.height - Self.attributionHeight)
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: rowHeight)
        messageLabel.frame = collection.frame
        attribution.frame = CGRect(x: 0, y: rowHeight, width: bounds.width - 4, height: Self.attributionHeight)
        layout.sectionInset = UIEdgeInsets(top: 4, left: 0, bottom: 2, right: 0)
        layout.invalidateLayout()
    }

    // MARK: - Stills

    private func request(_ url: URL) {
        guard images.object(forKey: url as NSURL) == nil, loading[url] == nil, !waiting.contains(url) else { return }
        waiting.append(url)
        pump()
    }

    /// Starts waiting loads, newest first (the cells just shown), up to `maxLoads`.
    private func pump() {
        while loading.count < Self.maxLoads, let url = waiting.popLast() {
            guard let loadStill else { return }
            loading[url] = Task { [weak self] in
                let data = try? await loadStill(url)
                guard !Task.isCancelled else { return }
                self?.finish(url, data: data)
            }
        }
    }

    /// A failed still leaves its tile blank; the GIF can still be copied.
    private func finish(_ url: URL, data: Data?) {
        loading[url] = nil
        if let data, let image = UIImage(data: data) {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
            images.setObject(image, forKey: url as NSURL, cost: cost)
            for case let cell as GifCell in collection.visibleCells where cell.url == url {
                cell.image = image
            }
        }
        pump()
    }

    // MARK: - Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GifCell.reuseID, for: indexPath)
        guard let cell = cell as? GifCell else { return cell }
        let gif = items[indexPath.item]
        cell.url = gif.still.url
        cell.backgroundColor = palette.chipFill
        cell.accessibilityLabel = gif.title.isEmpty ? "GIF" : gif.title
        cell.image = images.object(forKey: gif.still.url as NSURL)
        if cell.image == nil { request(gif.still.url) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifCell else { return }
        if let url = cell.url { waiting.removeAll { $0 == url } }
        cell.url = nil
        cell.image = nil
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let height = max(1, collectionView.bounds.height - 6)
        let still = items[indexPath.item].still
        let width = height * CGFloat(still.width) / CGFloat(still.height)
        return CGSize(width: min(2 * height, max(0.6 * height, width)), height: height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPick?(indexPath.item)
    }
}

@MainActor
private final class GifCell: UICollectionViewCell {
    static let reuseID = "gif"
    private let imageView = UIImageView()
    var url: URL?

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
    }
}

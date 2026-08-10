//
//  TheaterChrome.swift
//  BilibiliLive
//
//  The chrome that appears once the player docks: the pane switcher, the mini
//  transport under the picture, and the two simple panes (简介 / 选集).
//
//  All geometry is in 1920×1080 points, scaled from the container — see
//  `Theater.Metrics`.
//

import Kingfisher
import SnapKit
import UIKit

// MARK: - Chip bar

/// Horizontal pane switcher.
///
/// Built from the home screen's own `ChipButton` rather than a lookalike, so the
/// player's chips and the index chips can never drift apart — same 80pt height,
/// same radius, same inset, same type ramp. It also inherits the right state
/// model, which a private copy had got wrong: **selection is the fill, focus is
/// the ring**. Filling on focus too made two chips read as selected at once.
final class TheaterChipBar: UIView {
    var onSelect: ((TheaterPane) -> Void)?

    /// `.overlay` for the full-bleed transport, where the row sits on the
    /// picture; the docked panel keeps `.surface`, its own ground being opaque.
    ///
    /// Spacing no longer opens up with it. It used to, because `DS.Chip.gap` was
    /// half what the reference sets its chips apart and the overlay row was the
    /// one place that showed it; the gap is transcribed from the reference now,
    /// so both grounds want the same one.
    var style: ChipButton.Style = .surface {
        didSet {
            buttons.forEach { $0.style = style }
            // Overlay bars hug their content, so the row can be right-aligned
            // to the margin: a fixed width wider than the chips left them
            // floating short of it. The docked panel keeps its given width and
            // scrolls, which is the case that actually needs to.
            if style == .overlay, hugsContent == nil {
                snp.makeConstraints {
                    hugsContent = $0.width.equalTo(stack.snp.width)
                        .offset(scrollView.contentInset.left + scrollView.contentInset.right)
                        .constraint
                }
            }
        }
    }

    private var hugsContent: Constraint?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [ChipButton] = []
    private var selected: TheaterPane?

    /// Scrolls, like ChipBarView does. Four icon chips at the full
    /// `DS.Chip.hInset` come to ~800pt and the docked panel is 587pt wide, so
    /// something has to give — and it should not be the chip spec. The focus
    /// engine brings the focused chip into view, which is also what the
    /// reference recording's own chip row did.
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Clip to the column. Unclipped, a chip scrolled past the leading edge
        // kept on drawing and landed on top of the docked video — the bar has to
        // stay inside its own strip no matter where the row is scrolled to.
        clipsToBounds = true
        // The scroll view must NOT clip as well, or it would shave the focus
        // ring off vertically; the bar is taller than a chip precisely so that
        // ring has somewhere to go.
        scrollView.clipsToBounds = false
        scrollView.showsHorizontalScrollIndicator = false
        // Horizontal breathing room so clipping the bar does not cut the ring
        // off the first and last chip.
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.axis = .horizontal
        stack.spacing = DS.Chip.gap
        stack.alignment = .center

        addSubview(scrollView)
        scrollView.addSubview(stack)
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.centerY.equalToSuperview()
            make.height.equalTo(DS.Chip.height)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
        }
        buttons = TheaterPane.allCases.map { pane in
            let b = ChipButton(title: pane.title, symbol: pane.symbol)
            b.scalesOnFocus = false
            b.tag = pane.rawValue
            b.addTarget(self, action: #selector(tapped(_:)), for: .primaryActionTriggered)
            stack.addArrangedSubview(b)
            return b
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `nil` means no pane is open yet, so nothing is filled — the full-bleed
    /// transport starts with every chip unselected.
    func select(_ pane: TheaterPane?) {
        selected = pane
        for b in buttons {
            b.isOn = TheaterPane(rawValue: b.tag) == pane
        }
    }

    @objc private func tapped(_ sender: ChipButton) {
        guard let pane = TheaterPane(rawValue: sender.tag) else { return }
        onSelect?(pane)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let selected, let match = buttons.first(where: { $0.tag == selected.rawValue }) {
            return [match]
        }
        return buttons.first.map { [$0] } ?? []
    }
}

// MARK: - Mini transport

/// The now-playing block under the docked picture: cover, title and owner, then
/// the progress bar with elapsed and total under its two ends.
///
/// Read-only. Seeking stays with the full-bleed transport, where the remote's
/// touch surface maps to the scrubber — nothing here takes focus, so the panel
/// is always one press away.
final class TheaterMiniBar: UIView {
    var titleText: String? {
        didSet { titleLabel.text = titleText }
    }

    var ownerText: String? {
        didSet {
            ownerLabel.text = ownerText
            ownerLabel.isHidden = ownerText?.isEmpty ?? true
        }
    }

    var coverURL: URL? {
        didSet {
            guard coverURL != oldValue else { return }
            coverView.kf.setImage(
                with: coverURL,
                options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 426, height: 240))),
                          .cacheOriginalImage])
        }
    }

    /// Cover height; the width follows from 16:9. The whole block is measured
    /// from this — see `Theater.Metrics.miniBarHeight`.
    private let coverHeight: CGFloat = 120

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let ownerLabel = UILabel()
    private let currentLabel = UILabel()
    private let totalLabel = UILabel()

    /// Two plain views rather than `UIProgressView`: the stock bar shades its
    /// own track and insets the fill, so it never read as the flat pair of tones
    /// it is meant to be — white elapsed over one solid grey, no tint.
    private let track = UIView()
    private let fill = UIView()
    private let barHeight: CGFloat = 6

    /// Solid, not white-with-alpha. A translucent track picks up whatever sits
    /// behind the column and stops being a single neutral grey.
    private static let trackColor = UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(rgb: 0xC6_C6_C6) : UIColor(rgb: 0x4A_4A_4A)
    }

    private var ratio: Double = 0
    private var fillWidth: CGFloat = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.backgroundColor = DS.Color.surface
        coverView.layer.cornerRadius = 12
        coverView.layer.cornerCurve = .continuous

        titleLabel.font = DS.Font.cardTitle
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.numberOfLines = 2
        ownerLabel.font = DS.Font.meta
        ownerLabel.textColor = DS.Color.textSecondary

        [currentLabel, totalLabel].forEach {
            $0.font = DS.Font.badge
            $0.textColor = DS.Color.textSecondary
        }
        totalLabel.textAlignment = .right

        track.backgroundColor = Self.trackColor
        fill.backgroundColor = DS.Color.textPrimary

        let text = UIStackView(arrangedSubviews: [titleLabel, ownerLabel])
        text.axis = .vertical
        text.spacing = 8

        addSubview(coverView)
        addSubview(text)
        addSubview(track)
        track.addSubview(fill)
        addSubview(currentLabel)
        addSubview(totalLabel)

        coverView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.height.equalTo(coverHeight)
            make.width.equalTo(coverView.snp.height).multipliedBy(16.0 / 9.0)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(coverView.snp.trailing).offset(DS.Space.m)
            make.trailing.equalToSuperview()
            make.centerY.equalTo(coverView)
        }
        // Pinned to the bottom rather than stacked under the cover: the bar is
        // the block's baseline, and the gap above it is what makes the cover row
        // read as a separate line rather than a caption on the bar.
        currentLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
        }
        totalLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.firstBaseline.equalTo(currentLabel)
        }
        track.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(currentLabel.snp.top).offset(-10)
            make.height.equalTo(barHeight)
        }
        fill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.layer.cornerRadius = barHeight / 2
        fill.layer.cornerRadius = barHeight / 2
        applyRatio()
    }

    func update(current: Double, total: Double) {
        ratio = total > 0 ? max(0, min(1, current / total)) : 0
        applyRatio()
        currentLabel.text = TimeInterval(current).timeString()
        totalLabel.text = TimeInterval(total).timeString()
    }

    /// Width in points rather than a multiplier so the same call can run from
    /// `layoutSubviews` — guarded on the value, or re-setting it there would
    /// invalidate the layout it was called from on every pass.
    private func applyRatio() {
        let w = (track.bounds.width * ratio).rounded()
        guard w != fillWidth else { return }
        fillWidth = w
        fill.snp.updateConstraints { $0.width.equalTo(w) }
    }
}

// MARK: - 简介

/// Description block, then 相关推荐 as a list.
///
/// A collection view rather than the scroll view this used to be: a tvOS scroll
/// view with nothing focusable inside it cannot be scrolled at all, so a long
/// description was simply cut off. Every row here takes focus, which is what
/// makes the pane reachable — and it is also where the second copy of the
/// related videos lives, under the text, as a list instead of a rail.
final class TheaterInfoPane: UIViewController {
    var detail: VideoDetail? {
        didSet {
            guard isViewLoaded else { return }
            collectionView.reloadData()
        }
    }

    var related: [VideoDetail.Info] = [] {
        didSet {
            guard isViewLoaded else { return }
            collectionView.reloadData()
        }
    }

    var onSelectRelated: ((VideoDetail.Info) -> Void)?

    private enum Section: Int, CaseIterable { case about, related }

    /// The description collapses to a readable stub and opens in place on
    /// select — the same "no second screen" rule the comments follow.
    private var descExpanded = false

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, _ in
            let estimated: CGFloat = Section(rawValue: index) == .about ? 320 : 136
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimated)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimated)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 0, leading: 4, bottom: DS.Space.l, trailing: 4)
            if Section(rawValue: index) == .related, self?.related.isEmpty == false {
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(56)),
                        elementKind: UICollectionView.elementKindSectionHeader, alignment: .top),
                ]
            }
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.clipsToBounds = true
        cv.remembersLastFocusedIndexPath = true
        return cv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }
        collectionView.register(TheaterInfoBlockCell.self,
                                forCellWithReuseIdentifier: TheaterInfoBlockCell.identifier)
        collectionView.register(TheaterRelatedRowCell.self,
                                forCellWithReuseIdentifier: TheaterRelatedRowCell.identifier)
        collectionView.register(TheaterSectionHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: TheaterSectionHeader.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
    }
}

extension TheaterInfoPane: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in _: UICollectionView) -> Int { Section.allCases.count }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Section(rawValue: section) == .about ? (detail == nil ? 0 : 1) : related.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if Section(rawValue: indexPath.section) == .about {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterInfoBlockCell.identifier,
                                              for: indexPath) as! TheaterInfoBlockCell
            cell.configure(detail, expanded: descExpanded)
            return cell
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterRelatedRowCell.identifier,
                                          for: indexPath) as! TheaterRelatedRowCell
        cell.configure(related[indexPath.item])
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView
    {
        let header = cv.dequeueReusableSupplementaryView(ofKind: kind,
                                                         withReuseIdentifier: TheaterSectionHeader.identifier,
                                                         for: indexPath) as! TheaterSectionHeader
        header.label.text = "相关推荐"
        return header
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section) {
        case .about:
            descExpanded.toggle()
            cv.reloadItems(at: [indexPath])
        case .related:
            onSelectRelated?(related[indexPath.item])
        case .none:
            break
        }
    }
}

/// Stats, owner and description. Focusable so the pane can be scrolled to it
/// and so the description can be opened; the focus state is a ring rather than
/// the row fill — inverting a paragraph of text reads as an error.
final class TheaterInfoBlockCell: UICollectionViewCell {
    static let identifier = String(describing: TheaterInfoBlockCell.self)

    private let statsLabel = UILabel()
    private let ownerLabel = UILabel()
    private let descLabel = UILabel()
    private let moreLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = DS.Radius.railRow
        contentView.layer.cornerCurve = .continuous

        statsLabel.font = DS.Font.badge
        statsLabel.textColor = DS.Color.textTertiary
        statsLabel.numberOfLines = 0
        ownerLabel.font = DS.Font.meta
        ownerLabel.textColor = DS.Color.textPrimary
        descLabel.font = DS.Font.meta
        descLabel.textColor = DS.Color.textSecondary
        descLabel.numberOfLines = 6
        moreLabel.font = DS.Font.badge
        moreLabel.textColor = DS.Color.accentBlue

        let stack = UIStackView(arrangedSubviews: [statsLabel, ownerLabel, descLabel, moreLabel])
        stack.axis = .vertical
        stack.spacing = DS.Space.s
        stack.setCustomSpacing(DS.Space.xs, after: descLabel)
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DS.Space.xs)
            make.top.bottom.equalToSuperview().inset(DS.Space.xs)
        }
        updateFocusAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ detail: VideoDetail?, expanded: Bool) {
        guard let info = detail?.View else {
            statsLabel.text = nil
            ownerLabel.text = nil
            descLabel.text = "加载中…"
            moreLabel.isHidden = true
            return
        }
        let stats = [
            ("播放", info.stat.view), ("弹幕", info.stat.danmaku), ("点赞", info.stat.like),
            ("投币", info.stat.coin), ("收藏", info.stat.favorite),
        ]
        statsLabel.text = stats.map { "\($0.0) \($0.1.numberString())" }.joined(separator: "   ")
        ownerLabel.text = info.owner.name
        // Both fields are routinely present but empty, so test the content
        // rather than for nil — otherwise the row renders as a blank gap.
        let text = [info.desc, info.dynamic]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "暂无简介"
        descLabel.text = text
        descLabel.numberOfLines = expanded ? 0 : 6
        // Only offer the toggle when there is actually something hidden.
        moreLabel.text = expanded ? "收起" : "展开全部"
        moreLabel.isHidden = !expanded && text.count < 110
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in self?.updateFocusAppearance() }
    }

    private func updateFocusAppearance() {
        contentView.layer.borderWidth = isFocused ? 4 : 0
        contentView.layer.borderColor = DS.Color.ring.cgColor
    }
}

// MARK: - 选集

final class TheaterPagesPane: UIViewController {
    var pages: [VideoPage] = [] {
        didSet {
            guard isViewLoaded else { return }
            collectionView.reloadData()
        }
    }

    var onSelect: ((VideoPage) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(84)))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(84)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 4, bottom: DS.Space.l, trailing: 4)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        cv.backgroundColor = .clear
        // Clips so scrolled rows cannot ride up over the chip bar.
        cv.clipsToBounds = true
        cv.remembersLastFocusedIndexPath = true
        return cv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }
        collectionView.register(TheaterPageCell.self, forCellWithReuseIdentifier: TheaterPageCell.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
    }
}

extension TheaterPagesPane: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { pages.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterPageCell.identifier,
                                          for: indexPath) as! TheaterPageCell
        cell.configure(index: indexPath.item + 1, page: pages[indexPath.item])
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(pages[indexPath.item])
    }
}

/// Flat list row. Nothing is drawn at rest but the text and a hairline; the
/// fill belongs to focus alone, so a column of these reads as one list instead
/// of a stack of cards.
final class TheaterPageCell: TheaterRowCell {
    static let identifier = String(describing: TheaterPageCell.self)
    private let label = UILabel()

    /// One short line per row — the full `vInset` would make a list of parts
    /// twice as tall as it needs to be.
    override var rowInsets: UIEdgeInsets {
        UIEdgeInsets(top: 14, left: Theater.Row.hInset, bottom: 14, right: Theater.Row.hInset)
    }

    override func setup() {
        super.setup()
        label.font = DS.Font.meta
        label.numberOfLines = 2
        rowContent.addSubview(label)
        label.snp.makeConstraints { $0.edges.equalToSuperview() }
        updateRowAppearance()
    }

    func configure(index: Int, page: VideoPage) {
        label.text = "P\(index)  \(page.part)"
        updateRowAppearance()
    }

    override func updateRowAppearance() {
        super.updateRowAppearance()
        label.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
    }
}

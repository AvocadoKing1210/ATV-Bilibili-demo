//
//  HomeViewController.swift
//  BilibiliLive
//
//  The new index page: a chip-indexed set of shelves.
//
//  Shelves load concurrently and independently — one failing endpoint drops
//  its own shelf instead of blanking the screen. Chips are built from the
//  shelves that actually returned content, so the index can never point at
//  a section that is not there.
//

import SnapKit
import UIKit

struct HomeShelf {
    let title: String
    let chip: String
    let subtitle: String?
    let load: () async throws -> [any DisplayData]
}

/// 继续观看 and 历史记录 are the same request — one narrowed to what is
/// resumable, the other not — and they used to issue it twice, concurrently,
/// as part of the same burst.
///
/// That is not merely wasteful. The two calls are indistinguishable to
/// bilibili, arrive together, and 风控 answers duplicates in a burst often
/// enough that one of the pair comes back empty while the other has content —
/// which is exactly the shape of the bug: 历史记录 missing from the index while
/// 继续观看, which can only ever be a *subset* of it, is on screen. One request,
/// awaited by both shelves; a later reload starts a fresh one.
private actor HistoryFetch {
    private var inFlight: Task<[HistoryData], Never>?

    func items() async -> [HistoryData] {
        if let inFlight { return await inFlight.value }
        let task = Task { await WebRequest.requestHistory() }
        inFlight = task
        let items = await task.value
        inFlight = nil
        return items
    }
}

final class HomeViewController: UIViewController, BLTabBarContentVCProtocol {
    private enum Metrics {
        static let headerHeight: CGFloat = 92
    }

    private enum State {
        /// First load — the screen shows skeletons, never a blank canvas.
        case loading
        case loaded
    }

    private let chipBar = ChipBarView()
    private var collectionView: UICollectionView!
    private var loaded: [(shelf: HomeShelf, items: [any DisplayData])] = []
    private var isLoading = false
    private var state: State = .loading
    /// Placeholder shape while loading: enough shelves to fill 1080 and
    /// enough cards to run past the right edge, so the skeleton reads as a
    /// real page rather than a short list.
    private let skeletonShelves = 3
    private let skeletonCards = 4

    /// Shared by the two history shelves so the page issues one history
    /// request, not two. See `HistoryFetch`.
    private let history = HistoryFetch()

    /// Shelves in display order. Titles double as the chip labels where they
    /// are short enough to read at 10 feet.
    ///
    /// 直播 and 热门 are deliberately absent: both are whole destinations on the
    /// rail, and a shelf showing only the first page of one is a worse version
    /// of the page it duplicates. The index leans on what is personal instead.
    private lazy var shelves: [HomeShelf] = {
        // Captures the fetch, not `self` — these closures outlive the property
        // initialiser and must not hold the controller.
        let history = history
        return [
            // Same request as 历史记录 below, narrowed to what is actually
            // resumable — a finished entry has no position to continue from,
            // and without the filter the two shelves would be one list shown
            // twice.
            HomeShelf(title: "继续观看", chip: "继续观看", subtitle: nil) {
                await history.items().filter { $0.progress > 0 && $0.progress < $0.duration }
            },
            HomeShelf(title: "推荐", chip: "推荐", subtitle: "根据观看记录") {
                try await ApiRequest.getFeeds()
            },
            HomeShelf(title: "历史记录", chip: "历史记录", subtitle: "最近看过") {
                await history.items()
            },
            HomeShelf(title: "稍后再看", chip: "稍后再看", subtitle: nil) {
                try await WebRequest.requestToView()
            },
            HomeShelf(title: "每周必看", chip: "每周必看", subtitle: nil) {
                guard let latest = try await WebRequest.requestWeeklyWatchList().first else { return [] }
                return try await WebRequest.requestWeeklyWatch(wid: latest.number)
            },
        ]
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Color.bg
        setupViews()
        reloadData()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionView]
    }

    // MARK: - Layout

    private func setupViews() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.register(HomeCardCell.self, forCellWithReuseIdentifier: HomeCardCell.reuseID)
        collectionView.register(SkeletonCardCell.self, forCellWithReuseIdentifier: SkeletonCardCell.reuseID)
        collectionView.register(
            ShelfHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ShelfHeaderView.reuseID
        )
        collectionView.register(
            SkeletonHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SkeletonHeaderView.reuseID
        )

        view.addSubview(collectionView)
        view.addSubview(chipBar)

        chipBar.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(DS.Chip.barHeight)
        }
        collectionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(chipBar.snp.bottom)
        }
        chipBar.onSelect = { [weak self] index in
            self?.jump(to: index)
        }
        // Shelf names are static, so the index can be real from the first
        // frame rather than a second row of skeletons. It narrows to the
        // shelves that actually returned content once loading finishes.
        chipBar.setTitles(shelves.map(\.chip))
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let containerWidth = environment.container.effectiveContentSize.width
            let columns = DS.columns(forContentWidth: containerWidth)
            let cardWidth = DS.cardWidth(containerWidth: containerWidth, columns: columns)
            // 16:9 thumbnail + title (2 lines) + meta row.
            let cardHeight = cardWidth * 9 / 16 + 150

            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .absolute(cardWidth),
                heightDimension: .absolute(cardHeight)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .absolute(cardWidth),
                    heightDimension: .absolute(cardHeight)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = DS.Space.gutter
            section.orthogonalScrollingBehavior = .continuous
            // Focus grows cards by 8%; without room they clip against the
            // neighbouring shelf.
            section.contentInsets = NSDirectionalEdgeInsets(
                top: DS.Space.s,
                leading: DS.Space.contentLead,
                bottom: DS.Space.shelfGap,
                trailing: DS.Space.safeH
            )
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(Metrics.headerHeight)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                ),
            ]
            return section
        }
    }

    // MARK: - Data

    func reloadData() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            // Shelves are shown as they arrive rather than all at the end. The
            // four endpoints are already concurrent, but draining the whole
            // group before the first reloadData meant the page waited on its
            // slowest one — 推荐 and 热门 usually land while 直播 is still going,
            // and the user sat on a skeleton the whole time.
            var slots = [[any DisplayData]?](repeating: nil, count: shelves.count)
            var didFirstRender = false

            // Before the burst, not alongside it. Every web shelf here is
            // 风控-guarded and answers -352 to a jar with no buvid, and the only
            // thing that installed one was a fire-and-forget call at launch
            // racing this load. On a development machine the fingerprint wins
            // that race; over a television's network it need not, and the
            // shelves that lose it come back empty with nothing to show for it.
            // It is a no-op once the jar has a buvid, so the common path is free.
            await WebRequest.ensureFingerprint()

            await withTaskGroup(of: (Int, [any DisplayData]).self) { group in
                for (index, shelf) in shelves.enumerated() {
                    group.addTask {
                        do {
                            return (index, try await shelf.load())
                        } catch {
                            // Otherwise a failed shelf and an empty one are the
                            // same thing — both just vanish from the index, and
                            // there is no way to tell which happened on a device
                            // you cannot attach a debugger to.
                            Logger.warn("home shelf \(shelf.title) failed: \(error)")
                            return (index, [])
                        }
                    }
                }

                for await (index, items) in group {
                    slots[index] = items

                    // Only commit the leading run of arrived shelves. Inserting
                    // a section *above* one already on screen would shove the
                    // page — and whatever the focus engine is sitting on — down
                    // under the user.
                    let ready = shelves.indices.prefix { slots[$0] != nil }
                        .compactMap { i -> (shelf: HomeShelf, items: [any DisplayData])? in
                            guard let items = slots[i], !items.isEmpty else { return nil }
                            return (shelves[i], items)
                        }
                    guard ready.count > loaded.count else { continue }
                    let inserted = loaded.count..<ready.count
                    loaded = ready

                    if didFirstRender {
                        collectionView.performBatchUpdates {
                            collectionView.insertSections(IndexSet(inserted))
                        }
                    } else {
                        // Skeleton → content changes the section count out from
                        // under the layout; insertSections would trap.
                        didFirstRender = true
                        state = .loaded
                        collectionView.reloadData()
                        // reloadData only *marks* the collection view dirty — it
                        // goes on reporting the skeleton's section count until the
                        // next layout pass. The shelves resume on the same actor,
                        // so the next one can land in this very runloop turn and
                        // insert against that stale count, which traps ("the number
                        // of sections after the update must equal the number before
                        // it, plus or minus the number inserted"). Committing the
                        // reload here is what makes the insert below measure
                        // against the sections actually on screen.
                        collectionView.layoutIfNeeded()
                    }
                }
            }

            // Settle whatever arrived out of order, and narrow the chips once.
            loaded = shelves.indices.compactMap { index in
                guard let items = slots[index], !items.isEmpty else { return nil }
                return (shelves[index], items)
            }
            state = .loaded
            chipBar.setTitles(loaded.map(\.shelf.chip))
            collectionView.reloadData()
            isLoading = false

            // A shelf that returned nothing is dropped silently by design, but
            // *which* ones were dropped is the only clue available when the
            // index comes up short on a real device.
            let missing = shelves.indices
                .filter { slots[$0]?.isEmpty ?? true }
                .map { shelves[$0].title }
            if !missing.isEmpty {
                Logger.warn("home shelves empty: \(missing.joined(separator: ", "))")
            }
        }
    }

    // MARK: - Jump

    private func jump(to section: Int) {
        guard section < loaded.count else { return }
        let indexPath = IndexPath(item: 0, section: section)
        guard let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
            ofKind: UICollectionView.elementKindSectionHeader, at: indexPath
        ) else { return }
        let target = max(0, attrs.frame.minY - collectionView.adjustedContentInset.top)
        collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    /// Keeps the index honest as focus walks the shelves, so the chip
    /// reports where you are rather than where you last pressed.
    private func syncChipToVisibleSection() {
        let y = collectionView.contentOffset.y + 1
        var current = 0
        for section in 0..<loaded.count {
            guard let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: section)
            ) else { continue }
            if attrs.frame.minY <= y { current = section }
        }
        chipBar.setActive(current)
    }
}

// MARK: - Data source

extension HomeViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        state == .loading ? skeletonShelves : loaded.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        state == .loading ? skeletonCards : loaded[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if state == .loading {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: SkeletonCardCell.reuseID, for: indexPath
            )
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeCardCell.reuseID, for: indexPath
        ) as! HomeCardCell
        let item = loaded[indexPath.section].items[indexPath.item]
        cell.configure(with: item)
        // Resume progress is only carried by history entries; everything
        // else has no meaningful position to show.
        if let history = item as? HistoryData, history.duration > 0 {
            cell.setProgress(Double(history.progress) / Double(history.duration))
        } else {
            cell.setProgress(nil)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView
    {
        if state == .loading {
            return collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: SkeletonHeaderView.reuseID, for: indexPath
            )
        }
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: ShelfHeaderView.reuseID, for: indexPath
        ) as! ShelfHeaderView
        let shelf = loaded[indexPath.section].shelf
        view.configure(title: shelf.title, subtitle: shelf.subtitle)
        return view
    }
}

// MARK: - Delegate

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Skeletons are focusable but inert.
        guard state == .loaded, let item = loaded[safe: indexPath.section]?.items[safe: indexPath.item] else { return }
        // Live rooms go straight to the live player, not the video detail.
        if let room = item as? AreaLiveRoom {
            let playerVC = LivePlayerViewController()
            playerVC.room = room.toLiveRoom()
            present(playerVC, animated: true)
            return
        }
        if let room = item as? LiveRoom {
            let playerVC = LivePlayerViewController()
            playerVC.room = room
            present(playerVC, animated: true)
            return
        }
        // History entries carry an optional cid, so they cannot conform to
        // PlayableData — without this branch the 继续观看 shelf falls through
        // every cast and Enter does nothing.
        if let history = item as? HistoryData {
            VideoPlaybackPresenter.present(aid: history.aid, cid: history.cid, title: history.title, from: self)
            return
        }
        if let playable = item as? (any PlayableData) {
            VideoPlaybackPresenter.present(aid: playable.aid, cid: playable.cid, title: playable.title, from: self)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            self?.syncChipToVisibleSection()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        syncChipToVisibleSection()
    }
}

// MARK: - Shelf header

final class ShelfHeaderView: UICollectionReusableView {
    static let reuseID = "ShelfHeaderView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = DS.Font.rowHeader
        titleLabel.textColor = DS.Color.textPrimary
        subtitleLabel.font = DS.Font.meta
        subtitleLabel.textColor = DS.Color.textSecondary

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .horizontal
        stack.spacing = DS.Space.s
        stack.alignment = .lastBaseline
        addSubview(stack)
        stack.snp.makeConstraints { make in
            // The section's contentInsets already lead this in — see
            // SkeletonHeaderView for why adding it again is wrong.
            make.leading.equalToSuperview()
            make.bottom.equalToSuperview().offset(-DS.Space.s)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)
    }
}

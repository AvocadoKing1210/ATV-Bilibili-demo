//
//  FeedCollectionViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/4/5.
//

import SnapKit
import TVUIKit
import UIKit

protocol DisplayData: Hashable {
    var title: String { get }
    var ownerName: String { get }
    var pic: URL? { get }
    var avatar: URL? { get }
    var date: String? { get }
    var overlay: DisplayOverlay? { get }
}

extension DisplayData {
    var avatar: URL? { return nil }
    var date: String? { return nil }
    var overlay: DisplayOverlay? { return nil }
}

struct AnyDispplayData: Hashable {
    let data: any DisplayData

    static func == (lhs: AnyDispplayData, rhs: AnyDispplayData) -> Bool {
        func eq<T: Equatable>(lhs: T, rhs: any Equatable) -> Bool {
            lhs == rhs as? T
        }
        return eq(lhs: lhs.data, rhs: rhs.data)
    }

    func hash(into hasher: inout Hasher) {
        data.hash(into: &hasher)
    }
}

struct DisplayOverlay {
    var leftItems: [DisplayOverlayItem]
    var rightItems: [DisplayOverlayItem]
    var badge: DisplayOverlayBadge?

    init(leftItems: [DisplayOverlayItem], rightItems: [DisplayOverlayItem] = [], badge: DisplayOverlayBadge? = nil) {
        self.leftItems = leftItems
        self.rightItems = rightItems
        self.badge = badge
    }

    struct DisplayOverlayItem {
        var icon: String?
        var text: String
    }

    struct DisplayOverlayBadge {
        var color: UIColor?
        var text: String
    }
}

struct FeedHeaderConfig {
    let elementKind: String
    let estimatedHeight: CGFloat
    let viewProvider: (UICollectionView, String, IndexPath) -> UICollectionReusableView?

    init<T: UICollectionReusableView>(
        viewType: T.Type,
        estimatedHeight: CGFloat = 44,
        configure: @escaping (T, IndexPath) -> Void
    ) {
        elementKind = String(describing: viewType)
        self.estimatedHeight = estimatedHeight

        let registration = UICollectionView.SupplementaryRegistration<T>(elementKind: elementKind) { view, _, indexPath in
            configure(view, indexPath)
        }

        viewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: registration, for: indexPath)
        }
    }
}

class FeedCollectionViewController: UIViewController {
    var collectionView: UICollectionView!

    private enum Section: CaseIterable {
        case main
    }

    var styleOverride: FeedDisplayStyle?
    var didSelect: ((any DisplayData) -> Void)?
    var didLongPress: ((any DisplayData) -> Void)?
    var loadMore: (() -> Void)?
    var finished = false
    var pageSize = 20
    var showHeader: Bool = false
    var headerText = ""
    var customHeaderConfig: FeedHeaderConfig?

    /// Set once a request has actually returned, so an empty feed can be told
    /// apart from a feed that simply hasn't loaded yet.
    private var didCompleteLoad = false
    private lazy var stateView = FeedStateView()

    var displayDatas: [any DisplayData] {
        set {
            didCompleteLoad = true
            _displayData = newValue.map { AnyDispplayData(data: $0) }.uniqued()
            finished = false
        }
        get {
            _displayData.map { $0.data }
        }
    }

    private var _displayData = [AnyDispplayData]() {
        didSet {
            var snapshot = NSDiffableDataSourceSnapshot<Section, AnyDispplayData>()
            snapshot.appendSections(Section.allCases)
            snapshot.appendItems(_displayData, toSection: .main)
            dataSource.apply(snapshot)
            updateEmptyState()
        }
    }

    private var isLoading = false

    /// The same card the index page uses — one card everywhere, per §3.2.
    typealias DisplayCellRegistration = UICollectionView.CellRegistration<HomeCardCell, AnyDispplayData>
    private lazy var dataSource = makeDataSource()

    // MARK: - Public

    func show(in vc: UIViewController) {
        vc.addChild(self)
        vc.view.addSubview(view)
        view.makeConstraintsToBindToSuperview()
        didMove(toParent: vc)
        vc.setContentScrollView(collectionView)
    }

    func appendData(displayData: [any DisplayData]) {
        isLoading = false
        _displayData.append(contentsOf: displayData.map { AnyDispplayData(data: $0) }.filter({ !_displayData.contains($0) }))
        if displayData.count < pageSize - 5 || displayData.count == 0 {
            finished = true
            return
        }

        if _displayData.count < 12 {
            isLoading = true
            loadMore?()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        collectionView.dataSource = dataSource
        collectionView.delegate = self
    }

    // MARK: - Private

    private func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            [weak self] _, _ in
            return self?.makeGridLayoutSection()
        }
    }

    // MARK: - Empty / error states

    /// Message shown when a load succeeds but returns nothing. Screens with a
    /// more specific story (no followed streamers live, empty favourites) can
    /// override it.
    var emptyMessage = "这里还没有内容"
    var emptyIcon: Icon = .bangumi

    private func installStateViewIfNeeded() {
        guard stateView.superview == nil, isViewLoaded else { return }
        view.addSubview(stateView)
        stateView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func updateEmptyState() {
        guard didCompleteLoad else { return }
        if _displayData.isEmpty {
            installStateViewIfNeeded()
            stateView.configure(icon: emptyIcon, message: emptyMessage, retry: nil)
            stateView.isHidden = false
        } else {
            stateView.isHidden = true
        }
    }

    /// Replaces the modal alert the feeds used to throw on failure.
    func showError(_ message: String, retry: @escaping () -> Void) {
        didCompleteLoad = true
        installStateViewIfNeeded()
        stateView.configure(icon: .live, message: message, retry: retry)
        stateView.isHidden = false
    }

    /// Height of one HomeCardCell at a given card width: 16:9 thumb, then the
    /// two-line title and the meta row. Derived rather than hardcoded — the
    /// old 380/516 constants were tuned for the shorter legacy cell and leave
    /// a visible gap under every row now.
    private func estimatedCardHeight(cardWidth: CGFloat) -> CGFloat {
        let thumb = cardWidth * 9 / 16
        let titleBlock = 20 + ceil(DS.Font.cardTitle.lineHeight) * 2
        let metaBlock = 10 + max(32, ceil(DS.Font.meta.lineHeight))
        return thumb + titleBlock + metaBlock
    }

    /// The style actually in force, once the override and the personal-page
    /// rule have been applied. Callers laying something out beside the grid
    /// need the same answer the layout uses.
    var resolvedStyle: FeedDisplayStyle {
        if let styleOverride { return styleOverride }
        if parent?.parent is PersonalViewController { return .sideBar }
        return Settings.displayStyle
    }

    /// Left edge of the first card, measured from the collection view's own
    /// content origin — i.e. after the safe-area adjustment, which every scroll
    /// view on the page gets alike. Anything that has to align with the card
    /// column (the follows avatar rail) reads it from here rather than
    /// re-deriving the insets and drifting.
    var cardLeadingInset: CGFloat {
        resolvedStyle.sectionLeading + DS.Space.gutter / 2
    }

    private func makeGridLayoutSection() -> NSCollectionLayoutSection {
        let style = resolvedStyle

        // The section spans the collection view; the card is that width split
        // by the column count, minus the per-item side insets.
        let available = collectionView?.bounds.width ?? UIScreen.main.bounds.width
        let cardWidth = available / CGFloat(style.feedColCount) - DS.Space.gutter
        let heightDimension = NSCollectionLayoutDimension.estimated(
            estimatedCardHeight(cardWidth: max(cardWidth, 200))
        )
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(style.fractionalWidth),
            heightDimension: heightDimension
        ))
        // Applied to both edges of every item, so the effective gutter is 2x
        // this. At the old 30/35 that came to 60-70pt between cards; the HIG
        // grid gutter is 40, which is what DS.Space.gutter carries.
        let hSpacing: CGFloat = DS.Space.gutter / 2
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: hSpacing, bottom: 0, trailing: hSpacing)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: heightDimension
            ),
            repeatingSubitem: item,
            count: style.feedColCount
        )
        // One rhythm for every grid: 排行榜 is the reference and it sits at 16,
        // so a 3-up feed elsewhere in the app has the same row gap rather than
        // its own looser one.
        let vSpacing: CGFloat = 16
        let baseSpacing = style.sectionLeading
        group.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .fixed(baseSpacing), top: .fixed(vSpacing), trailing: .fixed(0), bottom: .fixed(vSpacing))
        let section = NSCollectionLayoutSection(group: group)
        if baseSpacing > 0 {
            section.contentInsets = NSDirectionalEdgeInsets(top: baseSpacing, leading: 0, bottom: 0, trailing: 0)
        }

        if showHeader {
            let headerHeight = customHeaderConfig?.estimatedHeight ?? 44
            let headerKind = customHeaderConfig?.elementKind ?? TitleSupplementaryView.reuseIdentifier
            let titleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                   heightDimension: .estimated(headerHeight))
            let titleSupplementary = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: titleSize,
                elementKind: headerKind,
                alignment: .top
            )
            section.boundarySupplementaryItems = [titleSupplementary]
        }
        return section
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AnyDispplayData> {
        let dataSource = UICollectionViewDiffableDataSource<Section, AnyDispplayData>(collectionView: collectionView, cellProvider: makeCellRegistration().cellProvider)

        let supplementaryRegistration = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: TitleSupplementaryView.reuseIdentifier) {
            [weak self] supplementaryView, string, indexPath in
            guard let self else { return }
            supplementaryView.label.text = self.headerText
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }

            // 如果有自定义 header 配置，使用自定义的
            if let customConfig = self.customHeaderConfig, kind == customConfig.elementKind {
                return customConfig.viewProvider(collectionView, kind, indexPath)
            }

            // 否则使用默认的 TitleSupplementaryView
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: supplementaryRegistration, for: indexPath
            )
        }

        return dataSource
    }

    private func makeCellRegistration() -> DisplayCellRegistration {
        DisplayCellRegistration { [weak self] cell, _, displayData in
            cell.configure(with: displayData.data)
            cell.onLongPress = {
                self?.didLongPress?(displayData.data)
            }
        }
    }
}

extension FeedCollectionViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let data = dataSource.itemIdentifier(for: indexPath) {
            didSelect?(data.data)
        }
    }

    /// The focused card is the one about to be played. Resolve its cid now, so
    /// the press does not have to wait for it — see `PlaybackPrewarm`.
    func collectionView(_ collectionView: UICollectionView,
                        didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator)
    {
        guard let indexPath = context.nextFocusedIndexPath,
              let item = dataSource.itemIdentifier(for: indexPath)?.data as? (any PlayableData)
        else { return }
        PlaybackPrewarm.shared.focused(aid: item.aid, cid: item.cid)
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        let indexPath = IndexPath(item: 0, section: 0)
        return indexPath
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard _displayData.count > 0 else { return }
        guard indexPath.row == _displayData.count - 1, !isLoading, !finished else {
            return
        }
        isLoading = true
        loadMore?()
    }

    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        collectionView.visibleCells.compactMap { $0 as? BLMotionCollectionViewCell }.forEach { cell in
            cell.updateTransform()
        }
    }
}

extension FeedDisplayStyle {
    var feedColCount: Int {
        switch self {
        case .normal: return 4
        case .large, .sideBar: return 3
        }
    }

    /// Extra lead on the whole section, on top of the per-item half-gutter.
    /// Only the pages that sit under a chip bar carry it, so their first card
    /// clears the chip row's own overshoot.
    var sectionLeading: CGFloat {
        self == .sideBar ? 24 : 0
    }
}

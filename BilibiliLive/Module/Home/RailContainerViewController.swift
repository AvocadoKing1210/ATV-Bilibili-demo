//
//  RailContainerViewController.swift
//  BilibiliLive
//
//  The global left rail, replacing the stock top UITabBarController.
//
//  tvOS's UITabBar geometry (68pt top bar) is not configurable, so a custom
//  container is the only way to get the rail pattern. Content is *pushed*
//  right when the rail expands — not overlaid, no scrim — which is what
//  YouTube TV actually does (verified frame-by-frame in docs/preview).
//

import SnapKit
import UIKit

/// A rail destination: either the new index page, or one of the screens the
/// app already ships.
enum RailSection: Hashable {
    case home
    case page(TabBarPage)

    var title: String {
        switch self {
        case .home: return "首页"
        case let .page(page): return page.title
        }
    }

    var icon: Icon {
        switch self {
        case .home: return .home
        case let .page(page): return page.railIcon
        }
    }

    func makeViewController() -> UIViewController {
        switch self {
        case .home: return HomeViewController()
        case let .page(page): return TabBarPageVCFactory.createVC(for: page)
        }
    }

    /// Search is a full-screen task, not a pane. UISearchContainerViewController
    /// lays its keyboard out at screen width and ignores safe-area insets, so
    /// mounted beside the rail its leading keys are always clipped. It gets
    /// presented instead, which also means sliding right past it must not
    /// commit it — a swipe is not a decision to open a modal.
    var isPresented: Bool {
        if case .page(.search) = self { return true }
        return false
    }

    /// Search and the profile are pinned; everything between them comes from
    /// the user's own tab configuration, so reordering tabs in Settings
    /// reorders the rail. Duplicates of the pinned entries are dropped.
    static var current: [RailSection] {
        let configured = Settings.tabBarPages
            .filter { $0 != .search && $0 != .personal }
            .map { RailSection.page($0) }
        return [.page(.search), .home] + configured + [.page(.personal)]
    }
}

final class RailContainerViewController: UIViewController {
    private let railView = UIView()
    private let contentView = UIView()
    private let rowsStack = UIStackView()
    private let rowsScroll = UIScrollView()
    /// Sliding right off a rail row has to land in the page. Without this the
    /// row is a dead end: the content column is laid out for the collapsed rail
    /// and translated clear of the open one, and the focus engine finds no
    /// candidate across that gap. Live only while the rail is open, so it can
    /// never intercept a move *inside* the content.
    private let railExitGuide = UIFocusGuide()
    /// The mirror of the exit guide: sliding left out of the page opens the rail
    /// on the row for the page you are on, from any height on the screen.
    ///
    /// The rows alone cannot do that. A leftward move is resolved geometrically,
    /// so it lands on whichever row happens to sit beside the card you left —
    /// and a card low on a long page has no row beside it at all. A full-height
    /// guide at the rail's edge is always the nearest thing to the left,
    /// whatever you were pointing at. Live only while the rail is closed, which
    /// is also the only time focus is in the content for it to catch.
    private let railEntryGuide = UIFocusGuide()
    /// Settings has no rail row of its own: it lives inside 我的 as a run of
    /// chips, so the rail would otherwise offer two doors into one screen.
    private let accountRow = RailRowButton(icon: nil, title: "哔哩用户", usesAvatar: true)

    private var sectionRows: [RailSection: RailRowButton] = [:]
    private var railWidth: Constraint?
    private var current: RailSection = .home
    private var currentVC: UIViewController?
    private var isExpanded = false
    /// Held so a focus bounce out of the rail and straight back reverses from
    /// wherever the rail actually is, instead of snapping to an end stop and
    /// replaying. Focus on tvOS moves faster than 300ms all the time.
    private var railAnimator: UIViewPropertyAnimator?
    /// Mounted pages are kept alive so switching back preserves scroll
    /// position and does not refetch. Six screens is a bounded set.
    private var mounted: [RailSection: UIViewController] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Color.bg
        setupRail()
        setupContent()
        select(Self.launchSection ?? .home, animated: false)
        updateAccount()
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateAccount),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        // Reordering tabs in Settings reorders the rail, same as it used to
        // reorder the tab bar.
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildRail),
            name: .tabBarPagesDidChange, object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-showSettings"), presentedViewController == nil {
                select(.page(.personal), animated: false)
            }
            if args.contains("-showSearch"), presentedViewController == nil {
                let searchVC = TabBarPageVCFactory.createVC(for: .search)
                searchVC.modalPresentationStyle = .fullScreen
                present(searchVC, animated: true)
            }
            if args.contains("-showAccounts"), presentedViewController == nil {
                accountTapped()
            }
        #endif
    }

    @objc private func rebuildRail() {
        rowsStack.arrangedSubviews
            .compactMap { $0 as? RailRowButton }
            .filter { $0 !== accountRow }
            .forEach { $0.removeFromSuperview() }
        sectionRows.removeAll()
        for section in RailSection.current {
            let row = RailRowButton(icon: section.icon, title: section.title)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .primaryActionTriggered)
            row.isExpanded = isExpanded
            row.setLabelVisible(isExpanded)
            row.setPillWidth(pillWidth(forRail: isExpanded ? DS.Rail.expanded : DS.Rail.collapsed))
            row.isActiveSection = (section == current)
            sectionRows[section] = row
            rowsStack.addArrangedSubview(row)
        }
        // A page that was dropped from the configuration can no longer be
        // the active one.
        if sectionRows[current] == nil {
            select(.home, animated: false)
        } else {
            // The active row is a fresh instance: the guide has to aim at it,
            // and the new rows inherit the closed rail's single-door rule.
            railEntryGuide.preferredFocusEnvironments = [sectionRows[current]].compactMap { $0 }
            updateRowFocusability()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Debug affordance: open straight onto a rail section, e.g.
    ///   xcrun simctl launch <udid> com.zeelu.BilibiliLive -railSection follows
    /// Lets a section be exercised without driving the focus engine, which
    /// is useful on hosts where the Simulator refuses synthetic input.
    private static var launchSection: RailSection? {
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-railSection"), i + 1 < args.count else { return nil }
            let raw = args[i + 1]
            if raw == "home" { return .home }
            guard let page = TabBarPage(rawValue: raw) else { return nil }
            return .page(page)
        #else
            return nil
        #endif
    }

    @objc private func updateAccount() {
        guard let profile = AccountManager.shared.activeAccount?.profile else {
            accountRow.setAccount(name: "未登录", avatar: nil)
            return
        }
        accountRow.setAccount(
            name: profile.username,
            avatar: profile.avatar.isEmpty ? nil : URL(string: profile.avatar)
        )
    }

    // MARK: - Layout

    private func setupRail() {
        railView.backgroundColor = DS.Color.bg
        railView.clipsToBounds = true
        view.addSubview(contentView)
        view.addSubview(railView)

        railView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            railWidth = make.width.equalTo(DS.Rail.collapsed).constraint
        }

        rowsStack.axis = .vertical
        rowsStack.spacing = DS.Rail.rowGap
        rowsStack.alignment = .fill

        // A fully configured rail (13 pages + account + profile) is taller
        // than 1080, so the rows scroll; the focus engine drives it.
        rowsScroll.showsVerticalScrollIndicator = false
        rowsScroll.clipsToBounds = false
        railView.addSubview(rowsScroll)
        rowsScroll.addSubview(rowsStack)

        accountRow.addTarget(self, action: #selector(accountTapped), for: .primaryActionTriggered)
        rowsStack.addArrangedSubview(accountRow)
        for section in RailSection.current {
            let row = RailRowButton(icon: section.icon, title: section.title)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .primaryActionTriggered)
            sectionRows[section] = row
            rowsStack.addArrangedSubview(row)
        }

        rowsScroll.snp.makeConstraints { make in
            // The first rail row shares its baseline with the first chip in
            // the content column, so the two columns start on one line.
            make.top.equalToSuperview().offset(DS.Space.topRow)
            make.leading.equalToSuperview().offset(DS.Rail.inset)
            make.width.equalTo(DS.Rail.expanded - DS.Rail.inset * 2)
            make.bottom.equalToSuperview().offset(-DS.Space.xl)
        }
        rowsStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }

        view.addLayoutGuide(railExitGuide)
        railExitGuide.isEnabled = false
        railExitGuide.snp.makeConstraints { make in
            make.leading.equalTo(railView.snp.trailing)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }

        view.addLayoutGuide(railEntryGuide)
        railEntryGuide.snp.makeConstraints { make in
            make.leading.equalTo(railView.snp.trailing)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        updateRowFocusability()
    }

    /// Content is laid out once, for the *collapsed* rail, and pushed with a
    /// transform rather than re-sized.
    ///
    /// Pinning its leading edge to the rail looks equivalent and is not: every
    /// page in here sizes its cards off `container.effectiveContentSize`, so a
    /// rail tied to the content's width re-solves the whole compositional
    /// layout on every frame of the animation and the cards visibly shrink
    /// from 384pt to 312pt and back while the rail moves. A translation moves
    /// the same rendered layer on the GPU — nothing reflows, nothing resizes,
    /// and the column that runs off the right edge is the one the reference
    /// pushes off too.
    private func setupContent() {
        contentView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.leading.equalToSuperview().offset(DS.Rail.collapsed)
        }
    }

    // MARK: - Section switching

    @objc private func accountTapped() {
        let switcher = AccountSwitcherViewController()
        present(switcher, animated: true)
    }

    @objc private func rowTapped(_ sender: RailRowButton) {
        guard let section = sectionRows.first(where: { $0.value === sender })?.key else { return }
        // Menu returns from the presented ones.
        if section.isPresented {
            let vc = section.makeViewController()
            vc.modalPresentationStyle = .fullScreen
            present(vc, animated: true)
            return
        }
        select(section, animated: true)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func select(_ section: RailSection, animated: Bool) {
        guard section != current || currentVC == nil else { return }
        current = section

        // Detach the outgoing page but keep it mounted, so returning to it
        // restores scroll position instead of re-requesting everything.
        currentVC?.willMove(toParent: nil)
        currentVC?.view.removeFromSuperview()
        currentVC?.removeFromParent()

        let vc: UIViewController
        if let existing = mounted[section] {
            vc = existing
        } else {
            vc = section.makeViewController()
            mounted[section] = vc
        }
        // The index page leads its own content in via section insets. Every
        // other page lays out to its safe area, so give it the same clearance
        // there — without it the search keyboard's first key sits flush under
        // the rail edge.
        if case .home = section {} else {
            vc.additionalSafeAreaInsets = UIEdgeInsets(
                top: 0, left: DS.Space.contentLead, bottom: 0, right: 0
            )
        }
        addChild(vc)
        contentView.addSubview(vc.view)
        vc.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        vc.didMove(toParent: self)
        currentVC = vc
        railExitGuide.preferredFocusEnvironments = [vc]

        for (key, row) in sectionRows {
            row.isActiveSection = (key == section)
        }
        railEntryGuide.preferredFocusEnvironments = [sectionRows[section]].compactMap { $0 }
        updateRowFocusability()
    }

    /// While the rail is closed the only row that answers focus is the active
    /// one, so a move in from the content can only ever land on the page you
    /// are already on — the guide above aims for that row, and this makes sure
    /// nothing else is standing in the way to be picked instead. The rest come
    /// alive with the labels, once there is a rail to walk.
    private func updateRowFocusability() {
        accountRow.isFocusable = isExpanded
        for (section, row) in sectionRows {
            row.isFocusable = isExpanded || section == current
        }
    }

    // MARK: - Focus

    /// Ordered preferences. Content first when the rail is at rest, then the
    /// *active* section row — never an unspecified fallback, which is how
    /// first launch used to land on the account chip before the shelves had
    /// finished loading and become focusable.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        let activeRow = sectionRows[current]
        if isExpanded {
            return [activeRow, currentVC].compactMap { $0 }
        }
        return [currentVC, activeRow].compactMap { $0 }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focusInRail = context.nextFocusedView.map { $0.isDescendant(of: railView) } ?? false
        setRailExpanded(focusInRail)
    }

    // Sliding right off a rail row used to *commit* it — the row you were
    // pointing at became the page, with no Select press. It reads as a slip
    // rather than a choice: leaving the rail is the same gesture as changing
    // where you are, so glancing at it and sliding back out costs you your
    // page. Worse, the swap ran as a vetoed move plus a deferred focus update,
    // and a page mounted a moment ago has nothing focusable to receive it —
    // focus stayed parked on a rail that had already closed, invisible, with
    // nothing to its left for the next slide to reach. Right now closes the
    // rail through `railExitGuide` and does nothing else; Select picks a page.

    /// The rail's inner width at a given rail width — what the pill has room
    /// to occupy, inset equally on both sides so its right cap mirrors the
    /// gap its left one already keeps.
    private func pillWidth(forRail width: CGFloat) -> CGFloat {
        width - DS.Rail.inset * 2
    }

    private func setRailExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        railExitGuide.isEnabled = expanded
        railEntryGuide.isEnabled = !expanded
        updateRowFocusability()

        let rows = rowsStack.arrangedSubviews.compactMap { $0 as? RailRowButton }
        let width = expanded ? DS.Rail.expanded : DS.Rail.collapsed

        // Halt where it is rather than let the old animation finish underneath
        // the new one: `stopAnimation(true)` leaves every property at its
        // current presentation value, which is exactly the state the reversal
        // has to start from. Only an *active* animator may be stopped — the
        // call raises on one that has already run out.
        if let running = railAnimator, running.state == .active {
            running.stopAnimation(true)
        }
        railAnimator = nil

        // Two clocks, and the split is the whole point. The fill answers the
        // remote — it has to be *there*, at its short length, before anything
        // moves, or there is nothing on screen to watch extend. The travel is
        // the slow half. Riding one clock for both gives a pill that only
        // finishes fading in once the rail is already open, which is what the
        // 300ms was supposed to fix.
        UIView.animate(withDuration: DS.Focus.duration, delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut])
        {
            rows.forEach { $0.isExpanded = expanded }
        }

        let curve = expanded ? DS.Motion.railOpenCurve : DS.Motion.railCloseCurve
        let animator = UIViewPropertyAnimator(
            duration: DS.Motion.rail, timingParameters: curve.timingParameters
        )
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.railWidth?.update(offset: width)
            rows.forEach { $0.setPillWidth(self.pillWidth(forRail: width)) }
            self.contentView.transform = expanded
                ? CGAffineTransform(translationX: DS.Rail.expanded - DS.Rail.collapsed, y: 0)
                : .identity
            self.view.layoutIfNeeded()
        }
        // Labels are the one thing that is not symmetric: they arrive late,
        // into room the rail has already made, and they leave early, before
        // the closing edge can cut through a word.
        if expanded {
            animator.addAnimations(
                { rows.forEach { $0.setLabelVisible(true) } },
                delayFactor: DS.Motion.railLabelDelay
            )
        } else {
            UIView.animate(withDuration: DS.Motion.railLabelOut, delay: 0,
                           options: [.beginFromCurrentState, .curveEaseIn])
            {
                rows.forEach { $0.setLabelVisible(false) }
            }
        }
        animator.startAnimation()
        railAnimator = animator
    }

    // MARK: - Menu button returns focus to the rail, mirroring the system

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.first?.type == .menu, !isExpanded {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

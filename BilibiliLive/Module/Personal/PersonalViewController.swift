//
//  PersonalViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/8/20.
//
//  设置 — the personal content pages and every settings group, on one screen.
//
//  This used to be 我的: a 500pt sidebar whose 设置 row opened a controller
//  carrying a 500pt sidebar of its own — two navigation columns nested inside a
//  third (the global rail), with the content squeezed into whatever was left.
//  It is one chip row now, the same grammar the index page and the category
//  pages already use, and both sidebars are gone.
//
//  The account is not here. The rail's avatar row already opens the switcher,
//  and 登出 moved into the 通用 group rather than keeping a whole pane alive
//  for two buttons.
//

import SnapKit
import UIKit

class PersonalViewController: UIViewController, BLTabBarContentVCProtocol {
    /// A chip and the pane behind it.
    private enum Pane: Hashable {
        case page(TabBarPage)
        case settings(SettingsSection)

        var title: String {
            switch self {
            case let .page(page): return page.title
            case let .settings(section): return section.title
            }
        }

        /// Pages that take over the screen instead of mounting in the pane:
        /// search needs the full width for its keyboard, and the others carry
        /// navigation of their own that would nest inside our chip row.
        var isModal: Bool {
            if case let .page(page) = self { return page.requirePresentInPersonalPage }
            return false
        }

        func makeViewController() -> UIViewController {
            switch self {
            case let .page(page): return TabBarPageVCFactory.createVC(for: page)
            case let .settings(section): return SettingsViewController(section: section)
            }
        }
    }

    static func create() -> PersonalViewController {
        return PersonalViewController()
    }

    private let chipBar = ChipBarView()
    private let contentView = UIView()

    private var panes: [Pane] = []
    /// Mounted panes are kept alive, so coming back to one restores its scroll
    /// position rather than refetching it.
    private var mounted: [Pane: UIViewController] = [:]
    private weak var currentViewController: UIViewController?
    private var current: Pane?
    private var activeIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Color.bg
        setupUI()
        rebuildPanes()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTabBarPagesDidChange),
                                               name: .tabBarPagesDidChange,
                                               object: nil)
        AccountManager.shared.refreshActiveAccountProfile()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Land on the chip whose pane is actually showing. Left to the focus
    /// engine it picks the first chip in the row, which can be a modal one —
    /// the ring ends up on a different chip than the fill.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [chipBar.buttons[safe: activeIndex], currentViewController?.view].compactMap { $0 }
    }

    // MARK: - Layout

    private func setupUI() {
        view.addSubview(contentView)
        view.addSubview(chipBar)

        chipBar.snp.makeConstraints { make in
            // Shares the rail's first-row baseline, same as the index page.
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(DS.Chip.barHeight)
        }
        contentView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(chipBar.snp.bottom)
        }

        chipBar.onSelect = { [weak self] index in
            self?.select(index, presentIfModal: true)
        }
        chipBar.onFocusChange = { [weak self] index in
            guard let self, Settings.sideMenuAutoSelectChange else { return }
            // A chip that takes over the screen must never fire from focus
            // merely passing across it.
            guard panes[safe: index]?.isModal == false else { return }
            chipBar.setActive(index)
            select(index, presentIfModal: false)
        }
    }

    // MARK: - Panes

    /// Whatever the user filed under this page first, then the settings
    /// groups — content before configuration.
    private func rebuildPanes() {
        panes = Settings.personalPages.map { Pane.page($0) }
            + SettingsSection.allCases.map { Pane.settings($0) }
        chipBar.setTitles(panes.map(\.title))
        // A page moved out to the rail no longer has a pane to come back to.
        mounted = mounted.filter { panes.contains($0.key) }
        // Open on the first chip that actually has a pane. The modal ones show
        // nothing until they are chosen, and landing on one leaves the screen
        // blank under a selected chip.
        let first = panes.firstIndex { !$0.isModal } ?? 0
        chipBar.setActive(first)
        select(first, presentIfModal: false)
    }

    private func select(_ index: Int, presentIfModal: Bool) {
        guard let pane = panes[safe: index] else { return }

        if pane.isModal {
            guard presentIfModal else { return }
            let vc = pane.makeViewController()
            vc.modalPresentationStyle = .fullScreen
            present(vc, animated: true)
            return
        }

        guard pane != current || currentViewController == nil else { return }
        current = pane
        activeIndex = index

        let vc = mounted[pane] ?? pane.makeViewController()
        mounted[pane] = vc
        setViewController(vc: vc)
    }

    func setViewController(vc: UIViewController) {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()

        currentViewController = vc
        addChild(vc)
        contentView.addSubview(vc.view)
        vc.view.makeConstraintsToBindToSuperview()
        vc.didMove(toParent: self)
    }

    func reloadData() {
        (currentViewController as? BLTabBarContentVCProtocol)?.reloadData()
    }

    @objc private func handleTabBarPagesDidChange() {
        // The chip row is rebuilt from scratch, so nothing survives as the
        // selection — force the first pane to re-mount.
        current = nil
        rebuildPanes()
    }
}

class EmptyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "Nothing Here"
        view.addSubview(label)
        label.makeConstraintsBindToCenterOfSuperview()
    }
}

//
//  PersonalViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/8/20.
//
//  设置 — a thin UIKit shell around the SwiftUI settings screen.
//
//  The screen itself is `SettingsScreen` (SettingsView.swift), rendered with
//  the `Theme` tokens ported from Discord's web client rather than the app's
//  own design system. This controller only exists because the rail mounts
//  UIViewControllers, and because two destinations are still UIKit modals the
//  SwiftUI side cannot present: the account switcher and the tab-bar
//  customization screen.
//
//  The content pages that used to live here as chips (追番追剧, 历史记录…)
//  are gone for good — the index page's shelves and the rail carry them, and
//  this screen is only settings now.
//

import SwiftUI
import UIKit

class PersonalViewController: UIViewController, BLTabBarContentVCProtocol {
    static func create() -> PersonalViewController {
        return PersonalViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The SwiftUI screen paints its own grounds; this only backstops the
        // frame during presentation transitions. It tracks the nav column's
        // own ground (`Theme.Colors.baseLowest`) in both appearances — a fixed
        // dark value here flashed a black frame into a Light-appearance push.
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .light ? UIColor(rgb: 0xE9_E8_E6) : UIColor(rgb: 0x12_12_14)
        }

        let bridge = SettingsBridge(
            presentAccountSwitcher: { [weak self] in
                self?.present(AccountSwitcherViewController(), animated: true)
            },
            presentTabCustomization: { [weak self] in
                self?.present(TabBarCustomizationViewController(), animated: true)
            },
            presentModal: { [weak self] request in
                self?.presentModal(request)
            }
        )

        let hosting = UIHostingController(rootView: SettingsScreen(bridge: bridge))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.makeConstraintsToBindToSuperview()
        hosting.didMove(toParent: self)

        AccountManager.shared.refreshActiveAccountProfile()
    }

    func reloadData() {}
}

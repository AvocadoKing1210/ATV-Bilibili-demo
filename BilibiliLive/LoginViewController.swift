//
//  LoginViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//
//  First launch, and wherever a session dies. Same brand mark, same backdrop
//  and same QR panel as the account switcher's "add account" step, so signing
//  in for the first time and adding a second account are one screen the user
//  learns once.
//
//  The old layout split the screen down the middle — QR on the left, a title
//  and two numbered hints on the right — and the right half was empty on
//  screen, because both of those labels were left on `.label`, which is black
//  in the Light appearance tvOS was running. One centred column has no half to
//  lose.
//

import Foundation
import SnapKit
import UIKit

class LoginViewController: UIViewController {
    private let backdrop = BrandBackdropView()
    private let markView = BiliMarkView(markHeight: 52)
    private let panel = QRLoginPanelView(title: "账号登录",
                                         subtitle: "用手机上的哔哩哔哩客户端扫描二维码登录\n登录失败时可以重新生成二维码再试一次")
    private let session = QRLoginSession()

    static func create() -> LoginViewController {
        LoginViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        session.onCode = { [weak self] url in
            self?.panel.setCode(url)
        }
        session.onExpire = { [weak self] in
            self?.panel.setHint("二维码已过期，正在刷新…")
        }
        session.onSuccess = { [weak self] _ in
            self?.didValidationSuccess()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stop()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [panel]
    }

    private func didValidationSuccess() {
        session.stop()
        // Let the panel leave before the root is swapped, so the hand-off is
        // one continuous fade instead of a cut into a cut.
        UIView.animate(withDuration: 0.28, animations: {
            self.panel.alpha = 0
            self.panel.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            AppDelegate.shared.showTabBar()
        })
    }

    private func setupUI() {
        view.backgroundColor = .clear

        view.addSubview(backdrop)
        view.addSubview(markView)
        view.addSubview(panel)

        backdrop.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        markView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(16)
        }

        panel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(28)
        }
    }
}

//
//  AppDelegate.swift
//  BilibiliLive
//
//  Created by Etan on 2021/3/27.
//

import AVFoundation
import CocoaLumberjackSwift
import Kingfisher
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.setup()
        ImageCache.default.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        AVInfoPanelCollectionViewThumbnailCellHook.start()
        AccountManager.shared.bootstrap()
        BiliBiliUpnpDMR.shared.start()
        URLSession.shared.configuration.headers.add(.userAgent("BiLiBiLi AppleTV Client/1.0.0 (github/yichengchen/ATV-Bilibili-live-demo)"))
        window = UIWindow()
        if ApiRequest.isLogin() {
            if let expireDate = ApiRequest.getToken()?.expireDate {
                let now = Date()
                if expireDate.timeIntervalSince(now) < 60 * 60 * 30 {
                    ApiRequest.refreshToken()
                }
            } else {
                ApiRequest.refreshToken()
            }
            // A launch is the second chance for an account whose name and
            // avatar never arrived at sign-in: without this, one failed fetch
            // left "UID 12345" on the rail for the life of the install.
            AccountManager.shared.refreshActiveAccountProfile()
            window?.rootViewController = AppDelegate.makeMainRoot()
        } else {
            window?.rootViewController = LoginViewController.create()
        }
        WebRequest.ensureFingerprint {
            WebRequest.requestIndex()
        }
        window?.makeKeyAndVisible()

        #if DEBUG
            if TheaterPreviewLauncher.isEnabled, let root = window?.rootViewController {
                TheaterPreviewLauncher.present(from: root)
            }
        #endif

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    func showLogin() {
        replaceRootViewController(with: LoginViewController.create(), animated: true)
    }

    /// Root for a logged-in session. The left rail replaces the stock tvOS
    /// tab bar, whose 68pt top-bar geometry is not configurable. Revert the
    /// whole navigation rework by returning `BLTabBarViewController()` here.
    static func makeMainRoot() -> UIViewController {
        RailContainerViewController()
    }

    func showTabBar() {
        replaceRootViewController(with: AppDelegate.makeMainRoot(), animated: true)
    }

    func resetTabBar() {
        replaceRootViewController(with: AppDelegate.makeMainRoot(), animated: true)
    }

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    private func replaceRootViewController(with viewController: UIViewController, animated: Bool) {
        guard let window else { return }
        if animated, let snapshot = window.snapshotView(afterScreenUpdates: false) {
            window.rootViewController = viewController
            window.makeKeyAndVisible()
            viewController.view.addSubview(snapshot)
            UIView.animate(withDuration: 0.25, animations: {
                snapshot.alpha = 0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        } else {
            window.rootViewController = viewController
            window.makeKeyAndVisible()
        }
    }
}

//
//  CommonPlayerViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVKit
import UIKit

class CommonPlayerViewController: UIViewController {
    private let playerVC = AVPlayerViewController()
    private var activePlugins = [CommonPlayerPlugin]()
    private var observations = Set<NSKeyValueObservation>()
    private var rateObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var playToEndObserver: Any?
    private var playbackStalledObserver: Any?
    private var isEnd = false
    private var isRestoringFromPip = false
    /// 新 AVPlayerItem ready 后是否自动 play。换 CDN host 等场景可临时关掉，由调用方按用户暂停状态决定是否续播。
    var autoPlayWhenReady = true
    var allowsPictureInPicturePlayback = true

    /// 当前 AVPlayer，供容器（如 VideoTheaterViewController）观察播放进度。
    var currentPlayer: AVPlayer? { playerVC.player }

    /// 缩放到角落时由容器自己绘制迷你进度条，隐藏系统 transport。
    var showsPlaybackControls: Bool {
        get { playerVC.showsPlaybackControls }
        set { playerVC.showsPlaybackControls = newValue }
    }

    /// PiP 结束后需要重新 present 播放器。当播放器被嵌入容器（作为 child VC）时，
    /// 它自己不是被 present 的那个，必须由容器代为恢复，否则 UIKit 会报错。
    weak var pipRestoreTarget: UIViewController?

    /// player 实例在切换 CDN 线路/清晰度时会被替换，容器据此重新挂观察者。
    var onPlayerChanged: ((AVPlayer) -> Void)?

    /// 各插件通过 addMenuItems(current:) 贡献的菜单。自绘播放控件时系统 transport bar
    /// 不再显示，容器需要拿到这份数据自行渲染，否则弹幕/倍速/画质/线路全部无法访问。
    private(set) var currentMenuItems = [UIMenuElement]()
    var onMenuItemsChanged: (([UIMenuElement]) -> Void)?

    deinit {
        cleanUpPlayerOnExit(force: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)
        playerVC.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        playerVC.allowsPictureInPicturePlayback = allowsPictureInPicturePlayback
        playerVC.delegate = self

        let playerObservation = playerVC.observe(\.player, options: [.old, .new]) { [weak self] vc, obs in
            Logger.debug("player changed: \(String(describing: obs.oldValue)) -> \(String(describing: obs.newValue))")
            if let oldPlayer = obs.oldValue, let oldPlayer {
                self?.activePlugins.forEach { $0.playerDidCleanUp(player: oldPlayer) }
            }
            self?.playerDidChange(player: vc.player)
        }
        observations.insert(playerObservation)
        activePlugins.forEach { $0.playerDidLoad(playerVC: playerVC) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        activePlugins.forEach { $0.playerDidDismiss(playerVC: playerVC) }
        cleanUpPlayerOnExit()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [playerVC.view]
    }

    /// Plugins are built by the view model, so a container that embeds this
    /// player has no other handle on them — the theater needs one to keep the
    /// danmaku layer in step with the picture when it docks.
    func plugin<T: CommonPlayerPlugin>(ofType _: T.Type) -> T? {
        activePlugins.compactMap { $0 as? T }.first
    }

    func addPlugin(plugin: CommonPlayerPlugin) {
        if activePlugins.contains(where: { $0 == plugin }) {
            return
        }
        plugin.addViewToPlayerOverlay(container: playerVC.contentOverlayView!)
        activePlugins.append(plugin)
        plugin.playerDidLoad(playerVC: playerVC)
        if playerVC.transportBarCustomMenuItems.isEmpty == false {
            updateMenus()
        }
    }

    func removePlugin(plugin: CommonPlayerPlugin) {
        let removingPlugins = activePlugins.filter { $0 == plugin }
        removingPlugins.forEach { $0.playerWillCleanUp(playerVC: playerVC) }
        if let player = playerVC.player {
            removingPlugins.forEach { $0.playerDidCleanUp(player: player) }
        }
        activePlugins.removeAll { $0 == plugin }
    }

    func removeAllPlugins() {
        guard !activePlugins.isEmpty else { return }
        activePlugins.forEach { $0.playerWillCleanUp(playerVC: playerVC) }
        if let player = playerVC.player {
            Logger.debug("removeAllPlugins: clean up player: \(player)")
            activePlugins.forEach { $0.playerDidCleanUp(player: player) }
        }
        activePlugins.removeAll()
    }

    /// Stop and release playback now, unless it has been handed to PiP.
    ///
    /// For containers that embed this controller as a child: a child never sees
    /// its own dismissal, and once the container has removed it from its view
    /// hierarchy it may not get a `viewDidDisappear` at all — so the container
    /// has to be the one to say playback is over. Leaving it to `deinit` means
    /// an AVPlayer, its decoder and its buffers linger for as long as anything
    /// still references the controller.
    func tearDownPlayback() {
        let isPictureInPictureRunning = PipRecorder.shared.playingPipViewController.contains { $0.playerVC == playerVC }
        guard !isPictureInPictureRunning else { return }
        cleanUpPlayerOnExit(force: true)
    }

    func playerWillStart(player: AVPlayer) {}
    func playerDidStart(player: AVPlayer) {}
    func playerDidEnd(player: AVPlayer) {}
    func playerDidStall(player: AVPlayer) {}
    func playerDidFail(player: AVPlayer) {}

    func showErrorAlertAndExit(title: String = "播放失败", message: String = "未知错误") {
        presentModalNotice(title: title, message: message) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
    }

    func updateMenus() {
        var menus = [UIMenuElement]()
        for activePlugin in activePlugins {
            let newMenus = activePlugin.addMenuItems(current: &menus)
            menus.append(contentsOf: newMenus)
        }
        playerVC.transportBarCustomMenuItems = menus
        currentMenuItems = menus
        onMenuItemsChanged?(menus)
    }

    func stopPlayback() {
        cleanUpPlayerOnExit(force: true)
    }

    func currentPlaybackTimeInSeconds() -> Int? {
        guard let seconds = playerVC.player?.currentTime().seconds,
              seconds.isFinite,
              seconds > 0
        else {
            return nil
        }
        return Int(seconds.rounded(.down))
    }

    private func cleanUpPlayerOnExit(force: Bool = false) {
        let isPictureInPictureRunning = PipRecorder.shared.playingPipViewController.contains { $0.playerVC == playerVC }
        // `parent?.isBeingDismissed` covers the embedded case. Inside the
        // theater this controller is a child, so it is never itself "being
        // dismissed" — the container is. Without this the whole rig (AVPlayer,
        // decoder, buffers, the plugins' timers and observers) survived the
        // screen and was only reclaimed if and when deinit happened to run.
        let leaving = isBeingDismissed
            || isMovingFromParent
            || parent?.isBeingDismissed == true
            || navigationController?.isBeingDismissed == true
        let shouldCleanUp = force || (leaving && !isPictureInPictureRunning)
        guard shouldCleanUp else { return }

        cleanUpObserver()

        let player = playerVC.player
        player?.pause()
        // Plugins may still be preparing the first AVPlayer. Always run their
        // cleanup hook even when playerVC.player has not been installed yet.
        removeAllPlugins()
        player?.replaceCurrentItem(with: nil)
        playerVC.player = nil
    }

    private func cleanUpObserver() {
        rateObserver = nil
        statusObserver = nil
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }
        playToEndObserver = nil
        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
        }
        playbackStalledObserver = nil
    }
}

extension CommonPlayerViewController {
    private func playerDidChange(player: AVPlayer?) {
        if let player {
            activePlugins.forEach { $0.playerDidChange(player: player) }
            onPlayerChanged?(player)
            rateObserver = player.observe(\.rate, options: [.old, .new]) {
                [weak self] _player, obs in
                DispatchQueue.main.async { [weak self] in
                    self?.playerRateDidChange(player: player)
                }
            }
            if let playItem = player.currentItem {
                observePlayerItem(playItem)
            }
            updateMenus()
        } else {
            cleanUpObserver()
        }
    }

    private func playerRateDidChange(player: AVPlayer) {
        if player.rate > 0 {
            activePlugins.forEach { $0.playerDidStart(player: player) }
            playerDidStart(player: player)
        } else if player.rate == 0 {
            if !isEnd {
                activePlugins.forEach { $0.playerDidPause(player: player) }
            }
        }
    }

    private func observePlayerItem(_ playerItem: AVPlayerItem) {
        statusObserver = playerItem.observe(\.status, options: [.new, .old]) {
            [weak self] item, _ in
            guard let self, let player = playerVC.player else { return }
            switch item.status {
            case .readyToPlay:
                isEnd = false
                activePlugins.forEach { $0.playerWillStart(player: player) }
                playerWillStart(player: player)
                if autoPlayWhenReady {
                    player.play()
                }
            case .failed:
                activePlugins.forEach { $0.playerDidFail(player: player) }
                playerDidFail(player: player)
            default:
                break
            }
        }
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }
        playToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] note in
            guard let self, let player = playerVC.player else { return }
            isEnd = true
            activePlugins.forEach { $0.playerDidEnd(player: player) }
            playerDidEnd(player: player)
        }
        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
        }
        playbackStalledObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: playerItem, queue: .main) { [weak self] _ in
            guard let self, let player = playerVC.player else { return }
            activePlugins.forEach { $0.playerDidStall(player: player) }
            playerDidStall(player: player)
        }
    }
}

extension CommonPlayerViewController: AVPlayerViewControllerDelegate {
    @objc func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
        if let presentedViewController = UIViewController.topMostViewController() as? CommonPlayerViewController,
           presentedViewController.playerVC == playerViewController
        {
            dismiss(animated: true)
            return false
        }
        return false
    }

    @objc func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_: AVPlayerViewController) -> Bool {
        return true
    }

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isRestoringFromPip = false
        PipRecorder.shared.playingPipViewController.append(self)
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        PipRecorder.shared.playingPipViewController.removeAll { $0.playerVC == playerViewController }
        if !isRestoringFromPip {
            // 用户点 ✕ 关闭 PiP，清理资源
            cleanUpPlayerOnExit(force: true)
        }
        isRestoringFromPip = false
    }

    @objc func playerViewController(_ playerViewController: AVPlayerViewController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void)
    {
        isRestoringFromPip = true
        let presentedViewController = UIViewController.topMostViewController()
        guard let containerPlayer = PipRecorder.shared.playingPipViewController.first(where: { $0.playerVC == playerViewController }) else {
            completionHandler(false)
            return
        }
        // 嵌入容器时播放器本身是 child VC，不能被 present，改为恢复容器。
        let restoreTarget = containerPlayer.pipRestoreTarget ?? containerPlayer
        if presentedViewController is CommonPlayerViewController {
            let parent = presentedViewController.presentingViewController
            presentedViewController.dismiss(animated: false) {
                parent?.present(restoreTarget, animated: false)
                completionHandler(true)
            }
        } else {
            presentedViewController.present(restoreTarget, animated: false) {
                completionHandler(true)
            }
        }
    }

    class PipRecorder {
        static let shared = PipRecorder()
        var playingPipViewController = [CommonPlayerViewController]()
    }
}

//
//  DanmuViewPlugin.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVKit
import Combine
import UIKit

protocol DanmuProviderProtocol {
    var observerPlayerTime: Bool { get }
    var onSendTextModel: PassthroughSubject<DanmakuTextCellModel, Never> { get }
    func playerTimeChange(time: TimeInterval)
}

class DanmuViewPlugin: NSObject {
    let danMuView = DanmakuView()

    init(provider: DanmuProviderProtocol) {
        danmuProvider = provider
        super.init()
        provider.onSendTextModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.shoot($0)
            }.store(in: &cancellable)

        Defaults.shared.$showDanmu
            .receive(on: DispatchQueue.main)
            .sink {
                [weak self] in
                self?.danMuView.isHidden = !$0
            }.store(in: &cancellable)
    }

    private let danmuProvider: DanmuProviderProtocol
    /// The two layouts the danmaku layer can be in — filling its container, or
    /// held at full-bleed size and scaled into a docked one. See
    /// `setPresentationScale`.
    fileprivate var fillConstraints: [NSLayoutConstraint] = []
    fileprivate var scaledConstraints: [NSLayoutConstraint] = []
    private var timeObserver: Any?
    private weak var currentPlayer: AVPlayer? // 保存当前 player 的弱引用
    private var cancellable = Set<AnyCancellable>()

    private func shoot(_ model: DanmakuCellModel) {
        // 当显示区域小于1时,将底部弹幕转为浮动弹幕
        if danMuView.displayArea < 1, model.type == .bottom {
            if let shootModel = model as? DanmakuTextCellModel {
                shootModel.type = .floating
                danMuView.shoot(danmaku: shootModel)
                return
            }
        }

        danMuView.shoot(danmaku: model)
    }
}

extension DanmuViewPlugin: CommonPlayerPlugin {
    func playerDidChange(player: AVPlayer) {
        // 清理旧的 observer（必须用旧的 player 来移除）
        if let timeObserver, let currentPlayer {
            currentPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // 保存新的 player 引用
        currentPlayer = player

        // 清空当前显示的弹幕，准备重新同步
        danMuView.clean()
    }

    func playerWillStart(player: AVPlayer) {
        guard danmuProvider.observerPlayerTime else {
            return
        }

        // 清理旧的 observer（如果有）
        if let timeObserver, let currentPlayer {
            currentPlayer.removeTimeObserver(timeObserver)
        }

        // 保存新的 player 引用
        currentPlayer = player

        // 主队列：provider 的分段缓存现在是边播边灌的（起播不再等弹幕下载完），
        // 读在这个回调里、写在下载完成时，两边都放主线程才不会撕裂。回调本身
        // 1 秒一次且只做游标推进，主线程开销可以忽略。
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1),
                                                      queue: .main)
        { [weak self] time in
            guard let self else { return }
            if !Defaults.shared.showDanmu { return }
            let seconds = time.seconds
            danmuProvider.playerTimeChange(time: seconds)
        }
    }

    func playerDidCleanUp(player: AVPlayer) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        currentPlayer = nil
    }

    func addViewToPlayerOverlay(container: UIView) {
        container.addSubview(danMuView)
        danMuView.translatesAutoresizingMaskIntoConstraints = false
        fillConstraints = [
            danMuView.leftAnchor.constraint(equalTo: container.leftAnchor),
            danMuView.rightAnchor.constraint(equalTo: container.rightAnchor),
            danMuView.topAnchor.constraint(equalTo: container.topAnchor),
            danMuView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        // Full-bleed geometry, held whatever the picture is doing — see
        // setPresentationScale.
        let screen = UIScreen.main.bounds.size
        scaledConstraints = [
            danMuView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            danMuView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            danMuView.widthAnchor.constraint(equalToConstant: screen.width),
            danMuView.heightAnchor.constraint(equalToConstant: screen.height),
        ]
        NSLayoutConstraint.activate(fillConstraints)
        danMuView.setNeedsLayout()
        danMuView.layoutIfNeeded()
        danMuView.paddingTop = 5
        danMuView.trackHeight = 50
        danMuView.displayArea = Settings.danmuArea.percent
        danMuView.recaculateTracks()
    }

    /// Scales the whole danmaku layer so it tracks the picture when the player
    /// docks into the corner.
    ///
    /// The layer keeps its full-bleed geometry and is *scaled* into place rather
    /// than re-laid out at the smaller size. Two reasons: danmaku already in
    /// flight carry the size and track they were measured at, so re-measuring
    /// would move only the new ones and the two sets would visibly disagree;
    /// and the text is authored for a full screen, so shrinking the box while
    /// keeping 36pt type is what made the docked picture unreadable.
    ///
    /// Safe to call repeatedly — plugins are rebuilt when the media loads, so
    /// the container re-applies the current scale each time.
    func setPresentationScale(_ scale: CGFloat) {
        guard danMuView.superview != nil, !fillConstraints.isEmpty else { return }
        if scale == 1 {
            NSLayoutConstraint.deactivate(scaledConstraints)
            NSLayoutConstraint.activate(fillConstraints)
            danMuView.transform = .identity
        } else {
            NSLayoutConstraint.deactivate(fillConstraints)
            NSLayoutConstraint.activate(scaledConstraints)
            danMuView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        danMuView.superview?.layoutIfNeeded()
    }

    func playerDidStart(player: AVPlayer) {
        danMuView.play()
    }

    func playerDidPause(player: AVPlayer) {
        danMuView.pause()
    }

    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        let danmuImage = UIImage(systemName: "list.bullet.rectangle.fill")
        let danmuImageDisable = UIImage(systemName: "list.bullet.rectangle")
        let danmuAction = UIAction(title: "Show Danmu", image: danMuView.isHidden ? danmuImageDisable : danmuImage) {
            action in
            Defaults.shared.showDanmu.toggle()
            action.image = Defaults.shared.showDanmu ? danmuImage : danmuImageDisable
        }
        let danmuDurationMenu = UIMenu(title: "弹幕展示时长", options: [.displayInline, .singleSelection], children: [4, 6, 8].map { dur in
            UIAction(title: "\(dur) 秒", state: dur == Settings.danmuDuration ? .on : .off) { _ in Settings.danmuDuration = dur }
        })
        let danmuAILevelMenu = UIMenu(title: "弹幕屏蔽等级", options: [.displayInline, .singleSelection], children: [Int32](1...10).map { level in
            UIAction(title: "\(level)", state: level == Settings.danmuAILevel ? .on : .off) { _ in Settings.danmuAILevel = level }
        })
        let danmuSettingMenu = UIMenu(title: "弹幕设置", image: UIImage(systemName: "keyboard.badge.ellipsis"), children: [danmuDurationMenu, danmuAILevelMenu])

        return [danmuAction, danmuSettingMenu]
    }
}

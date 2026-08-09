//
//  VideoPlayerViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVKit
import Combine
import UIKit

struct PlayInfo {
    /// Not `let`: a 番剧 entered by season or episode id only knows which video
    /// it is once the season lookup comes back.
    var aid: Int
    var cid: Int? = 0
    var epid: Int? = 0 // 港澳台解锁需要
    var seasonId: Int? = 0 // 番剧 season_id
    var ctime: Int? = 0
    var subType: Int? = nil // 0: 普通视频 1：番剧 2：电影 3：纪录片 4：国创 5：电视剧 7：综艺
    var lastPlayCid: Int?
    var playTimeInSecond: Int?
    var title: String?

    var isCidVaild: Bool {
        return cid ?? 0 > 0
    }

    var isBangumi: Bool {
        return epid ?? 0 > 0 || seasonId ?? 0 > 0
    }
}

class VideoNextProvider {
    init(seq: [PlayInfo]) {
        playSeq = seq
    }

    private var index = 0
    private var playSeq: [PlayInfo]
    var count: Int {
        return playSeq.count
    }

    /// The sequence is not always known when the player is built. With the
    /// detail screen gone, 选集 / 合集 arrive with the video detail — behind the
    /// picture, after playback has already started. Seeding late keeps 下一集
    /// working without the player having to wait for the list.
    ///
    /// Only ever fills an empty provider: once playback has started walking the
    /// sequence, replacing it would lose the position.
    func seed(_ seq: [PlayInfo]) {
        guard playSeq.isEmpty else { return }
        playSeq = seq
        index = 0
    }

    func reset() {
        index = 0
    }

    func getNext() -> PlayInfo? {
        index += 1
        if index < playSeq.count {
            return playSeq[index]
        }
        return nil
    }

    func peekNext() -> PlayInfo? {
        let nextIndex = index + 1
        if nextIndex < playSeq.count {
            return playSeq[nextIndex]
        }
        return nil
    }
}

class VideoPlayerViewController: CommonPlayerViewController {
    var data: VideoDetail?
    var nextProvider: VideoNextProvider?

    /// 由容器注入的插件（见 VideoTheaterViewController）。viewModel 插件就绪时会
    /// removeAllPlugins()，把容器的插件一起清掉，所以这些必须在之后重新挂上。
    var containerPlugins = [CommonPlayerPlugin]() {
        didSet { containerPlugins.forEach { addPlugin(plugin: $0) } }
    }

    /// 加载失败时由容器接管报错。
    ///
    /// 嵌进容器后播放器是 child VC，自己 present 弹窗有两个问题：容器还在做 present
    /// 动画时 UIKit 会把这次 present 直接丢掉（用户什么提示都拿不到，只剩一块不动的
    /// 黑屏）；就算弹出来了，OK 之后 dismiss 的也只是弹窗，容器还留在原地。
    /// 容器设了这个之后由它弹、由它退。
    var onLoadFailed: ((String) -> Void)?

    init(playInfo: PlayInfo) {
        viewModel = VideoPlayerViewModel(playInfo: playInfo)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let viewModel: VideoPlayerViewModel
    private var cancelable = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.nextProvider = nextProvider
        viewModel.onPluginReady.receive(on: DispatchQueue.main).sink { [weak self] completion in
            switch completion {
            case let .failure(err):
                guard let self else { return }
                if let onLoadFailed {
                    onLoadFailed(err)
                } else {
                    showErrorAlertAndExit(message: err)
                }
            default:
                break
            }
        } receiveValue: { [weak self] plugins in
            self?.removeAllPlugins()
            plugins.forEach { self?.addPlugin(plugin: $0) }
            // 容器插件刚被 removeAllPlugins() 一并清掉了，重新挂上，
            // 否则容器贡献的 transport bar 菜单会在加载完成后消失。
            self?.containerPlugins.forEach { self?.addPlugin(plugin: $0) }
            self?.updateMenus()
        }.store(in: &cancelable)

        viewModel.onExit = { [weak self] in
            self?.dismiss(animated: true)
        }
        Task {
            await viewModel.load()
        }
    }
}

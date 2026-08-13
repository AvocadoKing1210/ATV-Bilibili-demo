//
//  VideoTheaterViewController.swift
//  BilibiliLive
//
//  Hosts a `VideoPlayerViewController` and lets it dock: the picture shrinks
//  into the top-left, keeps playing, and a detail panel (简介 / 评论 / 选集 /
//  设置) takes the right-hand column.
//
//  THE INVARIANT
//  -------------
//  The player is a child view controller, created once. Docking only animates
//  the frame of the view it already lives in — the AVPlayer, its item, and
//  every plugin (danmaku, quality, sponsor-skip…) are untouched. Nothing is
//  re-created, re-parented or re-sourced, which is what keeps playback running
//  across the transition. Do not "simplify" this into swapping AVPlayerLayers.
//
//  Because the full-bleed rect and the docked rect are both exactly 16:9, one
//  uniform change of frame maps one onto the other with no letterboxing.
//
//  Geometry and timings live in `Theater.Metrics` / `Theater.Motion`, measured
//  from the reference recording; docs/preview/player-transition.html is the
//  browser rig for re-tuning them.
//

import AVKit
import Combine
import SnapKit
import UIKit

enum TheaterPane: Int, CaseIterable {
    case info, comments, pages, settings

    var title: String {
        switch self {
        case .info: return "简介"
        case .comments: return "评论"
        case .pages: return "选集"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .comments: return "bubble.left.and.bubble.right"
        case .pages: return "list.bullet"
        case .settings: return "gearshape"
        }
    }
}

final class VideoTheaterViewController: UIViewController {
    enum Mode { case fullscreen, docked }

    // MARK: Input

    /// Populated by the presenting screen; panes read from these.
    var detail: VideoDetail? {
        didSet {
            playerVC.data = detail
            infoPane.detail = detail
            miniBar.titleText = detail?.title
            miniBar.ownerText = detail?.ownerName
            miniBar.coverURL = detail?.pic
            fullChrome.configure(title: detail?.title, owner: detail?.ownerName)
            // 相关推荐 shows up twice on purpose: as a rail in the full-bleed
            // transport, under the action row, and as a list under the
            // description in 简介. Not under the docked picture — a permanent
            // strip there crowded the column and ran into the panel.
            let related = detail?.Related ?? []
            fullChrome.related = related
            infoPane.related = related
            refreshActionStates()
        }
    }

    var replies: [Replys.Reply] = [] { didSet { commentsPane.replies = replies } }
    var pages: [VideoPage] = []
    var onSelectPage: ((VideoPage) -> Void)?
    /// Fires when a 相关推荐 item is chosen, from either copy of the list.
    var onSelectRelated: ((VideoDetail.Info) -> Void)?
    /// Fires once the theater is really gone. The direct-enter path keeps an
    /// invisible detail screen underneath as the data source, and it has to go
    /// with the player rather than be revealed by its dismissal. Cleared before
    /// a deliberate swap (part / related video), which dismisses to re-present.
    var onExit: (() -> Void)?

    private(set) var mode: Mode = .fullscreen

    /// Mirrors of the three action buttons' tints, so a press can flip
    /// optimistically and revert on failure.
    private var isLiked = false
    private var isFavorited = false
    private var isInWatchLater = false

    // MARK: Children

    private let playerVC: VideoPlayerViewController
    private let playerContainer = UIView()
    /// 起播 / 缓冲指示器。
    ///
    /// AVPlayerViewController 自带的那个随 `showsPlaybackControls = false` 一起没了，
    /// 而这块屏在拿到播放地址之前是纯黑的：起播链路（cid → playurl → sidx → 首片）
    /// 全程没有任何反馈，慢一点就分不清"在加载"和"卡死了"。放在 playerContainer 里
    /// 而不是 fullChrome 里，缩到角落时它跟着画面走。
    private let loadingView = TheaterLoadingView()
    /// Feeds the indicator's speed line. Only runs while the indicator is up —
    /// nobody needs a 2Hz timer for a number that is not on screen.
    private let throughput = PlaybackThroughputMonitor()
    private var isLoading = false
    #if DEBUG
        private var previewHoldsLoading = false
        private var previewLoadingTimer: Timer?
    #endif
    /// Separates 起播 from 缓冲: the first wait has no picture behind it, every
    /// later one interrupts something the viewer was already watching.
    private var didBeginPlayback = false
    private let panel = UIView()
    private let miniBar = TheaterMiniBar()
    private let fullChrome = TheaterFullscreenChrome()
    private var controlsHideWork: DispatchWorkItem?
    private var titleHideWork: DispatchWorkItem?
    /// Swipe-to-wake, one per direction. Held so they can be switched off the
    /// moment the focus engine has something to move — see `updateWakeGestures`.
    private var wakeGestures: [UISwipeGestureRecognizer] = []

    /// Mirrors `AVPlayer.timeControlStatus`, but three states collapsed to two
    /// and a hole: `.playing` and `.paused` set it, a stall leaves it alone.
    private var isPlaying = false
    private var playbackStateObservation: NSKeyValueObservation?

    /// How long the title stays up once playback settles. Long enough to read a
    /// two-line CJK title from the sofa, short enough that it is gone before you
    /// are watching rather than reading.
    private static let titleLinger: TimeInterval = 2

    private lazy var chipBar = TheaterChipBar()
    private let paneContainer = UIView()
    private let commentsPane = TheaterCommentsPane()
    private let settingsPane = TheaterSettingsPane()
    private let infoPane = TheaterInfoPane()
    private let pagesPane = TheaterPagesPane()
    private var currentPane: TheaterPane = .comments
    private var mountedPane: UIViewController?

    /// Where an in-flight seek is headed, or nil when the playhead is its own
    /// authority. Both the accumulator for repeated steps and the value the
    /// transport reads while the seek is in flight — see `seek(by:)`.
    private var pendingSeekTarget: TimeInterval?

    private var timeObserver: Any?
    /// The player `timeObserver` is attached to. Not the same thing as
    /// `playerVC.currentPlayer` once a swap is under way — see
    /// `observePlaybackTime`.
    private weak var observedPlayer: AVPlayer?
    private var animator: UIViewPropertyAnimator?

    // MARK: Init

    init(playInfo: PlayInfo, nextProvider: VideoNextProvider? = nil) {
        playerVC = VideoPlayerViewController(playInfo: playInfo)
        playerVC.nextProvider = nextProvider
        super.init(nibName: nil, bundle: nil)
        // PiP restore re-presents the player. Embedded, the player is a child
        // and cannot be presented — the container has to stand in for it.
        playerVC.pipRestoreTarget = self
        // Seed from the play info so neither bar is blank while the detail
        // request is still in flight; `detail` overwrites both on arrival.
        miniBar.titleText = playInfo.title
        fullChrome.configure(title: playInfo.title, owner: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        #if DEBUG
            previewLoadingTimer?.invalidate()
        #endif
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Color.bg

        // Player
        playerContainer.backgroundColor = .black
        playerContainer.layer.cornerCurve = .continuous
        playerContainer.clipsToBounds = true
        view.addSubview(playerContainer)
        playerContainer.frame = view.bounds

        addChild(playerVC)
        playerContainer.addSubview(playerVC.view)
        playerVC.view.frame = playerContainer.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)

        // We draw the full-bleed transport ourselves, so the system one has to
        // go — and with it AVPlayerViewController's grab on the remote.
        playerVC.showsPlaybackControls = false
        playerVC.view.isUserInteractionEnabled = false

        playerContainer.addSubview(loadingView)
        loadingView.snp.makeConstraints { $0.edges.equalToSuperview() }
        throughput.onUpdate = { [weak self] bytesPerSecond in
            self?.loadingView.setSpeed(bytesPerSecond)
        }
        // 从剧场出现的那一刻就转：这时连 AVPlayer 都还没有，playbackStatusChanged
        // 一次都不会回调，没人替它开。
        setLoading(true)

        // 播放器是 child VC，报错弹窗得由容器来弹——见 VideoPlayerViewController.onLoadFailed。
        playerVC.onLoadFailed = { [weak self] message in self?.showLoadFailure(message) }

        view.addSubview(fullChrome)
        fullChrome.frame = view.bounds
        fullChrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fullChrome.onAction = { [weak self] action in self?.handle(action) }
        fullChrome.onSelectPane = { [weak self] pane in self?.dock(to: pane) }
        fullChrome.setDanmuOn(Defaults.shared.showDanmu)

        // Docked chrome — hidden until the player docks.
        view.addSubview(miniBar)
        view.addSubview(panel)
        miniBar.alpha = 0
        panel.alpha = 0
        setupPanel()
        installMenuHandling()
        installWakeGestures()
        layoutDockedChrome()


        // Every plugin's addMenuItems() output used to surface in the system
        // transport bar. That bar is gone, so route it into the 设置 pane instead
        // — otherwise 弹幕/倍速/画质/线路/Debug become unreachable.
        playerVC.onMenuItemsChanged = { [weak self] items in
            guard let self else { return }
            settingsPane.playerMenuItems = items
            // Plugins are rebuilt when the media finishes loading, which throws
            // away the danmaku layer the dock transition had already scaled.
            applyDanmuScale()
        }
        settingsPane.playerMenuItems = playerVC.currentMenuItems

        observePlaybackTime()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Only drive the frame from layout when we are not mid-animation;
        // otherwise a stray layout pass would snap the player to its end state.
        if animator == nil {
            playerContainer.frame = frame(for: mode)
            playerContainer.layer.cornerRadius = mode == .docked ? Theater.Metrics.dockRadius : 0
        }
        layoutDockedChrome()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        // A child is not covered by CommonPlayerViewController's own dismissal
        // check, so tear it down explicitly or the audio outlives the screen —
        // and so does everything behind it: the AVPlayer and its buffers, the
        // danmaku observer, the network-health timer.
        setLoading(false)
        playerVC.tearDownPlayback()
        playerVC.willMove(toParent: nil)
        playerVC.view.removeFromSuperview()
        playerVC.removeFromParent()
        onExit?()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if mode == .docked { return [chipBar] }
        // Idle full-bleed has nothing focusable at all — that is deliberate, so
        // the first press wakes the transport instead of activating something.
        return fullChrome.isShowingControls ? [fullChrome.preferredControl] : []
    }

    // MARK: Panel

    private func setupPanel() {
        panel.addSubview(chipBar)
        panel.addSubview(paneContainer)
        chipBar.onSelect = { [weak self] pane in self?.show(pane: pane) }

        // Comments open in place inside the pane, so there is nothing to hand
        // back out here — see TheaterCommentsPane.
        infoPane.onSelectRelated = { [weak self] info in self?.onSelectRelated?(info) }
        pagesPane.onSelect = { [weak self] page in self?.onSelectPage?(page) }
    }

    private func layoutDockedChrome() {
        typealias M = Theater.Metrics
        let b = view.bounds
        let sx = b.width / 1920, sy = b.height / 1080

        panel.frame = CGRect(x: M.panelX * sx, y: 0, width: M.panelWidth * sx, height: b.height)
        chipBar.frame = CGRect(x: 0, y: M.chipY * sy, width: panel.bounds.width, height: M.chipHeight * sy)
        paneContainer.frame = CGRect(x: M.panelInset * sx, y: M.paneBodyY * sy,
                                     width: panel.bounds.width - M.panelInset * sx,
                                     height: b.height - (M.paneBodyY + 60) * sy)
        mountedPane?.view.frame = paneContainer.bounds

        // Left column under the picture: title, elapsed, progress. Nothing
        // below it — 相关推荐 lives in the full-bleed transport now.
        let column = M.leftColumn(in: b)
        miniBar.frame = CGRect(x: column.minX, y: column.minY,
                               width: column.width, height: M.miniBarHeight * sy)
    }

    private func show(pane: TheaterPane) {
        guard pane != currentPane || mountedPane == nil else { return }
        currentPane = pane
        chipBar.select(pane)

        mountedPane?.willMove(toParent: nil)
        mountedPane?.view.removeFromSuperview()
        mountedPane?.removeFromParent()

        let next: UIViewController
        switch pane {
        case .info:
            infoPane.detail = detail
            next = infoPane
        case .comments:
            commentsPane.replies = replies
            next = commentsPane
        case .pages:
            pagesPane.pages = pages
            next = pagesPane
        case .settings:
            settingsPane.playerItem = playerVC.currentPlayer?.currentItem
            next = settingsPane
        }
        addChild(next)
        paneContainer.addSubview(next.view)
        next.view.frame = paneContainer.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        next.didMove(toParent: self)
        mountedPane = next
    }

    // MARK: Mode

    func dock(to pane: TheaterPane) {
        show(pane: pane)
        setMode(.docked)
    }

    // MARK: Remote

    /// Menu is taken as a gesture, not through `pressesBegan`.
    ///
    /// Measured on device: with the player embedded as a child, a Menu press
    /// made inside the panel never reaches this controller's press chain — the
    /// container is dismissed wholesale before it gets there, so every Menu
    /// press quit playback instead of stepping back one level. A recognizer on
    /// the container's own view sees the press whatever is focused, and it
    /// still does not see one meant for a presented sheet, because that sheet's
    /// view is not a descendant of this one.
    private func installMenuHandling() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(tap)
    }

    /// Waking the transport from the remote's touch surface.
    ///
    /// `pressesBegan` cannot do this job, and no amount of work on it will: a
    /// swipe across the Siri Remote's surface is an *indirect touch* and
    /// produces no `UIPress` at all. The `.upArrow`-family press types come only
    /// from a hard click of the clickpad ring. So the transport answered a click
    /// and the Play/Pause button, and a swipe — the gesture every other tvOS
    /// player wakes on — did nothing, leaving stopping the video as the only way
    /// to raise the controls.
    ///
    /// Any direction wakes. Apple's own transport comes up on a touch rather
    /// than on a particular gesture, and there is nothing else here a swipe
    /// could mean.
    ///
    /// Live only while the transport is down. Once it is up the same swipes
    /// belong to the focus engine, moving between the scrubber, the action row
    /// and the 相关推荐 rail, and a recognizer on an ancestor view would be
    /// competing with it for them.
    private func installWakeGestures() {
        // One recognizer per direction rather than a single four-bit mask: the
        // remote's surface is short and a real thumb stroke is rarely square, so
        // a mask that has to resolve one direction can drop an off-axis swipe.
        // Four independent recognizers all mean the same thing here, and any one
        // of them matching is enough.
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(wakeGesture))
            swipe.direction = direction
            // Spelled out rather than inherited: UIGestureRecognizer.h says the
            // default for this is "platform dependent", and the remote's surface
            // is an indirect touch. The one other place in this codebase that
            // needed remote touches had to set it too (Archive/
            // VideoDetailViewController.swift, the scrollable description).
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            view.addGestureRecognizer(swipe)
            wakeGestures.append(swipe)
        }
        // No recognizer for the *click* half. Measured in the simulator with both
        // paths logged: a Select or arrow click already arrives at `pressesBegan`
        // below, with nothing focused, and wakes the transport from there. A tap
        // recognizer for those press types never fired even once — showControls()
        // disables these recognizers before the press ends.

        // Waking is an observation, not a consumption: nothing here should
        // swallow or hold up the touch stream the focus engine, the chip bar's
        // scroll view and the rail all run on.
        for gesture in wakeGestures {
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
        }
        updateWakeGestures()
    }

    @objc private func wakeGesture() {
        guard mode == .fullscreen, !fullChrome.isShowingControls else { return }
        showControls()
    }

    /// The same wake, one step earlier in the touch's life.
    ///
    /// Two reasons it is here as well as on the recognizers. It is what Apple's
    /// player actually does — a thumb *resting* on the surface brings the
    /// transport up, no completed gesture required — so this is the behaviour
    /// being matched rather than an approximation of it. And it is a second
    /// delivery path: presses were measured reaching this controller with
    /// nothing focused, so the responder chain is live in the idle state, but
    /// tvOS routes indirect touches by their own rules and this could not be
    /// exercised without driving the simulator's remote window. Whichever path
    /// the touch takes, the transport comes up; both land on the same
    /// idempotent `showControls`.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard mode == .fullscreen, !fullChrome.isShowingControls,
              touches.contains(where: { $0.type == .indirect }) else { return }
        showControls()
    }

    private func updateWakeGestures() {
        let idle = mode == .fullscreen && !fullChrome.isShowingControls
        wakeGestures.forEach { $0.isEnabled = idle }
    }

    /// One step back per press: thread → comment list → full-bleed → out.
    @objc private func menuPressed() {
        if mode == .docked {
            // A comment thread is opened inside the pane, not presented, so
            // Menu has to unwind it here before it means "collapse".
            if currentPane == .comments, commentsPane.popThread() { return }
            setMode(.fullscreen)
            return
        }
        if fullChrome.isShowingControls {
            hideControls()
            return
        }
        dismiss(animated: true)
    }

    /// AVPlayerViewController normally owns all of this. With its controls off,
    /// every press lands here first.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let type = presses.first?.type

        if type == .playPause {
            handle(.playPause)
            return
        }

        if mode == .docked {
            super.pressesBegan(presses, with: event)
            return
        }

        if !fullChrome.isShowingControls {
            // Idle: any directional press or a click wakes the transport rather
            // than doing anything to playback. Measured to genuinely fire here
            // with nothing focused, which is why the wake recognizers next door
            // only cover swipes — this is already the click path.
            switch type {
            case .select, .upArrow, .downArrow, .leftArrow, .rightArrow:
                showControls()
                return
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func handle(_ action: TheaterFullscreenChrome.Action) {
        switch action {
        case .playPause:
            guard let player = playerVC.currentPlayer else { return }
            let playing = player.timeControlStatus != .paused
            playing ? player.pause() : player.play()
            fullChrome.setPlaying(!playing)
            if mode == .fullscreen { showControls() }
        case let .seek(delta):
            seek(by: delta)
            showControls()
        case .toggleDanmu:
            Defaults.shared.showDanmu.toggle()
            fullChrome.setDanmuOn(Defaults.shared.showDanmu)
            fullChrome.showToast(Defaults.shared.showDanmu ? "弹幕已开启" : "弹幕已关闭")
            showControls()
        case .toggleLike:
            toggleLike()
        case .toggleFavorite:
            toggleFavorite()
        case .toggleWatchLater:
            toggleWatchLater()
        }
    }

    // MARK: Seeking

    /// Steps the playhead, from wherever the *last* step was headed.
    ///
    /// `player.currentTime()` does not move until a seek lands, and a seek takes
    /// long enough that a second press always beats it: five quick taps on ±10s
    /// — or five clicks along the scrubber — all measured from the same starting
    /// point and added up to one jump of ten seconds. Stacking on the pending
    /// target instead makes them add up to fifty, which is what pressing a
    /// button five times means.
    ///
    /// The transport is moved here rather than left to the periodic observer:
    /// that observer is a quarter-second behind and reads the player's *old*
    /// position until the seek lands, so the bar sat still under the press and
    /// then jumped.
    private func seek(by delta: TimeInterval) {
        guard let player = playerVC.currentPlayer, let item = player.currentItem else { return }
        let total = item.duration.seconds
        let base = pendingSeekTarget ?? player.currentTime().seconds
        guard base.isFinite else { return }
        let target = max(0, min(total.isFinite ? total : .greatestFiniteMagnitude, base + delta))
        pendingSeekTarget = target
        if total.isFinite, total > 0 {
            fullChrome.update(current: target, total: total)
            miniBar.update(current: target, total: total)
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        { [weak self] _ in
            // Back to main before touching the accumulator: AVFoundation makes no
            // promise about the queue this lands on, and every other reader of it
            // is on the main thread. Same hop the playback-state observation does.
            DispatchQueue.main.async {
                // Ignoring `finished`: a superseded seek reports false, and the
                // seek that superseded it owns the target now — this check is what
                // tells the two apart. Cleared on failure too, rather than leaving
                // the readout pinned to a position playback never reached.
                guard let self, self.pendingSeekTarget == target else { return }
                self.pendingSeekTarget = nil
            }
        }
    }

    // MARK: - 点赞 / 收藏 / 稍后再看
    //
    // The transport is a 10-foot surface, so each of these is one press with an
    // immediate tint change; the request follows and the tint reverts only if it
    // fails. 收藏 goes to the default folder rather than opening a picker over
    // the picture — the folder list lives in the detail screen, which is where
    // choosing between folders belongs.

    private var actionAid: Int? { detail?.View.aid }

    private func refreshActionStates() {
        guard let aid = actionAid else { return }
        WebRequest.requestLikeStatus(aid: aid) { [weak self] on in
            self?.isLiked = on
            self?.fullChrome.setLiked(on)
        }
        WebRequest.requestFavoriteStatus(aid: aid) { [weak self] on in
            self?.isFavorited = on
            self?.fullChrome.setFavorited(on)
        }
        // No status call for 稍后再看: the API only offers the whole list, and
        // pulling it just to tint one button is not worth the request. The
        // button starts untinted and tracks presses within the session.
    }

    private func toggleLike() {
        guard let aid = actionAid else { return }
        let next = !isLiked
        isLiked = next
        fullChrome.setLiked(next)
        showControls()
        Task { @MainActor in
            let ok = await WebRequest.requestLike(aid: aid, like: next)
            if ok {
                fullChrome.showToast(next ? "已点赞" : "已取消点赞")
            } else {
                isLiked = !next
                fullChrome.setLiked(!next)
                fullChrome.showToast("点赞失败")
            }
        }
    }

    private func toggleFavorite() {
        guard let aid = actionAid else { return }
        let next = !isFavorited
        isFavorited = next
        fullChrome.setFavorited(next)
        showControls()
        Task { @MainActor in
            guard let folders = try? await WebRequest.requestFavVideosList(),
                  let first = folders.first
            else {
                isFavorited = !next
                fullChrome.setFavorited(!next)
                fullChrome.showToast("收藏失败")
                return
            }
            if next {
                WebRequest.requestFavorite(aid: aid, mid: first.id)
                fullChrome.showToast("已收藏到「\(first.title)」")
            } else {
                WebRequest.removeFavorite(aid: aid, mid: folders.map(\.id))
                fullChrome.showToast("已取消收藏")
            }
        }
    }

    private func toggleWatchLater() {
        guard let aid = actionAid else { return }
        isInWatchLater.toggle()
        fullChrome.setWatchLater(isInWatchLater)
        showControls()
        if isInWatchLater {
            WebRequest.requestAddToView(aid: aid)
            fullChrome.showToast("已添加到稍后再看")
        } else {
            WebRequest.requestRemoveToView(aid: aid)
            fullChrome.showToast("已移出稍后再看")
        }
    }

    /// Moving around inside the transport counts as using it. Without this the
    /// row — and the 相关推荐 rail under it — disappeared five seconds in while
    /// the user was still reading, which is far too little for a list you are
    /// meant to browse.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard mode == .fullscreen, fullChrome.isShowingControls,
              context.nextFocusedItem != nil else { return }
        if fullChrome.isInRail(context.nextFocusedItem) {
            controlsHideWork?.cancel()
        } else {
            armControlsHide()
        }
    }

    /// Internal rather than private so the DEBUG preview launcher can bring the
    /// transport up without synthesising a remote press.
    func showControls() {
        // Only *arriving* controls take focus. Every button routes back through
        // here to restart the auto-hide, and `preferredFocusEnvironments` names
        // the play button — so asking for an update while the row is already up
        // threw focus back to the head of the row on every press: one ±10s or
        // 弹幕 tap and the next one landed on play/pause instead.
        let takesFocus = !fullChrome.isShowingControls
        fullChrome.setControls(true)
        if takesFocus {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
        armControlsHide()
        updateWakeGestures()
        refreshTitleVisibility()
    }

    private func armControlsHide() {
        controlsHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, mode == .fullscreen else { return }
            hideControls()
        }
        controlsHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func hideControls() {
        controlsHideWork?.cancel()
        fullChrome.setControls(false)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        updateWakeGestures()
        // No beat here: the title came up as the transport's heading and goes
        // back down with it. The two-second grace is for the start of playback,
        // not for every auto-hide.
        refreshTitleVisibility()
    }

    // MARK: Title

    /// Title visibility, decided in one place.
    ///
    /// It is up whenever there is a reason to read it — the transport is showing,
    /// or playback is not running (still loading, paused, finished) — and gone
    /// otherwise, so a video that is simply playing plays against nothing.
    ///
    /// `afterBeat` is the two-second grace at the start of playback: the title
    /// has just become droppable but has not been on screen long enough to have
    /// been read yet.
    private func refreshTitleVisibility(afterBeat: Bool = false) {
        titleHideWork?.cancel()
        titleHideWork = nil
        // Docked, the mini bar carries the title and the chrome is hidden
        // anyway; touching it here would only fight `setMode`.
        guard mode == .fullscreen else { return }

        guard isPlaying, !fullChrome.isShowingControls else {
            fullChrome.setTitle(visible: true)
            return
        }
        guard afterBeat else {
            fullChrome.setTitle(visible: false)
            return
        }
        fullChrome.setTitle(visible: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self, mode == .fullscreen,
                  isPlaying, !fullChrome.isShowingControls else { return }
            fullChrome.setTitle(visible: false)
        }
        titleHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.titleLinger, execute: work)
    }

    /// `timeControlStatus` rather than `rate` or the plugin callbacks: it is the
    /// only signal that tells a user pause apart from a stall, and the plugins'
    /// `playerDidPause` is deliberately suppressed at end-of-item.
    private func playbackStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        fullChrome.setPlaying(status != .paused)
        switch status {
        case .playing:
            // Only a false → true edge earns the beat. Without that test every
            // recovered stall would put the title back up for two seconds.
            let started = !isPlaying
            isPlaying = true
            didBeginPlayback = true
            setLoading(false)
            refreshTitleVisibility(afterBeat: started)
        case .paused:
            isPlaying = false
            // A pause is a state, not a wait — including the pause at the end of
            // the video. Leaving the spinner up over a still picture would read
            // as "still loading" forever.
            setLoading(false)
            refreshTitleVisibility()
        default:
            // Buffering. The title is deliberately left alone — on a slow line it
            // would blink in and out for the length of the video — but this is
            // exactly when the spinner belongs.
            setLoading(true)
        }
    }

    private func setLoading(_ on: Bool) {
        #if DEBUG
            // The preview has no media, so the player settles on `.paused` and
            // would take the indicator down a beat after it went up.
            if previewHoldsLoading, !on { return }
        #endif
        guard on != isLoading else { return }
        isLoading = on
        loadingView.phase = didBeginPlayback ? .buffering : .starting
        loadingView.setActive(on)
        guard on else { return throughput.stop() }
        // Fetched per tick rather than captured: 换画质 / 换线路 swaps the whole
        // AVPlayer out from under us.
        throughput.start { [weak self] in self?.playerVC.currentPlayer }
    }

    /// 起播失败：弹窗 + 退出，都由容器做。
    ///
    /// 播放器自己 present 会在剧场还在做 present 动画时被 UIKit 丢掉，用户只剩一块
    /// 不会动的黑屏——这正是"点了没反应"的一种。`MorphingModalController` 和它取代的
    /// UIAlertController 一样，会在 handler 之前先把自己关掉，所以那时 `dismiss`
    /// 关的就是剧场本身。
    private func showLoadFailure(_ message: String) {
        #if DEBUG
            if previewHoldsLoading { return }
        #endif
        setLoading(false)
        presentModalNotice(title: "播放失败", message: message) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func frame(for mode: Mode) -> CGRect {
        mode == .docked ? Theater.Metrics.dockRect(in: view.bounds) : view.bounds
    }

    private func setMode(_ next: Mode, animated: Bool = true) {
        guard next != mode else { return }
        mode = next
        let docking = next == .docked

        // The native transport only makes sense full-bleed; docked, the mini bar
        // and the panel are the interface.
        if docking {
            // Collapsing returns to the *bare* full-bleed state, matching the
            // reference: no scrim, no transport, just the title block.
            controlsHideWork?.cancel()
            fullChrome.setControls(false, animated: false)
        }
        miniBar.isHidden = false
        panel.isHidden = false
        fullChrome.isHidden = false

        animator?.stopAnimation(true)
        let duration = docking ? Theater.Motion.expand : Theater.Motion.collapse
        let curve = docking ? Theater.Motion.expandCurve : Theater.Motion.collapseCurve
        let target = frame(for: next)
        let radius: CGFloat = docking ? Theater.Metrics.dockRadius : 0

        // Chrome cross-fades around the picture rather than with it: the old
        // layer clears first, the new one arrives while the frame is still
        // travelling. That overlap is what reads as one movement.
        UIView.animate(withDuration: Theater.Motion.chromeFade) {
            self.miniBar.alpha = docking ? 1 : 0
            self.panel.alpha = docking ? 1 : 0
            self.fullChrome.alpha = docking ? 0 : 1
        }

        guard animated else {
            playerContainer.frame = target
            playerContainer.layer.cornerRadius = radius
            applyDanmuScale()
            finishMode()
            return
        }

        let anim = UIViewPropertyAnimator(duration: duration, timingParameters: curve.timingParameters)
        anim.addAnimations { [weak self] in
            self?.playerContainer.frame = target
            self?.applyDanmuScale()
        }
        anim.addCompletion { [weak self] _ in
            self?.animator = nil
            self?.finishMode()
        }
        animator = anim

        // cornerRadius is a layer property; drive it alongside on the same curve.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = playerContainer.layer.cornerRadius
        radiusAnim.toValue = radius
        radiusAnim.duration = duration
        radiusAnim.timingFunction = curve.mediaTimingFunction
        playerContainer.layer.cornerRadius = radius
        playerContainer.layer.add(radiusAnim, forKey: "cornerRadius")

        anim.startAnimation(afterDelay: docking ? Theater.Motion.expandLeadIn : 0)
    }

    private func finishMode() {
        miniBar.isHidden = mode != .docked
        panel.isHidden = mode != .docked
        fullChrome.isHidden = mode == .docked
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        updateWakeGestures()
        // Collapsing back out of the panel lands on the bare picture with no
        // chrome at all. The title gets the same two-second beat it gets at the
        // start of playback — it is the one thing that says what you came back to.
        refreshTitleVisibility(afterBeat: mode == .fullscreen)
    }

    /// Keeps the danmaku layer the same size *relative to the picture* in both
    /// modes. Without it the docked video carried full-screen-sized danmaku,
    /// which covered the frame and spilled past its edges.
    private func applyDanmuScale() {
        let scale = mode == .docked ? Theater.Metrics.dockSize.width : 1
        playerVC.plugin(ofType: DanmuViewPlugin.self)?.setPresentationScale(scale)
    }

    #if DEBUG
        /// Preview hook — see TheaterPreviewLauncher.
        func previewOpenFirstThread() {
            show(pane: .comments)
            commentsPane.previewOpenFirstThread()
        }

        /// Toasts are only ever raised by an action-row press, which needs a
        /// remote; this puts one up so its layout can be checked in one launch.
        func previewShowToast(_ text: String) {
            fullChrome.showToast(text)
        }

        func previewPreferRail() {
            fullChrome.previewPrefersRail = true
        }

        /// Holds the loading indicator up and drives its speed line by hand, so
        /// both of its moving parts can be checked without arranging a real
        /// stall. The rates walk every branch of the formatter and every digit
        /// count, which is what the tabular figures are there for.
        ///
        /// Also suppresses 播放失败: with no aid the preview always fails, and
        /// that alert takes focus and dismisses the whole theater a second in.
        func previewHoldLoading() {
            previewHoldsLoading = true
            setLoading(true)
            // Nothing to measure — there is no player — so the monitor would
            // only publish nil over the top of these.
            throughput.stop()
            let rates: [Double] = [0, 45, 512, 999, 1024, 2458, 13_005].map { $0 * 1024 }
            var index = 0
            previewLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) {
                [weak self] _ in
                self?.loadingView.setSpeed(rates[index % rates.count])
                index += 1
            }
        }
    #endif

    // MARK: Progress

    private func observePlaybackTime() {
        // The player instance is swapped when the CDN line or quality changes,
        // so re-attach whenever it appears rather than observing once.
        playerVC.onPlayerChanged = { [weak self] player in
            guard let self else { return }
            // Detach from the player we actually attached to. Reading it back
            // off the player VC here gets the *new* one — this callback runs
            // after the swap — which left the old player observing forever, and
            // since a periodic observer's block is retained by the player, an
            // AVPlayer (with its item, its decoder and its buffers) leaked on
            // every quality or CDN change.
            if let timeObserver, let old = observedPlayer {
                old.removeTimeObserver(timeObserver)
            }
            observedPlayer = player
            // A seek aimed at the old player means nothing to the new one, and
            // its completion will never come to clear this.
            pendingSeekTarget = nil
            // `player` weakly: the player retains this block, so capturing it
            // strongly is a cycle that outlives the screen.
            self.timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main)
            { [weak self, weak player] time in
                guard let self, let player, let item = player.currentItem else { return }
                let total = item.duration.seconds
                guard total.isFinite, total > 0 else { return }
                // A pending seek owns the readout until it lands: this observer
                // reports the position the playhead is leaving, which would drag
                // the bar back to it between presses.
                let current = self.pendingSeekTarget ?? time.seconds
                self.miniBar.update(current: current, total: total)
                self.fullChrome.update(current: current, total: total)
                self.fullChrome.setPlaying(player.timeControlStatus != .paused)
            }
            observePlaybackState(of: player)
        }
    }

    /// Deliberately without `.initial`, and deliberately without re-seeding
    /// `isPlaying`: a player swapped in for a CDN line or quality change is
    /// `.paused` for a moment before it is told to play, and letting that read
    /// as a pause would flash the title back up in the middle of a switch the
    /// user never asked to see. Only edges the player actually crosses under
    /// this observation count, so a swap is invisible to the title state.
    private func observePlaybackState(of player: AVPlayer) {
        // `[weak self]` on the *outer* closure. Putting it on the inner one
        // instead still leaves the outer closure capturing self strongly, and
        // self owns the observation — the same cycle the periodic observer above
        // is at such pains to avoid.
        playbackStateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            DispatchQueue.main.async { self?.playbackStatusChanged(status) }
        }
    }
}

// The 详情 transport-bar menu that used to live here is gone: the pane chips
// are part of the self-drawn transport now, so the panes are one press away
// instead of nested inside a menu.

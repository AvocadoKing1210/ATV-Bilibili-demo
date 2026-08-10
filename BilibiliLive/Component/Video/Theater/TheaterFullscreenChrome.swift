//
//  TheaterFullscreenChrome.swift
//  BilibiliLive
//
//  Self-drawn full-bleed player controls, replacing AVPlayerViewController's.
//
//  Positions are the ones measured off the reference recording at 1920×1080
//  (docs/preview/player-transition.html is the browser rig for them):
//
//      idle      artwork (96,756) 200²   · title x=336 · 60pt
//      controls  artwork (94,448) 205²   · title x=331
//                progress y=736, x 252→1830
//                play/pause centre (156,740) ⌀85
//                action row centre y=853, ⌀80, x 156 + n·103 (six buttons)
//                pane chips  y 813→893, right-aligned to 1830
//
//  Play button and action row share the x=156 centre line — one column, the
//  way the reference stacks them.
//
//  Revealing the controls lifts the title block and drops a scrim over the
//  picture — the idle state deliberately has no scrim, matching the reference.
//

import AVKit
import SnapKit
import UIKit

// MARK: - Circular focusable button

/// BLButton with a pill/circular mask. The base class hardcodes an 8pt radius,
/// which reads as a rounded square at transport sizes.
final class TheaterRoundButton: BLButton {
    private let iconView = UIImageView()

    var icon: UIImage? {
        didSet { iconView.image = icon }
    }

    /// Toggled controls (danmaku) fill with the accent so state survives at 10ft.
    var isOn = false {
        didSet { updateTint() }
    }

    override func setup() {
        super.setup()
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalToSuperview().multipliedBy(0.42)
        }
        updateTint()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        clipsToBounds = true
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        // BLButton grows the control by 1.1 on focus. In a row of six equal
        // circles that reads as the row shuffling; the white fill already says
        // which one is selected, so the size stays put.
        coordinator.addCoordinatedAnimations { [weak self] in
            self?.transform = .identity
            self?.updateTint()
        }
    }

    private func updateTint() {
        iconView.tintColor = isFocused ? .black : (isOn ? DS.Color.accent : .white)
    }
}

// MARK: - Scrubber

/// Focusable progress bar. Left/right — clicked *or* swiped — are consumed here
/// and turned into seeks, so the focus engine does not steal them to move
/// sideways; that is the price of dropping AVPlayerViewController's own
/// scrubber. Refusing the focus move is the other half of it and lives in
/// `TheaterFullscreenChrome.shouldUpdateFocus`, which is the environment tvOS
/// actually asks.
final class TheaterScrubber: UIControl {
    var onSeek: ((TimeInterval) -> Void)?
    /// Select on the bar. Apple's transport toggles playback from the scrubber
    /// rather than from a neighbouring button, and here it is also what keeps
    /// the play button one press away now that Left seeks instead of landing on
    /// it.
    var onPlayPause: (() -> Void)?
    /// Seconds per press. Matches the ±10s buttons either side of it.
    var step: TimeInterval = 10

    private let track = UIView()
    private let fill = UIView()
    private let knob = UIView()

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = UIColor.white.withAlphaComponent(0.26)
        fill.backgroundColor = DS.Color.accent
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 11
        knob.isHidden = true

        addSubview(track)
        track.addSubview(fill)
        addSubview(knob)
        track.snp.makeConstraints { make in
            make.leading.trailing.centerY.equalToSuperview()
            make.height.equalTo(8)
        }
        fill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(0)
        }
        knob.snp.makeConstraints { make in
            make.width.height.equalTo(22)
            make.centerY.equalTo(track)
            make.centerX.equalTo(track.snp.leading)
        }

        // A swipe across the remote's surface is an indirect touch and produces
        // no `UIPress` at all — `pressesBegan` below only ever sees a hard click
        // of the clickpad ring — so scrubbing the way every other tvOS player
        // scrubs needs its own recognizers. Same asymmetry the transport's
        // swipe-to-wake had to work around; see `installWakeGestures`.
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            swipe.direction = direction
            // Spelled out rather than inherited: UIGestureRecognizer.h calls the
            // default "platform dependent", and the remote's surface is an
            // indirect touch.
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(swipe)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        onSeek?(gesture.direction == .left ? -step : step)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.layer.cornerRadius = 4
        fill.layer.cornerRadius = 4
    }

    private var progress: Double = 0

    func update(progress p: Double) {
        progress = max(0, min(1, p))
        let w = track.bounds.width * progress
        fill.snp.updateConstraints { $0.width.equalTo(w) }
        knob.snp.updateConstraints { $0.centerX.equalTo(track.snp.leading).offset(w) }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.knob.isHidden = !self.isFocused
            self.track.transform = self.isFocused ? CGAffineTransform(scaleX: 1, y: 1.4) : .identity
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isFocused else { return super.pressesBegan(presses, with: event) }
        switch presses.first?.type {
        case .leftArrow: onSeek?(-step)
        case .rightArrow: onSeek?(step)
        default: super.pressesBegan(presses, with: event)
        }
    }

    /// Select, on the ended half of the press — the same edge `BLButton` fires
    /// its primary action on, so the whole transport answers a click at the same
    /// moment.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isFocused, presses.first?.type == .select else {
            return super.pressesEnded(presses, with: event)
        }
        onPlayPause?()
    }
}

// MARK: - Toast

/// Transient confirmation for the action row.
///
/// The buttons already re-tint, but a tint is easy to miss from ten feet and
/// says nothing about whether the request actually landed — 收藏 in particular
/// flips optimistically and can fail afterwards. tvOS has no system toast, so
/// this is the app's: top-centre, never focusable, gone in two seconds.
final class TheaterToast: UIView {
    private let label = UILabel()
    /// `.dark` rather than a system material: tvOS ships neither the thick
    /// materials nor `.systemChromeMaterial`, and it is what the rest of the
    /// app's blurred surfaces already use.
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Never take focus and never swallow a press aimed at the transport
        // underneath — this is a readout, not a control.
        isUserInteractionEnabled = false
        alpha = 0
        clipsToBounds = true
        layer.cornerCurve = .continuous
        // A dark blur over a dark frame is nearly the frame. The hairline is
        // what gives the pill an edge on black; on a bright frame the blur
        // already carries it.
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor

        label.font = DS.Font.navLabel
        label.textColor = .white
        label.textAlignment = .center

        addSubview(blur)
        addSubview(label)
        blur.snp.makeConstraints { $0.edges.equalToSuperview() }
        label.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(DS.Chip.hInset)
        }
        snp.makeConstraints { $0.height.equalTo(DS.Chip.height) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func show(_ text: String, for duration: TimeInterval = 2) {
        label.text = text
        // A second press re-arms the timer rather than letting the first one
        // dismiss the new message early.
        hideWork?.cancel()
        superview?.bringSubviewToFront(self)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
            self.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                self?.alpha = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - Full-bleed chrome

final class TheaterFullscreenChrome: UIView {
    enum Action {
        case playPause
        case seek(TimeInterval)
        case toggleDanmu
        case toggleLike
        /// 收藏 — picks a folder. Distinct from `toggleWatchLater`, which is
        /// the transient 稍后再看 queue.
        case toggleFavorite
        case toggleWatchLater
    }

    var onAction: ((Action) -> Void)?
    var onSelectPane: ((TheaterPane) -> Void)?
    var onSelectRelated: ((VideoDetail.Info) -> Void)?

    /// 相关推荐 for the rail under the action row. Empty hides the strip, which
    /// is why the transport's other rows are pinned to the bottom rather than
    /// stacked on it.
    var related: [VideoDetail.Info] = [] {
        didSet { relatedRail.items = related }
    }

    private(set) var isShowingControls = false

    /// The idle title block is not permanent chrome — it introduces what is
    /// playing and then gets out of the picture. Driven by the container, which
    /// owns the playback state that decides when that is: see
    /// `VideoTheaterViewController.refreshTitleVisibility`.
    private(set) var isShowingTitle = true

    /// The transport sits low, near the bottom safe area, rather than floating
    /// in the middle third the way the music-player reference did.
    ///
    /// It used to sit lower still (progress 858, buttons 962). 相关推荐 now
    /// occupies the bottom strip, so the whole column moved up by ~220 to make
    /// room — the rail reads as the last row of the transport rather than as
    /// something floating over the picture on its own.
    ///
    /// These are the *raised* positions: progress, buttons, chips and the shelf
    /// are one column that scrolls as a unit (see `columnDrop`), and this is
    /// where it lands with the shelf focused. At rest everything below sits
    /// `columnDrop` lower.
    private enum Layout {
        static let progressY: CGFloat = 640
        static let buttonRowY: CGFloat = 744
        static let titleBottomIdle: CGFloat = 100 // → bottom edge at y=980
        static let titleBottomControls: CGFloat = 540 // → bottom edge at y=540
        static let sideMargin: CGFloat = 90

        /// 相关推荐, under the action row. Header + one row of 16:9 cards.
        static let railHeight: CGFloat = 213
        static let railBottom: CGFloat = 40

        /// How far the column rests below its raised frame.
        ///
        /// The shelf used to move on its own while the rows above it stayed put,
        /// which meant the gap between the action row and the shelf header was
        /// the thing that changed — ~190pt of empty scrim at rest, closing to 43
        /// on focus. Now the rows and the shelf travel together, so that gap is
        /// a constant 43 and this is the only thing that moves: the transport
        /// rides 90pt lower until focus reaches the shelf, then the whole column
        /// scrolls up to bring the cards fully on screen.
        ///
        /// 90 leaves the card titles off the bottom edge and clips the last few
        /// points of the thumbnails at rest — enough of a cut edge to read as
        /// "there is more down here" without hiding what the cards are.
        static let columnDrop: CGFloat = 90

        /// Transport column. The play button and the action row share one
        /// centre line, the way the reference player stacks them — the row used
        /// to start 104pt to its right, which read as two unrelated groups.
        static let columnX: CGFloat = 156
        /// 106 originally. Dropped 20%: at full size it out-weighed the row
        /// beneath it and crowded the scrubber's left end.
        static let playDiameter: CGFloat = 85
        static let actionDiameter: CGFloat = 80
        static let actionPitch: CGFloat = 103
    }

    let scrim = UIView()
    private let bottomShade = UIView()
    /// Everything that scrolls together: progress row, play button, action row,
    /// pane chips and the shelf. Pinned edge-to-edge over the chrome, so the
    /// absolute offsets its children use still read against the 1920×1080
    /// frame; the scrolling is a translation on this view, not a relayout.
    private let column = UIView()
    private let titleStack = UIStackView()
    private let titleLabel = UILabel()
    private let ownerLabel = UILabel()

    private let scrubber = TheaterScrubber()
    private let currentLabel = UILabel()
    private let totalLabel = UILabel()
    private let playButton = TheaterRoundButton()
    private let backButton = TheaterRoundButton()
    private let forwardButton = TheaterRoundButton()
    private let danmuButton = TheaterRoundButton()
    private let likeButton = TheaterRoundButton()
    private let favButton = TheaterRoundButton()
    private let laterButton = TheaterRoundButton()
    private let chipBar = TheaterChipBar()
    private let relatedRail = TheaterRelatedRail()
    private let toast = TheaterToast()

    /// The action row, in display order. Seeking first, then the danmaku
    /// switch, then the three that act on the video itself.
    private var actionButtons: [TheaterRoundButton] {
        [backButton, forwardButton, danmuButton, likeButton, favButton, laterButton]
    }

    private var titleBottomConstraint: Constraint?
    private var isColumnRaised = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildScrim()
        buildTitleBlock()
        buildTransport()
        buildToast()
        setControls(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Build

    private func buildScrim() {
        scrim.backgroundColor = .black
        scrim.alpha = 0
        scrim.isUserInteractionEnabled = false
        addSubview(scrim)
        scrim.snp.makeConstraints { $0.edges.equalToSuperview() }

        // Bottom shade so the idle title stays legible on bright video. It
        // exists for the title alone and leaves with it — see `applyTitleAlpha`.
        bottomShade.isUserInteractionEnabled = false
        addSubview(bottomShade)
        bottomShade.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(520)
        }
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]
        gradient.locations = [0, 1]
        bottomShade.layer.addSublayer(gradient)
        bottomShadeGradient = gradient
    }

    private var bottomShadeGradient: CAGradientLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        bottomShadeGradient?.frame = bottomShade.bounds
    }

    /// No artwork: the poster is redundant next to the video it was cut from,
    /// and dropping it lets the title start at the same 96pt margin the rest of
    /// the chrome uses. Owner sits above the title, matching the watch page.
    private func buildTitleBlock() {
        titleLabel.font = .systemFont(ofSize: 60, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        ownerLabel.font = .systemFont(ofSize: 28, weight: .medium)
        ownerLabel.textColor = UIColor.white.withAlphaComponent(0.7)

        titleStack.axis = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 10
        titleStack.addArrangedSubview(ownerLabel)
        titleStack.addArrangedSubview(titleLabel)
        addSubview(titleStack)

        titleStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(96)
            make.trailing.lessThanOrEqualToSuperview().offset(-620)
            titleBottomConstraint = make.bottom.equalToSuperview().offset(-Layout.titleBottomIdle).constraint
        }
    }

    private func buildTransport() {
        currentLabel.font = .systemFont(ofSize: 25, weight: .medium)
        totalLabel.font = currentLabel.font
        currentLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        totalLabel.textColor = currentLabel.textColor
        totalLabel.textAlignment = .right

        playButton.icon = UIImage(systemName: "pause.fill")
        backButton.icon = UIImage(systemName: "gobackward.10")
        forwardButton.icon = UIImage(systemName: "goforward.10")
        danmuButton.icon = Icon.danmakuOn.image
        likeButton.icon = Icon.like.image
        favButton.icon = Icon.favorite.image
        laterButton.icon = Icon.watchLaterPlay.image

        playButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.playPause) }
        backButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.seek(-10)) }
        forwardButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.seek(10)) }
        danmuButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.toggleDanmu) }
        likeButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.toggleLike) }
        favButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.toggleFavorite) }
        laterButton.onPrimaryAction = { [weak self] _ in self?.onAction?(.toggleWatchLater) }
        scrubber.onSeek = { [weak self] delta in self?.onAction?(.seek(delta)) }
        scrubber.onPlayPause = { [weak self] in self?.onAction?(.playPause) }
        chipBar.onSelect = { [weak self] pane in self?.onSelectPane?(pane) }
        chipBar.style = .overlay

        addSubview(column)
        column.snp.makeConstraints { $0.edges.equalToSuperview() }

        ([scrubber, currentLabel, totalLabel, playButton, chipBar] as [UIView] + actionButtons)
            .forEach(column.addSubview)

        scrubber.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(252)
            make.trailing.equalToSuperview().offset(-Layout.sideMargin)
            make.centerY.equalToSuperview().offset(Layout.progressY - 540)
            make.height.equalTo(40)
        }
        currentLabel.snp.makeConstraints { make in
            make.leading.equalTo(scrubber)
            make.top.equalTo(scrubber.snp.bottom).offset(2)
        }
        totalLabel.snp.makeConstraints { make in
            make.trailing.equalTo(scrubber)
            make.top.equalTo(currentLabel)
        }
        playButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview().offset(Layout.columnX - 960)
            make.centerY.equalToSuperview().offset(Layout.progressY - 540)
            make.width.height.equalTo(Layout.playDiameter)
        }
        for (i, b) in actionButtons.enumerated() {
            b.snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                    .offset(Layout.columnX + CGFloat(i) * Layout.actionPitch - 960)
                make.centerY.equalToSuperview().offset(Layout.buttonRowY - 540)
                make.width.height.equalTo(Layout.actionDiameter)
            }
        }
        chipBar.snp.makeConstraints { make in
            // The bar hugs its chips (see TheaterChipBar.style), so trailing is
            // pulled in by the scroll view's own 10pt inset to put the last
            // chip's edge exactly on the 1830 margin rather than 10pt inside it.
            make.trailing.equalToSuperview().offset(-Layout.sideMargin + 10)
            make.centerY.equalTo(danmuButton)
            // Taller than a chip: the bar clips, and the focus ring plus the
            // 1.05 scale need somewhere to land inside it.
            make.height.equalTo(DS.Chip.height + 20)
        }

        // Last row of the transport. Down from the action row lands here and Up
        // goes back — the focus engine handles both, because the rail sits
        // directly under the row rather than off in another column.
        //
        // Fixed inside the column: the shelf no longer moves relative to the
        // rows above it, the column moves and takes the shelf with it.
        relatedRail.onSelect = { [weak self] info in self?.onSelectRelated?(info) }
        column.addSubview(relatedRail)
        relatedRail.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.sideMargin)
            make.trailing.equalToSuperview().offset(-Layout.sideMargin)
            make.bottom.equalToSuperview().offset(-Layout.railBottom)
            make.height.equalTo(Layout.railHeight)
        }
    }

    /// Top-centre, clear of both the title block and the transport, so it never
    /// has to compete with them for the same strip. Deliberately outside the
    /// `setControls` fade lists: if the row auto-hides two seconds after a
    /// press, the confirmation should still finish being read.
    private func buildToast() {
        addSubview(toast)
        toast.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(DS.Space.safeV)
        }
    }

    // MARK: Content

    /// Confirmation for an action that has no other visible result, or whose
    /// visible result (a tint) may be reverted a moment later by a failure.
    func showToast(_ text: String) {
        toast.show(text)
    }

    func configure(title: String?, owner: String?) {
        titleLabel.text = title
        ownerLabel.text = owner
        ownerLabel.isHidden = owner?.isEmpty ?? true
    }

    /// Fades the idle title block on its own, independently of the transport.
    ///
    /// The two overlap but are not the same switch: raising the transport always
    /// brings the title back, while lowering it does not always take the title
    /// away — a paused video keeps its title up. Only the container knows which
    /// case it is in, so the decision lives there and this is the actuator.
    func setTitle(visible: Bool, animated: Bool = true) {
        guard visible != isShowingTitle else { return }
        isShowingTitle = visible
        let apply = { self.applyTitleAlpha() }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState],
                           animations: apply)
        } else {
            apply()
        }
    }

    /// The shade is the title's ground, not the picture's: it is there so white
    /// 60pt type survives a bright frame. With the title gone and the transport
    /// down there is nothing left to keep legible, so it leaves too rather than
    /// dimming the bottom third of the video for no one.
    private func applyTitleAlpha() {
        titleStack.alpha = isShowingTitle ? 1 : 0
        bottomShade.alpha = (isShowingControls || !isShowingTitle) ? 0 : 1
    }

    func update(current: TimeInterval, total: TimeInterval) {
        guard total > 0 else { return }
        scrubber.update(progress: current / total)
        currentLabel.text = current.timeString()
        totalLabel.text = total.timeString()
    }

    func setPlaying(_ playing: Bool) {
        playButton.icon = UIImage(systemName: playing ? "pause.fill" : "play.fill")
    }

    /// Two distinct glyphs rather than one tinted two ways: the badge says
    /// which state you are in even when the button is focused and inverted.
    func setDanmuOn(_ on: Bool) {
        danmuButton.isOn = on
        danmuButton.icon = (on ? Icon.danmakuOn : Icon.danmakuOff).image
    }

    func setLiked(_ on: Bool) { likeButton.isOn = on }
    func setFavorited(_ on: Bool) { favButton.isOn = on }
    func setWatchLater(_ on: Bool) { laterButton.isOn = on }

    // No `select` here on purpose. Full-bleed, the chips are launchers — none of
    // them is "current", so none is filled. Only the docked panel treats them as
    // a segmented control.

    // MARK: Controls visibility

    /// Focus has to land somewhere the moment the controls appear, and nowhere
    /// while they are hidden — otherwise the engine keeps a stale focus target
    /// alive under a transparent overlay.
    var preferredControl: UIFocusEnvironment {
        #if DEBUG
            if previewPrefersRail { return relatedRail }
        #endif
        return playButton
    }

    /// Whether a focus target is one of the rail's cards. Reading a shelf of
    /// recommendations is not idling: the container suspends the auto-hide
    /// while focus is down there, instead of pulling the row out from under it
    /// five seconds in.
    func isInRail(_ item: UIFocusItem?) -> Bool {
        guard let view = item as? UIView else { return false }
        return view.isDescendant(of: relatedRail)
    }

    /// The column scrolls up when focus reaches the shelf and drops back when it
    /// leaves — the transport rows ride along, so nothing shifts relative to
    /// anything else and the move reads as scrolling one page of controls.
    ///
    /// The chrome is an ancestor of both the action row and the rail, so it is
    /// in the focus chain for every move between them and can drive this from
    /// one place rather than having the container push state in.
    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator)
    {
        super.didUpdateFocus(in: context, with: coordinator)
        setColumnRaised(isInRail(context.nextFocusedItem), coordinator: coordinator)
    }

    /// Left/Right belong to the scrubber while it is focused: they seek.
    ///
    /// The focus engine gets first refusal on every directional input — click or
    /// swipe — and the play button sits directly to the bar's left, so Left
    /// moved focus onto it and `TheaterScrubber.pressesBegan` never ran; only
    /// Right, with nothing beyond it to move to, ever reached the seek. Refusing
    /// the update hands both directions back to the bar.
    ///
    /// Asked here rather than on the scrubber itself: the chrome is the ancestor
    /// of everything the focus can move between, so it is reliably in the chain
    /// for the move being vetoed — the same reason `didUpdateFocus` above lives
    /// here. Nothing is stranded by the veto: the play button is still Up from
    /// the ±10s button beneath it, and Select on the bar toggles playback.
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        let heading = context.focusHeading
        if context.previouslyFocusedItem === scrubber,
           heading.contains(.left) || heading.contains(.right)
        {
            return false
        }
        return super.shouldUpdateFocus(in: context)
    }

    #if DEBUG
        /// Sends the first focus into the rail instead of the play button, so
        /// the raised state can be inspected in one launch. Deliberately drives
        /// the real focus path — forcing the constraint instead would prove
        /// nothing about whether the engine can reach a half-offscreen card.
        var previewPrefersRail = false
    #endif

    private func setColumnRaised(_ raised: Bool, coordinator: UIFocusAnimationCoordinator? = nil) {
        guard raised != isColumnRaised else { return }
        isColumnRaised = raised
        // A transform rather than a constraint: the column's children are all
        // positioned against the full frame, and re-solving that layout every
        // focus move to shift it 90pt would be work for nothing.
        let apply = { self.column.transform = Self.columnOffset(raised: raised) }
        if let coordinator {
            coordinator.addCoordinatedAnimations(apply)
        } else {
            UIView.animate(withDuration: 0.26, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState],
                           animations: apply)
        }
    }

    private static func columnOffset(raised: Bool) -> CGAffineTransform {
        raised ? .identity : CGAffineTransform(translationX: 0, y: Layout.columnDrop)
    }

    func setControls(_ show: Bool, animated: Bool = true) {
        let wasShowing = isShowingControls
        isShowingControls = show
        // Whatever the auto-hide did to the title, waking the transport puts it
        // back: it is the heading of the panel that just came up, and the row of
        // buttons is meaningless without knowing what they act on.
        if show { isShowingTitle = true }
        titleBottomConstraint?.update(
            offset: -(show ? Layout.titleBottomControls : Layout.titleBottomIdle))
        // Controls coming or going puts the column back down: focus lands on the
        // play button either way, so a column left raised from the last visit
        // would come back already scrolled. `apply` animates it with the rest.
        //
        // Only on the transition, though. Every action-row press re-wakes an
        // already-showing transport to restart the auto-hide, and dropping the
        // column there would pull the shelf out from under a focused card.
        if !(show && wasShowing) { isColumnRaised = false }

        let fading: [UIView] = [scrubber, currentLabel, totalLabel, playButton, chipBar, relatedRail] + actionButtons
        let apply = {
            self.scrim.alpha = show ? 0.66 : 0
            self.applyTitleAlpha()
            fading.forEach { $0.alpha = show ? 1 : 0 }
            self.column.transform = Self.columnOffset(raised: self.isColumnRaised)
            self.layoutIfNeeded()
        }
        ([scrubber, playButton, chipBar, relatedRail] as [UIView] + actionButtons)
            .forEach { $0.isUserInteractionEnabled = show }

        if animated {
            UIView.animate(withDuration: 0.26, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState],
                           animations: apply)
        } else {
            apply()
        }
    }
}

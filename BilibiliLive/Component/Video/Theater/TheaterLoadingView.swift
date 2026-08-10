//
//  TheaterLoadingView.swift
//  BilibiliLive
//
//  起播 / 缓冲指示器，照着 B 站网页播放器那个来。
//
//  The reference is two states of the same thing. Its loading panel is the
//  TV-head mark with three dots marching across its screen — a 17-frame sprite
//  (`ploading.png`, 0.94s, `steps(1)`) in which the dots fill in left to right
//  and then empty out the same way, i.e. an ellipsis typed inside the mascot.
//  Its buffering state is a spinner beside `正在缓冲...` and the current
//  download rate. This is both at once, at 10-foot size.
//
//  Two departures from the reference, both deliberate:
//
//  - The dots fade rather than step. The sprite's own frames carry two
//    brightness levels per dot, so the 18fps stepping is a sampling artefact of
//    a fade, not the intent — and stepped at 18fps on a 60Hz television reads
//    as a dropped-frame stutter rather than as charm.
//  - No black cover. The reference blacks out the whole picture while
//    buffering; on a television that turns a 300ms hiccup into a visible
//    flash-to-black. A soft radial pool under the mark buys the same legibility
//    over a bright frame without ever hiding it.
//

import CoreText
import SnapKit
import UIKit

final class TheaterLoadingView: UIView {
    enum Phase {
        /// 起播：还没有画面，这块屏是纯黑的。
        case starting
        /// 播放中断流。
        case buffering

        var text: String {
            switch self {
            case .starting: return "正在加载…"
            case .buffering: return "正在缓冲…"
            }
        }
    }

    var phase: Phase = .starting {
        didSet {
            guard phase != oldValue else { return }
            statusLabel.text = phase.text
        }
    }

    // MARK: Views

    private let mark = LoadingMarkView()
    private let statusLabel = UILabel()
    private let speedLabel = UILabel()
    private let pool = CAGradientLayer()

    /// A stall short enough to be invisible should stay invisible. Appearing
    /// and vanishing inside a third of a second reads as a glitch in the app,
    /// not as a report about the network — and the picture is already back by
    /// the time the eye has found the spinner. Startup skips the wait: there
    /// the screen is black and empty, and any delay is just an unexplained gap.
    private static let bufferingShowDelay: TimeInterval = 0.3
    private static let fade: TimeInterval = 0.2

    /// 132pt square: the reference's mark measures ~7.5% of player width, which
    /// is where this lands in the 1920-point layout tvOS reports.
    private static let markSize: CGFloat = 132

    private var showWork: DispatchWorkItem?
    private(set) var isActive = false

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // Radial, so it has no edge to notice. A rectangular plate — even a
        // blurred one, which is what the rest of the chrome uses — announces
        // itself as a panel arriving every time the line hiccups.
        pool.type = .radial
        pool.colors = [UIColor.black.withAlphaComponent(0.55).cgColor,
                       UIColor.black.withAlphaComponent(0).cgColor]
        pool.locations = [0, 1]
        pool.startPoint = CGPoint(x: 0.5, y: 0.5)
        pool.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(pool)

        addSubview(mark)
        addSubview(statusLabel)
        addSubview(speedLabel)

        statusLabel.font = DS.Font.body
        statusLabel.textColor = .white
        statusLabel.text = phase.text

        // Accent, which the ramp reserves for progress — and this is the only
        // thing on screen that is making any.
        speedLabel.font = Self.tabularFigures(DS.Font.body)
        speedLabel.textColor = DS.Color.accent

        // The picture underneath can be anything, so every mark on top of it
        // carries its own contrast rather than trusting the pool alone.
        for view in [mark, statusLabel, speedLabel] as [UIView] {
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.55
            view.layer.shadowRadius = 10
            view.layer.shadowOffset = .zero
        }

        // Fixed offsets rather than a stack: the speed line comes and goes, and
        // a stack would walk the whole group up the screen each time it did.
        mark.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.size.equalTo(Self.markSize)
            $0.centerY.equalToSuperview().offset(-47)
        }
        statusLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(mark.snp.bottom).offset(22)
        }
        speedLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(statusLabel.snp.bottom).offset(4)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The dock transition resizes this view inside an animation block, and
        // an implicitly animated gradient frame lags a step behind the picture.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = CGSize(width: bounds.width * 0.55, height: bounds.height * 0.62)
        pool.frame = CGRect(x: bounds.midX - size.width / 2,
                            y: bounds.midY - size.height / 2,
                            width: size.width, height: size.height)
        CATransaction.commit()
    }

    // MARK: State

    func setActive(_ on: Bool) {
        guard on != isActive else { return }
        isActive = on
        showWork?.cancel()
        showWork = nil

        guard on else {
            mark.setAnimating(false)
            UIView.animate(withDuration: Self.fade) { self.alpha = 0 }
            return
        }

        let reveal = { [weak self] in
            guard let self, isActive else { return }
            mark.setAnimating(true)
            UIView.animate(withDuration: Self.fade) { self.alpha = 1 }
        }
        guard phase == .buffering else { return reveal() }
        let work = DispatchWorkItem(block: reveal)
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bufferingShowDelay, execute: work)
    }

    /// nil while nothing has been measured yet — the startup requests do not go
    /// through `AVPlayer`, so the first seconds legitimately have no number.
    func setSpeed(_ bytesPerSecond: Double?) {
        speedLabel.text = bytesPerSecond.map(Self.format(bytesPerSecond:))
    }

    private static func format(bytesPerSecond: Double) -> String {
        let kb = max(0, bytesPerSecond) / 1024
        // 1024-based, matching every other speed readout in this ecosystem.
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024)
    }

    /// Tabular figures, so a rate crossing 9→10 does not shove the centred line
    /// sideways twice a second.
    private static func tabularFigures(_ font: UIFont) -> UIFont {
        let feature: [UIFontDescriptor.FeatureKey: Int] = [
            .type: kNumberSpacingType,
            .selector: kMonospacedNumbersSelector,
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

// MARK: - Mark

/// The TV-head shell with three dots marching across its screen.
private final class LoadingMarkView: UIView {
    private let dots = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private var isAnimating = false

    /// The reference's 0.94s, rounded. Held as one number because the dot
    /// phases below are fractions of it.
    private static let cycle: CFTimeInterval = 0.95

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        // The glyph is stroked in `draw`, so a resize has to re-run it rather
        // than stretch the last bitmap.
        contentMode = .redraw
        for dot in dots {
            dot.fillColor = UIColor.white.cgColor
            dot.opacity = 0
            layer.addSublayer(dot)
        }
        // A layer animation is torn off when the app backgrounds, so coming
        // back from the Home screen mid-buffer would otherwise show three
        // frozen dots.
        NotificationCenter.default.addObserver(
            self, selector: #selector(restoreAnimation),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_: CGRect) {
        BiliMark.draw(in: bounds, color: .white, eyes: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let centres = BiliMark.dotCentres(in: bounds)
        let radius = BiliMark.dotRadius(in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (dot, centre) in zip(dots, centres) {
            dot.frame = bounds
            dot.path = UIBezierPath(ovalIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                   width: radius * 2, height: radius * 2)).cgPath
        }
        CATransaction.commit()
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restoreAnimation()
    }

    func setAnimating(_ on: Bool) {
        isAnimating = on
        on ? addDotAnimations() : dots.forEach { $0.removeAllAnimations() }
    }

    @objc private func restoreAnimation() {
        guard isAnimating, window != nil else { return }
        addDotAnimations()
    }

    /// Each dot lights in turn and they clear in the same order, so the group
    /// reads as an ellipsis being typed rather than as three things blinking.
    /// The gap at the end of the cycle is the reference's own empty frame — it
    /// is what stops the loop from looking continuous.
    private func addDotAnimations() {
        for (index, dot) in dots.enumerated() {
            let lead = 0.12 * Double(index)
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.keyTimes = [0, 0.05 + lead, 0.15 + lead, 0.58 + lead, 0.68 + lead, 1]
                .map { NSNumber(value: $0) }
            animation.values = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
            animation.duration = Self.cycle
            animation.repeatCount = .infinity
            dot.add(animation, forKey: "dots")
        }
    }
}

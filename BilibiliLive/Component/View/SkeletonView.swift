//
//  SkeletonView.swift
//  BilibiliLive
//
//  A shimmering placeholder block. Per docs/UI-REWORK.md §2.3 the shimmer is
//  a 1.2s linear opacity loop between 0.06 and 0.12 — deliberately subtle,
//  because at 10 feet a strong pulse reads as flicker.
//

import UIKit

final class SkeletonView: UIView {
    private static let animationKey = "skeleton.shimmer"

    init(cornerRadius: CGFloat = 0) {
        super.init(frame: .zero)
        backgroundColor = DS.Color.textPrimary
        layer.opacity = 0.06
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Animations are removed when a layer leaves the window, so (re)start on
    /// every move — otherwise recycled cells come back frozen.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stop() : start()
    }

    private func start() {
        guard layer.animation(forKey: Self.animationKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.06
        pulse.toValue = 0.12
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(pulse, forKey: Self.animationKey)
    }

    private func stop() {
        layer.removeAnimation(forKey: Self.animationKey)
    }
}

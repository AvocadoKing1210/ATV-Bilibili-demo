//
//  VideoTheaterMetrics.swift
//  BilibiliLive
//
//  Geometry and motion for the docked-player ("theater") transition: the video
//  shrinks into the top-left, keeps playing, and a detail panel takes the right.
//
//  Every number here was measured frame-by-frame from a 1920×1080 reference
//  recording; docs/preview/player-transition.html reproduces the same numbers
//  in a browser and is the place to re-tune them. tvOS reports a 1920×1080
//  point layout on every device, so the measurements transfer 1:1 — but the
//  rects are expressed as fractions of the container anyway, so nothing breaks
//  if that ever stops holding.
//

import UIKit

enum Theater {
    enum Metrics {
        /// Docked video rect. Measured L=92 T=72 R=1218 B=705, i.e. 1126×633.
        ///
        /// 1126÷633 = 1.779 — the same 16:9 as the full-bleed rect. That is the
        /// whole trick: one uniform scale maps one rect onto the other, so the
        /// picture never letterboxes or distorts at any point in the animation.
        static let dockOrigin = CGPoint(x: 92.0 / 1920.0, y: 72.0 / 1080.0)
        static let dockSize = CGSize(width: 1126.0 / 1920.0, height: 633.0 / 1080.0)
        static let dockRadius: CGFloat = 24

        /// Content column beneath the video, inset 14pt from the video rect
        /// (measured 106 → 1202 against the video's 92 → 1218).
        static let contentLeading: CGFloat = 106
        static let contentTrailing: CGFloat = 1202

        /// Now-playing block under the picture: cover, title and owner on one
        /// line, then the progress bar with elapsed and total beneath its two
        /// ends.
        ///
        /// Sized and placed off the reference: a 120pt-tall cover row, the bar
        /// well below it, and the whole block sitting in the leftover space with
        /// a bias upward (~70 above, ~95 below) rather than tucked against
        /// either edge.
        static let miniBarTopGap: CGFloat = 70
        static let miniBarHeight: CGFloat = 210
        static let columnBottomInset: CGFloat = 40

        /// Right-hand panel. Chips measured at x=1293, y=72, height 79; the
        /// pane body starts at x=1310.
        static let panelX: CGFloat = 1293
        static let panelWidth: CGFloat = 587
        /// Was 17. The panes are flat lists now rather than inset cards, so the
        /// column can start closer to its own edge without the rows colliding
        /// with the picture.
        static let panelInset: CGFloat = 8
        static let chipY: CGFloat = 72
        /// The strip, not the chip. Derived rather than kept at the measured 79,
        /// which was a hair *under* the 80pt chip and would have clipped it —
        /// the bar clips by design so a scrolled chip cannot spill onto the
        /// picture. Same +20 of ring room the full-bleed bar leaves.
        static let chipHeight: CGFloat = DS.Chip.height + 20
        static let paneBodyY: CGFloat = 186

        /// Left column rect beneath the docked picture, in view coordinates.
        static func leftColumn(in bounds: CGRect) -> CGRect {
            let sx = bounds.width / 1920, sy = bounds.height / 1080
            let dock = dockRect(in: bounds)
            let x = contentLeading * sx
            let y = dock.maxY + miniBarTopGap * sy
            return CGRect(x: x, y: y,
                          width: (contentTrailing - contentLeading) * sx,
                          height: bounds.height - y - columnBottomInset * sy)
        }

        static func dockRect(in bounds: CGRect) -> CGRect {
            CGRect(x: (bounds.width * dockOrigin.x).rounded(),
                   y: (bounds.height * dockOrigin.y).rounded(),
                   width: (bounds.width * dockSize.width).rounded(),
                   height: (bounds.height * dockSize.height).rounded())
        }
    }

    /// The theater's curves are the app's curves — see `DS.Curve`, which was
    /// lifted out of here once the rail needed the same pair of accessors.
    typealias Curve = DS.Curve

    enum Motion {
        /// Expand (full → docked): measured 220ms, decelerating (≈easeOutQuad).
        static let expand: TimeInterval = 0.22
        static let expandCurve = Curve(p1: CGPoint(x: 0.2, y: 0), p2: CGPoint(x: 0, y: 1))

        /// Collapse (docked → full): measured 280ms, symmetric S-curve — the
        /// sampled progress hit exactly 0.50 at t=0.50, i.e. standard ease-in-out.
        static let collapse: TimeInterval = 0.28
        static let collapseCurve = Curve(p1: CGPoint(x: 0.4, y: 0), p2: CGPoint(x: 0.2, y: 1))

        /// The reference holds the video still for ~170ms after the chrome
        /// starts fading, before it begins to move. On close inspection that
        /// gap is a render stall in the app being measured — the nav bar
        /// reappears mid-gap, which is a re-layout, not a design beat — and
        /// reproducing it reads as lag on a remote. We use a short lead-in
        /// instead. Set this to 0.17 to match the recording exactly.
        static let expandLeadIn: TimeInterval = 0.04
        static let chromeFade: TimeInterval = 0.12
    }
}

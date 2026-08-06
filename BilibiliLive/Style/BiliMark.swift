//
//  BiliMark.swift
//  BilibiliLive
//
//  bilibili's TV-head mark, drawn rather than shipped as an asset. Two callers
//  need it at wildly different sizes — a 56pt lockup at the top of a screen and
//  a ~90pt badge punched into the middle of a QR code — and a stroked path
//  scales to both without the hairline artefacts a rasterised logo picks up
//  when it is blown up 4x.
//

import UIKit

enum BiliMark {
    /// The glyph is authored in a 24x24 box: body 1.2…22.8 wide, antennae
    /// reaching up to y=1.9. Everything below is a ratio of that box, so the
    /// whole mark scales from one number.
    private static let designSize: CGFloat = 24

    /// The eye line, and the two x's the eyes sit on. Named because the loading
    /// dots are laid out against the same three numbers — see `dotCentres`.
    private static let eyeY: CGFloat = 12.8
    private static let eyeX: CGFloat = 3.8

    /// The design box fitted to the largest square inside `rect`: the square's
    /// origin, plus the scale that maps a 24-unit coordinate onto it.
    private static func fit(_ rect: CGRect) -> (origin: CGPoint, k: CGFloat) {
        let side = min(rect.width, rect.height)
        return (CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2), side / designSize)
    }

    /// Draws the mark into the current context, fitted to the largest square
    /// inside `rect`.
    ///
    /// `eyes` is off for the loading state, which animates its own three dots
    /// across the same screen and would otherwise draw them over the eyes.
    static func draw(in rect: CGRect, color: UIColor, eyes drawEyes: Bool = true) {
        let (origin, k) = fit(rect)
        let ox = origin.x, oy = origin.y
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * k, y: oy + y * k)
        }

        color.setStroke()

        let shell = UIBezierPath()
        // Antennae. They stop short of the body so the round caps read as two
        // separate strokes rather than melting into the corner radius.
        shell.move(to: p(5.6, 1.9))
        shell.addLine(to: p(9.3, 5.4))
        shell.move(to: p(18.4, 1.9))
        shell.addLine(to: p(14.7, 5.4))

        // Body. Inset by half a line width so the stroke lands *on* the
        // 1.2…22.8 box rather than straddling outside it.
        let lineWidth = 2.05 * k
        let body = CGRect(x: ox + 1.2 * k, y: oy + 5.4 * k,
                          width: 21.6 * k, height: 16.4 * k)
            .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        shell.append(UIBezierPath(roundedRect: body, cornerRadius: 4.6 * k - lineWidth / 2))
        shell.lineWidth = lineWidth
        shell.lineCapStyle = .round
        shell.lineJoinStyle = .round
        shell.stroke()

        guard drawEyes else { return }

        // Eyes: two short vertical strokes, round-capped, so they read as
        // pills. Heavier than the shell — at a uniform weight they vanish
        // first as the mark shrinks.
        let eyes = UIBezierPath()
        eyes.move(to: p(12 - eyeX, eyeY - 0.7))
        eyes.addLine(to: p(12 - eyeX, eyeY + 0.7))
        eyes.move(to: p(12 + eyeX, eyeY - 0.7))
        eyes.addLine(to: p(12 + eyeX, eyeY + 0.7))
        eyes.lineWidth = 2.5 * k
        eyes.lineCapStyle = .round
        eyes.stroke()
    }

    /// Centres of the three loading dots, left to right.
    ///
    /// They sit on the eye line, and the outer two land exactly where the eyes
    /// would be — which is what keeps the loading mark reading as the same
    /// glyph rather than as a different drawing that happens to be TV-shaped.
    static func dotCentres(in rect: CGRect) -> [CGPoint] {
        let (origin, k) = fit(rect)
        return [-eyeX, 0, eyeX].map {
            CGPoint(x: origin.x + (12 + $0) * k, y: origin.y + eyeY * k)
        }
    }

    /// Matches the eyes' stroke weight, so a dot and an eye are the same width.
    static func dotRadius(in rect: CGRect) -> CGFloat {
        fit(rect).k * 1.25
    }
}

/// The full lockup — mark plus wordmark — used at the top of the account
/// switcher and the login screen.
final class BiliMarkView: UIView {
    private let markView = MarkView()
    private let wordmark = UILabel()
    private let markHeight: CGFloat

    var markColor: UIColor = .bilipink {
        didSet { markView.color = markColor }
    }

    var wordmarkColor: UIColor = .white {
        didSet { wordmark.textColor = wordmarkColor }
    }

    init(markHeight: CGFloat = 56) {
        self.markHeight = markHeight
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        markView.color = markColor
        markView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(markView)

        // Rounded, because bilibili's own wordmark is a rounded geometric face
        // and the stock system face reads as a caption beside the mark.
        let size = markHeight * 0.80
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        wordmark.font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                               size: size)
        wordmark.text = "bilibili"
        wordmark.textColor = wordmarkColor
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wordmark)

        NSLayoutConstraint.activate([
            markView.leadingAnchor.constraint(equalTo: leadingAnchor),
            markView.centerYAnchor.constraint(equalTo: centerYAnchor),
            markView.widthAnchor.constraint(equalToConstant: markHeight),
            markView.heightAnchor.constraint(equalToConstant: markHeight),

            wordmark.leadingAnchor.constraint(equalTo: markView.trailingAnchor, constant: markHeight * 0.24),
            wordmark.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The mark's optical centre sits a touch above its box centre —
            // the antennae are lighter than the body — so nudge the text up
            // with it rather than centring both on the same line.
            wordmark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: markHeight * 0.03),

            heightAnchor.constraint(equalToConstant: markHeight),
        ])
    }

    private final class MarkView: UIView {
        var color: UIColor = .bilipink { didSet { setNeedsDisplay() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ rect: CGRect) {
            BiliMark.draw(in: bounds, color: color)
        }
    }
}

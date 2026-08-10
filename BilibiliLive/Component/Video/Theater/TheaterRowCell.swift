//
//  TheaterRowCell.swift
//  BilibiliLive
//
//  The one row shape every pane in the docked panel uses.
//
//  Flat at rest — text and a hairline, no container — with the focus fill doing
//  the work a card background used to. Two things that a card got for free have
//  to be put back deliberately once the container is gone:
//
//    · The fill needs its own padding. Content sitting 8pt from the fill's edge
//      read as cramped; the text now clears it by `hInset`, which is where the
//      row's comfort actually comes from.
//    · The fill needs to stand off its neighbours. It is inset vertically from
//      the cell, so two adjacent fills can never meet and the hairline has a gap
//      of its own to sit in.
//
//  Subclasses add their content to `rowContent`, never to `contentView`, so it
//  always draws above the fill.
//

import SnapKit
import UIKit

extension Theater {
    enum Row {
        /// Text inset from the fill's edge.
        static let hInset: CGFloat = 20
        static let vInset: CGFloat = 20
        /// Fill inset from the cell, top and bottom only — full-bleed
        /// horizontally, so the row keeps the width the tighter panel bought.
        static let fillInset: CGFloat = 4
        /// Larger than `DS.Radius.railRow`: that radius was drawn for a small
        /// card, and reads as a hard corner on a fill this tall.
        static let radius: CGFloat = 18
    }
}

/// Not a `BLMotionCollectionViewCell`: selection is a change of colour, never of
/// size. The parallax-and-grow treatment the feed cards use pushes a row's
/// neighbours around and, in a narrow column, reads as the list shifting under
/// you. The fill alone carries the state.
class TheaterRowCell: UICollectionViewCell {
    private let highlight = UIView()
    private let separator = UIView()

    /// Where subclasses put their content.
    let rowContent = UIView()

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Override to trade height for density — the 设置 pane runs many more rows
    /// than the comment list and wants to show more of them at once.
    var rowInsets: UIEdgeInsets {
        UIEdgeInsets(top: Theater.Row.vInset, left: Theater.Row.hInset,
                     bottom: Theater.Row.vInset, right: Theater.Row.hInset)
    }

    /// Subclasses build their content here and call `super.setup()` first —
    /// same shape as `BLMotionCollectionViewCell`, which these cells used to
    /// subclass, so the call sites did not have to change.
    func setup() {
        highlight.layer.cornerRadius = Theater.Row.radius
        highlight.layer.cornerCurve = .continuous
        separator.backgroundColor = DS.Color.textPrimary.withAlphaComponent(0.08)

        contentView.addSubview(highlight)
        contentView.addSubview(separator)
        contentView.addSubview(rowContent)

        highlight.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(Theater.Row.fillInset)
        }
        separator.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        let insets = rowInsets
        rowContent.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(insets.left)
            make.trailing.equalToSuperview().offset(-insets.right)
            make.top.equalToSuperview().offset(insets.top)
            make.bottom.equalToSuperview().offset(-insets.bottom)
        }
        updateRowAppearance()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateRowAppearance()
    }

    /// Override to re-tint text for the inverted fill; call `super` first.
    func updateRowAppearance() {
        highlight.backgroundColor = isFocused ? DS.Color.pill : .clear
        // The hairline is the resting divider; under a fill it is noise.
        separator.isHidden = isFocused
    }

    /// Rows that are the last of their kind (a thread's root comment) can drop
    /// the divider entirely.
    func setSeparatorHidden(_ hidden: Bool) {
        separator.alpha = hidden ? 0 : 1
    }
}

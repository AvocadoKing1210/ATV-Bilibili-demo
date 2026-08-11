//
//  ChipBarView.swift
//  BilibiliLive
//
//  The section index above the shelves. Chips and shelves are 1:1 — every
//  chip has a destination and every section has a chip — which is what makes
//  it an index rather than a filter. Selecting one jumps to that section.
//
//  It sits above the collection view rather than inside it, so it stays
//  visible at every scroll position; a jump target you cannot get back to
//  is not an index.
//

import SnapKit
import UIKit

final class ChipButton: UIControl {
    /// Same chip, two grounds. Geometry never varies — height, radius, inset
    /// and type ramp are the tokens either way; only the fill and the label's
    /// idle colour do.
    enum Style {
        /// On an opaque screen background: the index bar, the docked panel.
        case surface
        /// Over the picture. An opaque fill here reads as a card pasted onto
        /// the video, so the idle chip is a translucent lift off whatever is
        /// behind it and the label stays near-white to survive a bright frame.
        case overlay
    }

    private let label = UILabel()
    private let iconView = UIImageView()
    var isOn = false { didSet { updateAppearance() } }
    var style: Style = .surface { didSet { updateAppearance() } }
    /// The index bar grows its chips on focus. The player's do not — in a
    /// transport row every control states focus by colour alone, and one chip
    /// swelling while the buttons beside it hold still reads as a glitch.
    var scalesOnFocus = true { didSet { updateAppearance() } }
    var onFocused: (() -> Void)?
    override var canBecomeFocused: Bool { true }

    /// `symbol` is an SF Symbol name, and it must be an outline one —
    /// `gearshape`, never `gearshape.fill`. The reference's chips are outline
    /// throughout, in both states: a filled glyph inverted onto the white
    /// selected fill turns into a black blob, where the outline keeps its
    /// silhouette and just swaps ink.
    ///
    /// The index bar passes none — its chips are text-only — while the player's
    /// pane chips use one, because four two-character labels are hard to tell
    /// apart at 10 feet. A hidden arranged subview is skipped by the stack, so
    /// the text-only case lays out exactly as it did before the icon existed.
    init(title: String, symbol: String? = nil) {
        super.init(frame: .zero)
        label.text = title
        label.font = DS.Font.chipLabel

        iconView.contentMode = .scaleAspectFit
        // Point size pinned to the box and the stroke left at `.regular`: SF
        // Symbols would otherwise scale the glyph off the *label's* font, and a
        // semibold label would drag the icon to a heavier stroke than the
        // reference's — which is hairline-thin next to its text.
        iconView.image = symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(
                pointSize: DS.Chip.icon, weight: .regular))
        }
        iconView.isHidden = symbol == nil
        iconView.snp.makeConstraints { $0.width.height.equalTo(DS.Chip.icon) }

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = DS.Chip.iconGap
        stack.alignment = .center
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(DS.Chip.hInset)
        }
        snp.makeConstraints { $0.height.equalTo(DS.Chip.height) }
        layer.cornerRadius = DS.Chip.height / 2
        layer.cornerCurve = .continuous
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// See RailRowButton: a bare UIControl never sends this on tvOS.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused { onFocused?() }
        coordinator.addCoordinatedAnimations { [weak self] in self?.updateAppearance() }
    }

    private func updateAppearance() {
        let idleFill: UIColor
        let idleInk: UIColor
        switch style {
        case .surface:
            idleFill = DS.Color.surfaceRaised
            idleInk = DS.Color.textPrimary
        case .overlay:
            idleFill = UIColor.white.withAlphaComponent(0.16)
            idleInk = .white
        }
        // Fill carries selection on its own, and the ink stays at full strength
        // either way. Dimming the idle label — the old `textSecondary` — read as
        // *disabled* rather than merely unselected, and stacked a second signal
        // onto a state the fill already says unambiguously.
        backgroundColor = isOn ? DS.Color.pill : idleFill
        label.textColor = isOn ? DS.Color.pillInk : idleInk
        iconView.tintColor = isOn ? DS.Color.pillInk : idleInk
        layer.borderWidth = isFocused ? 4 : 0
        // The ring is the chip's own ink on an overlay, where DS.Color.ring
        // would follow the system appearance and could come out dark on video.
        layer.borderColor = (style == .overlay ? UIColor.white : DS.Color.ring).cgColor
        transform = isFocused && scalesOnFocus
            ? CGAffineTransform(scaleX: DS.Focus.rowScale, y: DS.Focus.rowScale)
            : .identity
    }
}

final class ChipBarView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private(set) var buttons: [ChipButton] = []

    /// Fires with the index of the section to jump to.
    var onSelect: ((Int) -> Void)?
    /// Fires as focus moves across chips, for the "switch on focus" mode the
    /// old category sidebar offered (Settings.sideMenuAutoSelectChange).
    var onFocusChange: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DS.Color.bg
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        stack.axis = .horizontal
        stack.spacing = DS.Chip.gap
        stack.alignment = .center

        addSubview(scrollView)
        scrollView.addSubview(stack)
        scrollView.snp.makeConstraints { make in
            // Same lead as the cards; a focused chip scales 1.05 and would
            // otherwise overshoot into the rail.
            make.leading.equalToSuperview().offset(DS.Space.contentLead)
            make.trailing.equalToSuperview()
            // Shares the rail's first-row baseline.
            make.top.equalToSuperview().offset(DS.Space.topRow)
            make.height.equalTo(DS.Chip.height)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitles(_ titles: [String]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { index, title in
            let b = ChipButton(title: title)
            b.tag = index
            b.addTarget(self, action: #selector(tapped(_:)), for: .primaryActionTriggered)
            b.onFocused = { [weak self] in self?.onFocusChange?(index) }
            stack.addArrangedSubview(b)
            return b
        }
        setActive(0)
    }

    func setActive(_ index: Int) {
        for (i, b) in buttons.enumerated() { b.isOn = (i == index) }
    }

    @objc private func tapped(_ sender: ChipButton) {
        setActive(sender.tag)
        onSelect?(sender.tag)
    }
}

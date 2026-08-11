//
//  RailRowButton.swift
//  BilibiliLive
//
//  One row of the global left rail.
//
//  State model (verified against live YouTube TV footage in docs/preview):
//
//    collapsed  — no pill, ever. The current section is carried by stroke
//                 colour alone: white active, 60% grey idle.
//    expanded   — the focused row takes a filled pill, and everything on it
//                 (glyph included) flips to the opposite ink.
//

import Kingfisher
import SnapKit
import UIKit

final class RailRowButton: UIControl {
    /// The pill is its own view rather than the row's `backgroundColor`
    /// because it has to be *shorter* than the row while the rail is opening.
    /// The row is always laid out at full expanded width — that is what keeps
    /// the label from re-truncating on every frame — so a background painted
    /// on the row itself can only ever be revealed by the rail's clip, i.e. as
    /// a hard vertical edge wiping across a white block. Given its own width
    /// the pill carries its rounded cap along with it, and reads as extending.
    private let pillView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let avatarView = UIView()
    private let avatarLabel = UILabel()
    private let avatarImageView = UIImageView()

    private var pillWidth: Constraint?

    private let usesAvatar: Bool
    private let icon: Icon?

    /// The section this row represents is the one currently on screen.
    /// Drives both the ink and the filled/heavier glyph variant.
    var isActiveSection = false { didSet { updateAppearance() } }
    /// The rail is showing labels. Gates the pill — a collapsed rail must
    /// never grow a background.
    ///
    /// Assigned from inside the rail's animator, so the fill transition is
    /// carried by whatever animation is running rather than snapping.
    var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            updateAppearance()
        }
    }

    /// A closed rail is a single door: only the row for the page you are on
    /// answers focus, so sliding in from the content lands there rather than on
    /// whichever row happens to sit beside the card you left. The rail owns
    /// this — see `RailContainerViewController.updateRowFocusability`.
    var isFocusable = true

    override var canBecomeFocused: Bool { isFocusable }

    init(icon: Icon?, title: String, usesAvatar: Bool = false) {
        self.usesAvatar = usesAvatar
        self.icon = icon
        super.init(frame: .zero)
        setup(icon: icon, title: title)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup(icon: Icon?, title: String) {
        pillView.layer.cornerRadius = DS.Radius.railRow
        pillView.layer.cornerCurve = .continuous
        pillView.backgroundColor = DS.Color.pill
        pillView.alpha = 0

        iconView.contentMode = .scaleAspectFit
        iconView.image = icon?.image
        iconView.isHidden = usesAvatar

        avatarView.layer.cornerRadius = DS.Rail.icon / 2
        avatarView.clipsToBounds = true
        avatarView.isHidden = !usesAvatar
        avatarLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        avatarLabel.textAlignment = .center
        avatarLabel.text = String(title.prefix(1))

        titleLabel.font = DS.Font.navLabel
        titleLabel.text = title
        titleLabel.lineBreakMode = .byTruncatingTail
        // Labels are laid out at full width even when collapsed; only the
        // rail's clipping hides them, so expansion is a width animation
        // rather than a relayout.
        titleLabel.alpha = 0

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true

        addSubview(pillView)
        addSubview(iconView)
        addSubview(avatarView)
        avatarView.addSubview(avatarLabel)
        avatarView.addSubview(avatarImageView)
        addSubview(titleLabel)

        pillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            // Starts at the collapsed rail's own inner width, so the first
            // frame of an opening rail is a pill that fits the rail as it is
            // now — not one that has to be clipped to fit.
            pillWidth = make.width.equalTo(DS.Rail.collapsed - DS.Rail.inset * 2).constraint
        }
        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(DS.Rail.icon)
        }
        avatarView.snp.makeConstraints { make in
            make.edges.equalTo(iconView)
        }
        avatarLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        avatarImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(DS.Rail.inset)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-DS.Rail.inset)
        }
        snp.makeConstraints { make in
            make.height.equalTo(DS.Rail.rowHeight)
        }
    }

    func setLabelVisible(_ visible: Bool) {
        titleLabel.alpha = visible ? 1 : 0
    }

    /// How much of the rail is currently uncovered, minus its own inset on
    /// both sides. Driven by the rail while it opens and closes so the pill
    /// travels with the edge instead of being sliced by it. Takes effect on
    /// the next layout pass, which the rail runs inside its animator.
    func setPillWidth(_ width: CGFloat) {
        pillWidth?.update(offset: width)
    }

    /// Account chip: real profile name and avatar, initial as the fallback.
    func setAccount(name: String, avatar: URL?) {
        titleLabel.text = name
        avatarLabel.text = String(name.prefix(1))
        guard let avatar else {
            avatarImageView.image = nil
            avatarImageView.isHidden = true
            return
        }
        avatarImageView.isHidden = false
        avatarImageView.kf.setImage(
            with: avatar,
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 88, height: 88))),
                .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                .cacheSerializer(FormatIndicatedCacheSerializer.png),
            ]
        )
    }

    /// A bare UIControl does not fire .primaryActionTriggered on tvOS — only
    /// UIButton does. Without this the rail looks alive (rows focus and take
    /// the pill) but Select does nothing, which is what made the sidebar
    /// static. Same pattern as BLButton.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in
            self?.updateAppearance()
        }
    }

    /// Every mutation here is animatable, and none of it schedules its own
    /// animation: the caller decides the clock. Focus moves within an open
    /// rail run on the focus engine's, opening and closing on the rail's.
    func updateAppearance() {
        let onPill = isFocused && isExpanded
        let ink: UIColor = onPill
            ? DS.Color.pillInk
            : (isActiveSection ? DS.Color.textPrimary : DS.Color.textSecondary)

        // Alpha, not a fill swap to `.clear`: `.clear` is transparent *black*,
        // so interpolating to it drags a grey haze across the middle of every
        // fade. The colour stays put and only the opacity moves.
        pillView.alpha = onPill ? 1 : 0
        // The current section reads as filled (or heavier, where Tabler has
        // no fill); everything else stays the plain outline.
        iconView.image = isActiveSection ? icon?.activeImage : icon?.image
        iconView.tintColor = ink
        titleLabel.textColor = ink
        avatarLabel.textColor = onPill ? DS.Color.pill : ink
        avatarView.backgroundColor = onPill ? DS.Color.pillInk : DS.Color.surfaceRaised
        transform = onPill
            ? CGAffineTransform(scaleX: DS.Focus.rowScale, y: DS.Focus.rowScale)
            : .identity
    }
}

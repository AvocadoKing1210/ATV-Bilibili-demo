//
//  HomeCardCell.swift
//  BilibiliLive
//
//  The one card, used by every shelf on the index page.
//
//    ┌──────────────────────────┐
//    │ 16:9 thumbnail, r=16     │ ← LIVE badge top-left, duration pill bottom-right
//    │ ▂▂▂▂▂░░░░ progress       │ ← 6pt accent bar, only when partially watched
//    ├──────────────────────────┤
//    │ Title, up to 2 lines     │
//    │ ◯ UP名 · 3.2万 · 3天前    │
//    └──────────────────────────┘
//
//  On focus the thumbnail lifts and takes a ring; the text stays put. View
//  and danmaku counts live on the meta line, not on the thumbnail.
//

import Kingfisher
import SnapKit
import UIKit

/// A label that pads its own text, so a chip's width can come from a real
/// inset rather than from spaces baked into the string.
private final class InsetLabel: UILabel {
    var textInsets: UIEdgeInsets = .zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + textInsets.left + textInsets.right,
                      height: size.height + textInsets.top + textInsets.bottom)
    }
}

final class HomeCardCell: UICollectionViewCell {
    static let reuseID = "HomeCardCell"

    private let thumbContainer = UIView()
    private let imageView = UIImageView()
    private let liveBadge = UILabel()
    private let durationPill = InsetLabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let titleLabel = UILabel()
    private let avatarView = UIImageView()
    private let metaLabel = UILabel()

    /// Play and danmaku counts. Revealed on focus only — at rest the card
    /// shows just the duration, which is the one number you need to decide
    /// whether to start something.
    private let statsPill = UIStackView()

    private var progressWidth: Constraint?

    /// Long-press context menu, used by the feed screens.
    var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        thumbContainer.layer.cornerRadius = DS.Radius.card
        thumbContainer.layer.cornerCurve = .continuous
        thumbContainer.clipsToBounds = true
        thumbContainer.backgroundColor = DS.Color.surface

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        liveBadge.font = DS.Font.badge
        liveBadge.textColor = .white
        liveBadge.backgroundColor = DS.Color.accent
        liveBadge.textAlignment = .center
        liveBadge.text = " LIVE "
        liveBadge.layer.cornerRadius = 17
        liveBadge.layer.cornerCurve = .continuous
        liveBadge.clipsToBounds = true
        liveBadge.isHidden = true

        durationPill.font = DS.Font.overlay
        durationPill.textColor = .white
        durationPill.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        durationPill.textAlignment = .center
        durationPill.textInsets = .init(top: 0, left: DS.CardChip.hInset,
                                        bottom: 0, right: DS.CardChip.hInset)
        durationPill.layer.cornerRadius = DS.CardChip.radius
        durationPill.layer.cornerCurve = .continuous
        durationPill.clipsToBounds = true
        durationPill.isHidden = true

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        progressFill.backgroundColor = DS.Color.accent
        progressTrack.isHidden = true

        titleLabel.font = DS.Font.cardTitle
        titleLabel.textColor = DS.Color.textPrimary
        titleLabel.numberOfLines = 2
        // Truncate, never shrink — shrink-to-fit is unreadable at 10 feet.
        titleLabel.lineBreakMode = .byTruncatingTail

        avatarView.layer.cornerRadius = 16
        avatarView.clipsToBounds = true
        avatarView.backgroundColor = DS.Color.surfaceRaised

        metaLabel.font = DS.Font.meta
        metaLabel.textColor = DS.Color.textSecondary
        metaLabel.numberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail

        statsPill.axis = .horizontal
        statsPill.spacing = DS.CardChip.groupGap
        statsPill.alignment = .center
        statsPill.isLayoutMarginsRelativeArrangement = true
        // Vertical margins are gone on purpose: the chip's height is now fixed
        // to match the duration beside it, and `.center` places the row in it.
        statsPill.directionalLayoutMargins = .init(top: 0, leading: DS.CardChip.hInset,
                                                   bottom: 0, trailing: DS.CardChip.hInset)
        statsPill.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statsPill.layer.cornerRadius = DS.CardChip.radius
        statsPill.layer.cornerCurve = .continuous
        statsPill.alpha = 0

        contentView.addSubview(thumbContainer)
        thumbContainer.addSubview(imageView)
        thumbContainer.addSubview(liveBadge)
        thumbContainer.addSubview(statsPill)
        thumbContainer.addSubview(durationPill)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)
        thumbContainer.addSubview(progressTrack)
        progressTrack.addSubview(progressFill)
        contentView.addSubview(titleLabel)
        contentView.addSubview(avatarView)
        contentView.addSubview(metaLabel)

        thumbContainer.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(thumbContainer.snp.width).multipliedBy(9.0 / 16.0)
        }
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        liveBadge.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(12)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(88)
        }
        // The two chips are one row: same height, same bottom edge. The
        // minimum width the duration used to carry is gone with the spaces it
        // was padded with — `hInset` gives it a real box now.
        durationPill.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(DS.CardChip.inset)
            make.height.equalTo(DS.CardChip.height)
        }
        statsPill.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(DS.CardChip.inset)
            make.height.equalTo(DS.CardChip.height)
            make.trailing.lessThanOrEqualTo(durationPill.snp.leading).offset(-DS.Space.xs)
        }
        progressTrack.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(6)
        }
        progressFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            progressWidth = make.width.equalTo(0).constraint
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(thumbContainer.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview()
        }
        avatarView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.size.equalTo(32)
        }
        metaLabel.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(12)
            make.centerY.equalTo(avatarView)
            make.trailing.lessThanOrEqualToSuperview()
        }
        // Lets the card self-size under an .estimated height, which is how the
        // feed screens lay out; the index page pins an absolute height and
        // this constraint simply goes slack.
        avatarView.snp.makeConstraints { make in
            make.bottom.lessThanOrEqualToSuperview()
        }
    }

    @objc private func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        onLongPress?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        avatarView.kf.cancelDownloadTask()
        avatarView.image = nil
        liveBadge.isHidden = true
        durationPill.isHidden = true
        progressTrack.isHidden = true
        statsPill.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statsPill.alpha = 0
    }

    /// SF Symbol names carried by the existing DisplayOverlay model, mapped to
    /// the Tabler set the rest of the UI uses.
    private func icon(forOverlaySymbol symbol: String) -> Icon? {
        switch symbol {
        case "play.rectangle": return .play
        case "list.bullet.rectangle": return .danmaku
        default: return nil
        }
    }

    private func buildStats(from overlay: DisplayOverlay) {
        for item in overlay.leftItems {
            guard !item.text.isEmpty, item.text != "-" else { continue }
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = DS.CardChip.iconGap
            row.alignment = .center
            if let symbol = item.icon, let icon = icon(forOverlaySymbol: symbol) {
                let iv = UIImageView(image: icon.image)
                iv.tintColor = .white
                iv.contentMode = .scaleAspectFit
                iv.snp.makeConstraints { $0.size.equalTo(DS.CardChip.icon) }
                row.addArrangedSubview(iv)
            }
            let label = UILabel()
            label.text = item.text
            label.font = DS.Font.overlay
            label.textColor = .white
            row.addArrangedSubview(label)
            statsPill.addArrangedSubview(row)
        }
    }

    func configure(with data: any DisplayData) {
        titleLabel.text = data.title

        var parts: [String] = []
        if !data.ownerName.isEmpty { parts.append(data.ownerName) }
        if let date = data.date, !date.isEmpty { parts.append(date) }
        metaLabel.text = parts.joined(separator: " · ")
        avatarView.isHidden = data.avatar == nil

        if let pic = data.pic {
            imageView.kf.setImage(
                with: pic,
                options: [
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 640, height: 360))),
                    .cacheOriginalImage,
                    .transition(.fade(0.2)),
                ]
            )
        }
        if let avatar = data.avatar {
            avatarView.kf.setImage(
                with: avatar,
                options: [
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 64, height: 64))),
                    .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                    .cacheSerializer(FormatIndicatedCacheSerializer.png),
                ]
            )
        }

        // The overlay model already carries duration and badges; reuse it
        // rather than re-deriving per shelf.
        if let overlay = data.overlay {
            if let badge = overlay.badge {
                liveBadge.isHidden = false
                liveBadge.text = " \(badge.text) "
                liveBadge.backgroundColor = badge.color ?? DS.Color.accent
            }
            if let duration = overlay.rightItems.first(where: { $0.icon == nil })?.text,
               !duration.isEmpty, duration != "-"
            {
                durationPill.isHidden = false
                durationPill.text = duration
            }
            buildStats(from: overlay)
        }
    }

    /// 0...1, or nil to hide. Only meaningful for partially watched items.
    func setProgress(_ fraction: Double?) {
        guard let fraction, fraction > 0.01, fraction < 0.995 else {
            progressTrack.isHidden = true
            return
        }
        progressTrack.isHidden = false
        layoutIfNeeded()
        progressWidth?.update(offset: thumbContainer.bounds.width * fraction)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self else { return }
            // Thumbnail only — the text stays where it is.
            self.thumbContainer.transform = focused
                ? CGAffineTransform(scaleX: DS.Focus.cardScale, y: DS.Focus.cardScale)
                : .identity
            // Counts are a "tell me more" detail, so they arrive with focus.
            self.statsPill.alpha = focused ? 1 : 0
            self.thumbContainer.layer.borderWidth = focused ? 5 : 0
            self.thumbContainer.layer.borderColor = DS.Color.ring.cgColor
            self.layer.shadowOpacity = focused ? DS.Focus.shadowOpacity : 0
            self.layer.shadowOffset = DS.Focus.shadowOffset
            self.layer.shadowRadius = DS.Focus.shadowRadius
            self.layer.shadowColor = UIColor.black.cgColor
        }
    }
}

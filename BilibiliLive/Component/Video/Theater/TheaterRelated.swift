//
//  TheaterRelated.swift
//  BilibiliLive
//
//  相关推荐 inside the player, in the two places it can be reached without
//  leaving playback:
//
//    · `TheaterRelatedRail` — a horizontal rail in the full-bleed transport,
//      under the button row. It comes and goes with the controls, so the
//      picture is never permanently cropped by it.
//    · `TheaterRelatedRowCell` — the same data as a vertical list, appended
//      under the description in the 简介 pane.
//
//  Neither grows on focus. Selection is a ring and a change of ink; nothing
//  moves, because a rail that pushes its neighbours around is hard to aim at
//  from a couch.
//

import Kingfisher
import SnapKit
import UIKit

// Section titles come from `TheaterSectionHeader` in TheaterSettingsPane —
// every list in the player uses the same one.

/// Duration chip drawn over the bottom-right of a thumbnail.
private func makeDurationLabel() -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    label.textColor = .white
    label.backgroundColor = UIColor.black.withAlphaComponent(0.62)
    label.textAlignment = .center
    label.layer.cornerRadius = 6
    label.layer.cornerCurve = .continuous
    label.clipsToBounds = true
    return label
}

// MARK: - Rail

/// Horizontal 相关推荐 strip for the full-bleed transport.
///
/// A plain horizontally-scrolling `UICollectionViewFlowLayout` rather than a
/// compositional orthogonal section: the section's internal scroll view brings
/// its own clipping and inset behaviour, and this strip needs to sit exactly
/// inside the transport's margins.
final class TheaterRelatedRail: UIView {
    var items: [VideoDetail.Info] = [] {
        didSet {
            isHidden = items.isEmpty
            collectionView.reloadData()
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    var onSelect: ((VideoDetail.Info) -> Void)?

    private let titleLabel = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = DS.Space.m
        layout.minimumInteritemSpacing = DS.Space.m
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        // Nothing overflows: the cards do not scale on focus, so the strip can
        // clip to its own bounds and never reach into what is beside it.
        cv.clipsToBounds = true
        cv.remembersLastFocusedIndexPath = true
        cv.register(TheaterRelatedCardCell.self, forCellWithReuseIdentifier: TheaterRelatedCardCell.identifier)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private let cardWidth: CGFloat = 240

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        titleLabel.text = "相关推荐"
        titleLabel.font = DS.Font.badge
        // Fixed white rather than a DS colour: this rail only ever draws over
        // video, under the transport's scrim.
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        addSubview(titleLabel)
        addSubview(collectionView)

        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }
        collectionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The cell is full-height and derives its thumbnail from that, so the
        // item size has to follow the strip rather than be asserted.
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        let size = CGSize(width: cardWidth, height: height)
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
    }
}

extension TheaterRelatedRail: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { items.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterRelatedCardCell.identifier,
                                          for: indexPath) as! TheaterRelatedCardCell
        cell.configure(items[indexPath.item])
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
    }
}

// MARK: - Cells

/// 16:9 thumbnail with the title underneath. The thumbnail carries the focus
/// ring; nothing scales.
final class TheaterRelatedCardCell: UICollectionViewCell {
    static let identifier = String(describing: TheaterRelatedCardCell.self)

    private let imageView = UIImageView()
    private let durationLabel = makeDurationLabel()
    private let titleLabel = UILabel()

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        imageView.layer.cornerRadius = DS.Radius.card
        imageView.layer.cornerCurve = .continuous

        titleLabel.font = DS.Font.meta
        titleLabel.numberOfLines = 1

        contentView.addSubview(imageView)
        contentView.addSubview(durationLabel)
        contentView.addSubview(titleLabel)

        imageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(imageView.snp.width).multipliedBy(9.0 / 16.0)
        }
        durationLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(imageView).inset(8)
            make.height.equalTo(28)
            make.width.greaterThanOrEqualTo(58)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(8)
        }
        updateFocusAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ info: VideoDetail.Info) {
        titleLabel.text = info.title
        durationLabel.text = "  " + TimeInterval(info.duration).timeString() + "  "
        durationLabel.isHidden = info.duration <= 0
        imageView.kf.setImage(
            with: info.pic,
            options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 480, height: 270))),
                      .cacheOriginalImage])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in self?.updateFocusAppearance() }
    }

    private func updateFocusAppearance() {
        imageView.layer.borderWidth = isFocused ? 4 : 0
        imageView.layer.borderColor = UIColor.white.cgColor
        titleLabel.textColor = isFocused ? .white : UIColor.white.withAlphaComponent(0.65)
    }
}

/// The list form of the same item, for the 简介 pane.
final class TheaterRelatedRowCell: TheaterRowCell {
    static let identifier = String(describing: TheaterRelatedRowCell.self)

    private let imageView = UIImageView()
    private let durationLabel = makeDurationLabel()
    private let titleLabel = UILabel()
    private let ownerLabel = UILabel()

    override func setup() {
        super.setup()

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = DS.Color.surface
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous

        titleLabel.font = DS.Font.meta
        titleLabel.numberOfLines = 2
        ownerLabel.font = DS.Font.badge

        let text = UIStackView(arrangedSubviews: [titleLabel, ownerLabel])
        text.axis = .vertical
        text.spacing = 6
        text.alignment = .leading

        rowContent.addSubview(imageView)
        rowContent.addSubview(durationLabel)
        rowContent.addSubview(text)

        imageView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
            make.width.equalTo(180)
            make.height.equalTo(imageView.snp.width).multipliedBy(9.0 / 16.0)
        }
        durationLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(imageView).inset(6)
            make.height.equalTo(26)
            make.width.greaterThanOrEqualTo(54)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(imageView.snp.trailing).offset(DS.Space.s)
            make.trailing.top.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        updateRowAppearance()
    }

    func configure(_ info: VideoDetail.Info) {
        titleLabel.text = info.title
        ownerLabel.text = info.owner.name
        durationLabel.text = "  " + TimeInterval(info.duration).timeString() + "  "
        durationLabel.isHidden = info.duration <= 0
        imageView.kf.setImage(
            with: info.pic,
            options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 203))),
                      .cacheOriginalImage])
        updateRowAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
    }

    override func updateRowAppearance() {
        super.updateRowAppearance()
        titleLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
        ownerLabel.textColor = isFocused
            ? DS.Color.pillInk.withAlphaComponent(0.7)
            : DS.Color.textTertiary
    }
}

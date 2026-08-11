//
//  SkeletonCardCell.swift
//  BilibiliLive
//
//  Card-shaped placeholder: a 16:9 thumb block plus two text bars, laid out
//  on exactly the metrics HomeCardCell uses so nothing shifts when the real
//  content lands.
//
//  It stays focusable on purpose. A non-focusable placeholder would push
//  first-launch focus out to the rail, and then focus would still be sitting
//  there once the shelves arrived; keeping it focusable means focus starts in
//  the content and `remembersLastFocusedIndexPath` carries it across the swap.
//

import SnapKit
import UIKit

final class SkeletonCardCell: UICollectionViewCell {
    static let reuseID = "SkeletonCardCell"

    private let thumb = SkeletonView(cornerRadius: DS.Radius.card)
    private let titleBar = SkeletonView(cornerRadius: 6)
    private let metaBar = SkeletonView(cornerRadius: 6)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(thumb)
        contentView.addSubview(titleBar)
        contentView.addSubview(metaBar)

        thumb.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(thumb.snp.width).multipliedBy(9.0 / 16.0)
        }
        titleBar.snp.makeConstraints { make in
            make.top.equalTo(thumb.snp.bottom).offset(24)
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview().multipliedBy(0.92)
            make.height.equalTo(26)
        }
        metaBar.snp.makeConstraints { make in
            make.top.equalTo(titleBar.snp.bottom).offset(16)
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview().multipliedBy(0.55)
            make.height.equalTo(22)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self else { return }
            thumb.transform = focused
                ? CGAffineTransform(scaleX: DS.Focus.cardScale, y: DS.Focus.cardScale)
                : .identity
        }
    }
}

/// Placeholder for a shelf title while the shelf is still loading.
final class SkeletonHeaderView: UICollectionReusableView {
    static let reuseID = "SkeletonHeaderView"

    private let bar = SkeletonView(cornerRadius: 6)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bar)
        bar.snp.makeConstraints { make in
            // No extra lead: the section's contentInsets already apply to
            // boundary supplementary items, so adding it again double-indents
            // the header relative to its own cards.
            make.leading.equalToSuperview()
            make.bottom.equalToSuperview().offset(-DS.Space.s)
            make.width.equalTo(220)
            make.height.equalTo(34)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

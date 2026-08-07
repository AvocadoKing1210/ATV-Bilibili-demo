//
//  FeedStateView.swift
//  BilibiliLive
//
//  In-canvas empty and error states for feeds, per docs/UI-REWORK.md §3.3.
//
//  Errors used to surface as a UIAlertController, which on a 10-foot display
//  means a modal you must dismiss before you can even see which screen failed.
//  These sit in the content area instead, name what happened, and offer 重试
//  where retrying is meaningful.
//

import SnapKit
import UIKit

final class FeedStateView: UIView {
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let retryButton = FeedStateRetryButton(title: "重试")
    private var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = DS.Color.textTertiary

        messageLabel.font = DS.Font.body
        messageLabel.textColor = DS.Color.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [iconView, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = DS.Space.m
        addSubview(stack)

        iconView.snp.makeConstraints { $0.size.equalTo(72) }
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.6)
        }
        retryButton.addTarget(self, action: #selector(retryTapped), for: .primaryActionTriggered)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon: Icon, message: String, retry: (() -> Void)?) {
        iconView.image = icon.image
        messageLabel.text = message
        onRetry = retry
        retryButton.isHidden = (retry == nil)
    }

    override var canBecomeFocused: Bool { false }

    @objc private func retryTapped() { onRetry?() }
}

final class FeedStateRetryButton: UIControl {
    private let label = UILabel()
    override var canBecomeFocused: Bool { true }

    init(title: String) {
        super.init(frame: .zero)
        label.text = title
        label.font = DS.Font.chipLabel
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(DS.Chip.hInset)
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(DS.Chip.height) }
        layer.cornerRadius = DS.Chip.height / 2
        layer.cornerCurve = .continuous
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// See RailRowButton — a bare UIControl never sends this on tvOS.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in self?.updateAppearance() }
    }

    private func updateAppearance() {
        backgroundColor = isFocused ? DS.Color.pill : DS.Color.surfaceRaised
        label.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
        transform = isFocused
            ? CGAffineTransform(scaleX: DS.Focus.rowScale, y: DS.Focus.rowScale)
            : .identity
    }
}

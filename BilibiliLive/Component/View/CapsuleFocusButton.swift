//
//  CapsuleFocusButton.swift
//  BilibiliLive
//
//  A plain capsule that inverts on focus — DS's `pill` over `pillInk`, the
//  same state signal the rail rows use. `BLButton` is the wrong base here: its
//  blur panel and parallax tilt are built for a square card in a grid, and on
//  a lone button under a QR code they read as a stray tile.
//

import UIKit

final class CapsuleFocusButton: UIButton {
    private let label = UILabel()
    private let background = UIView()

    var onPrimaryAction: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        setup(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String) {
        background.isUserInteractionEnabled = false
        background.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        background.layer.cornerCurve = .continuous
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        label.text = title
        label.font = DS.Font.body
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        addTarget(self, action: #selector(primaryAction), for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.layer.cornerRadius = bounds.height / 2
    }

    @objc private func primaryAction() {
        onPrimaryAction?()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            // Fixed poles rather than `DS.Color.pill` / `.pillInk`: those
            // invert with the system appearance, and this button only ever
            // sits on the account screens' dark backdrop.
            self.background.backgroundColor = focused
                ? .white
                : UIColor.white.withAlphaComponent(0.14)
            self.label.textColor = focused ? UIColor(rgb: 0x0C_0C_0C) : .white
            self.transform = focused
                ? CGAffineTransform(scaleX: 1.06, y: 1.06)
                : .identity
        }
    }
}

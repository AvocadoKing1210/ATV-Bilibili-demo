//
//  QRLoginPanel.swift
//  BilibiliLive
//
//  The scan-to-sign-in step, shared by the first-launch login screen and the
//  account switcher's "add account". Both want the same picture and the same
//  four-second poll; only what happens on success differs.
//

import UIKit

// MARK: - Session

/// Owns one QR code and the poll that watches it. Kept apart from the view so
/// the switcher can keep polling while the panel is mid-transition.
final class QRLoginSession {
    /// A fresh code has been issued.
    var onCode: ((String) -> Void)?
    /// The code went stale and a replacement is on its way.
    var onExpire: (() -> Void)?
    /// Scanned, confirmed, and stored. The account is already active.
    var onSuccess: ((AccountManager.Account) -> Void)?

    private var timer: Timer?
    private var authCode = ""
    private var polls = 0
    /// 200 polls at 4s is a little over 13 minutes of standing at the screen.
    private let maxPolls = 200

    deinit {
        timer?.invalidate()
    }

    func start() {
        stop()
        polls = 0
        requestCode()
    }

    /// User-driven refresh. Resets the poll budget — they are clearly still
    /// there.
    func regenerate() {
        start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func requestCode() {
        ApiRequest.requestLoginQR { [weak self] code, url in
            guard let self else { return }
            self.authCode = code
            self.onCode?(url)
            self.startPolling()
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.polls += 1
            if self.polls > self.maxPolls {
                self.stop()
                return
            }
            self.poll()
        }
    }

    private func poll() {
        ApiRequest.verifyLoginQR(code: authCode) { [weak self] state in
            guard let self else { return }
            switch state {
            case .expire:
                self.onExpire?()
                self.requestCode()
            case .waiting, .fail:
                break
            case let .success(token, cookies):
                self.stop()
                AccountManager.shared.registerAccount(token: token, cookies: cookies) { [weak self] account in
                    self?.onSuccess?(account)
                }
            }
        }
    }
}

// MARK: - Panel

/// Heading, code, hints, refresh — one centred column. The old login screen
/// split the screen down the middle and left the right half empty; a single
/// column has no empty half to fill.
final class QRLoginPanelView: UIView {
    static let codeSize: CGFloat = 520

    let regenerateButton = CapsuleFocusButton(title: "重新生成二维码")

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let codeContainer = UIView()
    private let codeView = UIImageView()
    private let placeholder = UIActivityIndicatorView(style: .large)
    private let hintLabel = UILabel()
    private let stack = UIStackView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        setup(title: title, subtitle: subtitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String, subtitle: String) {
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 46, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        subtitleLabel.text = subtitle
        subtitleLabel.font = DS.Font.body
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2

        // The card carries its own shadow, so it lifts off the backdrop the
        // way a physical card would rather than sitting flat on the wash.
        codeContainer.layer.shadowColor = UIColor.black.cgColor
        codeContainer.layer.shadowOpacity = 0.4
        codeContainer.layer.shadowRadius = 40
        codeContainer.layer.shadowOffset = CGSize(width: 0, height: 18)
        codeContainer.translatesAutoresizingMaskIntoConstraints = false

        codeView.contentMode = .scaleAspectFit
        codeView.alpha = 0
        codeView.translatesAutoresizingMaskIntoConstraints = false
        codeContainer.addSubview(codeView)

        placeholder.color = UIColor.white.withAlphaComponent(0.5)
        placeholder.startAnimating()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        codeContainer.addSubview(placeholder)

        hintLabel.font = DS.Font.meta
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        hintLabel.textAlignment = .center
        hintLabel.text = " "

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(14, after: titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(44, after: subtitleLabel)
        stack.addArrangedSubview(codeContainer)
        stack.setCustomSpacing(28, after: codeContainer)
        stack.addArrangedSubview(hintLabel)
        stack.setCustomSpacing(32, after: hintLabel)
        stack.addArrangedSubview(regenerateButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            codeContainer.widthAnchor.constraint(equalToConstant: Self.codeSize),
            codeContainer.heightAnchor.constraint(equalToConstant: Self.codeSize),
            codeView.leadingAnchor.constraint(equalTo: codeContainer.leadingAnchor),
            codeView.trailingAnchor.constraint(equalTo: codeContainer.trailingAnchor),
            codeView.topAnchor.constraint(equalTo: codeContainer.topAnchor),
            codeView.bottomAnchor.constraint(equalTo: codeContainer.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: codeContainer.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: codeContainer.centerYAnchor),
        ])
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [regenerateButton]
    }

    // MARK: - State

    /// A regenerated code replacing an expired one is a *change*, not an
    /// arrival: it flips in place rather than fading up from nothing, so the
    /// eye is told something happened.
    func setCode(_ url: String) {
        let image = StyledQRCode.image(for: url, size: Self.codeSize * 2)
        let replacing = codeView.image != nil
        placeholder.stopAnimating()

        if replacing {
            UIView.transition(with: codeView, duration: 0.32,
                              options: [.transitionFlipFromRight, .allowUserInteraction])
            {
                self.codeView.image = image
            }
        } else {
            codeView.image = image
            codeView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0, options: [.allowUserInteraction])
            {
                self.codeView.alpha = 1
                self.codeView.transform = .identity
            }
        }
        setHint(nil)
    }

    func setHint(_ text: String?) {
        // Blank rather than removed: an empty string keeps the row's height,
        // so the button below does not hop up and down as hints come and go.
        let next = text ?? " "
        guard hintLabel.text != next else { return }
        UIView.transition(with: hintLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.hintLabel.text = next
        }
    }
}

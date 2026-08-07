//
//  BrandBackdropView.swift
//  BilibiliLive
//
//  Full-bleed background for the account screens: the signed-in avatar blown
//  up and blurred past recognition, under a brand wash and a vignette. It is
//  the same trick the YouTube TV profile picker uses — the picture is there to
//  give the screen a colour that belongs to *this* user, not to be looked at.
//
//  With no avatar to work from (first launch, before any account exists) the
//  wash alone carries the screen.
//

import Kingfisher
import UIKit

final class BrandBackdropView: UIView {
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let washLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = UIColor(rgb: 0x14_10_18)
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        // Magenta out of the top-left into indigo at the bottom-right. Sits
        // *over* the blur so it tints the avatar rather than being washed out
        // by it, and stays put when there is no avatar at all.
        washLayer.colors = [
            UIColor(rgb: 0xFF_3D_7F, alpha: 0.40).cgColor,
            UIColor(rgb: 0x4A_1A_52, alpha: 0.58).cgColor,
            UIColor(rgb: 0x0E_0C_1A, alpha: 0.82).cgColor,
        ]
        washLayer.locations = [0, 0.48, 1]
        washLayer.startPoint = CGPoint(x: 0.08, y: 0)
        washLayer.endPoint = CGPoint(x: 0.92, y: 1)
        layer.addSublayer(washLayer)

        // Pulls the corners down so avatars and white type in the middle keep
        // their contrast wherever the wash happens to be light.
        vignetteLayer.type = .radial
        vignetteLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.26).cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
        ]
        vignetteLayer.locations = [0, 0.55, 1]
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1.25, y: 1.35)
        layer.addSublayer(vignetteLayer)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Gradient layers do not participate in Auto Layout, and animating
        // their frame implicitly would lag a rotation or a bounds change by a
        // quarter second.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        washLayer.frame = bounds
        vignetteLayer.frame = bounds
        CATransaction.commit()
    }

    /// Swaps the source picture. Fades rather than cuts, so switching the
    /// highlighted account can drive it live.
    func setSource(url: URL?) {
        guard let url else {
            UIView.animate(withDuration: 0.35) { self.imageView.alpha = 0 }
            return
        }
        imageView.kf.setImage(with: url, options: [.transition(.fade(0.35))]) { [weak self] result in
            guard let self else { return }
            let found = (try? result.get()) != nil
            UIView.animate(withDuration: 0.35) {
                self.imageView.alpha = found ? 1 : 0
            }
        }
    }
}

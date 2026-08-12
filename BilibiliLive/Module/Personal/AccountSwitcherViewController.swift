//
//  AccountSwitcherViewController.swift
//  BilibiliLive
//
//  Full-bleed account picker, modelled on YouTube TV's: brand mark at the top,
//  one row of round avatars across the middle, a circular "+" at the end of
//  that row, over a backdrop built from the signed-in avatar.
//
//  It used to be a 1100x720 blurred card holding a two-section vertical grid,
//  which put "add account" alone on a second row with the rest of the row
//  empty beside it. One row removes that hole; adding an account no longer
//  tears down the root view controller to show a QR code either — the code is
//  a second step inside this screen, and the two cross-fade.
//

import Kingfisher
import UIKit

final class AccountSwitcherViewController: UIViewController {
    private enum Step {
        case chooser
        case add
        case success
    }

    // MARK: - Chrome

    private let backdrop = BrandBackdropView()
    private let markView = BiliMarkView(markHeight: 52)

    // MARK: - Steps

    private let chooserView = UIView()
    private let addView = UIView()
    private let successView = UIView()

    private let tileScrollView = UIScrollView()
    private let tileStack = UIStackView()
    private let closeButton = CapsuleFocusButton(title: "关闭")

    private lazy var qrPanel = QRLoginPanelView(title: "添加账号",
                                                subtitle: "用手机上的哔哩哔哩客户端扫描二维码，即可把账号添加到这台 Apple TV")
    private let session = QRLoginSession()

    private let successAvatar = UIImageView()
    private let successLabel = UILabel()

    // MARK: - State

    private var accounts: [AccountManager.Account] = []
    private var tiles: [AccountTileView] = []
    private var addTile = AccountTileView(kind: .add)
    private var step: Step = .chooser
    private let transition = FadeScaleTransitioning()
    private var lastScrollWidth: CGFloat = -1

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        transitioningDelegate = transition
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupChrome()
        setupChooser()
        setupAdd()
        setupSuccess()
        setupSession()
        reloadAccounts()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountUpdate),
                                               name: AccountManager.didUpdateNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerTileRowIfNeeded()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        switch step {
        case .chooser:
            let active = AccountManager.shared.activeAccount?.profile.mid
            if let index = accounts.firstIndex(where: { $0.profile.mid == active }),
               index < tiles.count
            {
                return [tiles[index]]
            }
            return [tiles.first ?? addTile]
        case .add:
            return [qrPanel]
        case .success:
            return []
        }
    }

    // MARK: - Setup

    private func setupChrome() {
        view.backgroundColor = .clear

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)

        markView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(markView)

        for step in [chooserView, addView, successView] {
            step.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(step)
            NSLayoutConstraint.activate([
                step.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                step.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                step.topAnchor.constraint(equalTo: markView.bottomAnchor),
                step.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        addView.isHidden = true
        successView.isHidden = true

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            markView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            markView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    private func setupChooser() {
        tileScrollView.showsHorizontalScrollIndicator = false
        // The focus engine grows a tile 6% past its own bounds and the ring
        // sits outside the avatar; clipped, both get sliced at the row's edge.
        tileScrollView.clipsToBounds = false
        tileScrollView.translatesAutoresizingMaskIntoConstraints = false
        chooserView.addSubview(tileScrollView)

        tileStack.axis = .horizontal
        tileStack.alignment = .top
        tileStack.spacing = 48
        tileStack.translatesAutoresizingMaskIntoConstraints = false
        tileScrollView.addSubview(tileStack)

        closeButton.onPrimaryAction = { [weak self] in self?.dismissSwitcher() }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        chooserView.addSubview(closeButton)

        addTile.onSelect = { [weak self] in self?.beginAddAccount() }

        let content = tileScrollView.contentLayoutGuide
        let frame = tileScrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            tileScrollView.leadingAnchor.constraint(equalTo: chooserView.leadingAnchor),
            tileScrollView.trailingAnchor.constraint(equalTo: chooserView.trailingAnchor),
            tileScrollView.centerYAnchor.constraint(equalTo: chooserView.centerYAnchor, constant: -72),
            tileScrollView.heightAnchor.constraint(equalToConstant: AccountTileView.height),

            tileStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tileStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tileStack.topAnchor.constraint(equalTo: content.topAnchor),
            tileStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tileStack.heightAnchor.constraint(equalTo: frame.heightAnchor),

            closeButton.centerXAnchor.constraint(equalTo: chooserView.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: tileScrollView.bottomAnchor, constant: 72),
        ])
    }

    private func setupAdd() {
        qrPanel.translatesAutoresizingMaskIntoConstraints = false
        addView.addSubview(qrPanel)
        qrPanel.regenerateButton.onPrimaryAction = { [weak self] in
            self?.qrPanel.setHint("正在生成新的二维码…")
            self?.session.regenerate()
        }
        NSLayoutConstraint.activate([
            qrPanel.centerXAnchor.constraint(equalTo: addView.centerXAnchor),
            qrPanel.centerYAnchor.constraint(equalTo: addView.centerYAnchor, constant: -12),
        ])
    }

    private func setupSuccess() {
        successAvatar.contentMode = .scaleAspectFill
        successAvatar.clipsToBounds = true
        successAvatar.layer.cornerRadius = 110
        successAvatar.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        successAvatar.translatesAutoresizingMaskIntoConstraints = false
        successView.addSubview(successAvatar)

        let check = UIImageView(image: UIImage(systemName: "checkmark",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)))
        check.tintColor = .white
        check.contentMode = .center
        check.backgroundColor = .bilipink
        check.layer.cornerRadius = 34
        check.clipsToBounds = true
        check.translatesAutoresizingMaskIntoConstraints = false
        successView.addSubview(check)

        successLabel.font = UIFont.systemFont(ofSize: 42, weight: .semibold)
        successLabel.textColor = .white
        successLabel.textAlignment = .center
        successLabel.translatesAutoresizingMaskIntoConstraints = false
        successView.addSubview(successLabel)

        NSLayoutConstraint.activate([
            successAvatar.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            successAvatar.centerYAnchor.constraint(equalTo: successView.centerYAnchor, constant: -60),
            successAvatar.widthAnchor.constraint(equalToConstant: 220),
            successAvatar.heightAnchor.constraint(equalToConstant: 220),

            check.trailingAnchor.constraint(equalTo: successAvatar.trailingAnchor, constant: 8),
            check.bottomAnchor.constraint(equalTo: successAvatar.bottomAnchor, constant: 4),
            check.widthAnchor.constraint(equalToConstant: 68),
            check.heightAnchor.constraint(equalToConstant: 68),

            successLabel.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            successLabel.topAnchor.constraint(equalTo: successAvatar.bottomAnchor, constant: 44),
        ])
    }

    private func setupSession() {
        session.onCode = { [weak self] url in
            self?.qrPanel.setCode(url)
        }
        session.onExpire = { [weak self] in
            self?.qrPanel.setHint("二维码已过期，正在刷新…")
        }
        session.onSuccess = { [weak self] account in
            self?.showSuccess(for: account)
        }
    }

    // MARK: - Data

    private func reloadAccounts() {
        accounts = AccountManager.shared.accounts
        let activeMID = AccountManager.shared.activeAccount?.profile.mid

        tileStack.arrangedSubviews.forEach {
            tileStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        tiles = accounts.map { account in
            let tile = AccountTileView(kind: .account)
            tile.configure(with: account, active: account.profile.mid == activeMID)
            tile.onSelect = { [weak self] in self?.select(account) }
            tileStack.addArrangedSubview(tile)
            return tile
        }
        tileStack.addArrangedSubview(addTile)

        backdrop.setSource(url: AccountManager.shared.activeAccount
            .flatMap { URL(string: $0.profile.avatar) })
        lastScrollWidth = -1
        view.setNeedsLayout()
    }

    /// Centres the row while it fits and pads it symmetrically once it does
    /// not. A stack pinned to the content guide cannot do this on its own, and
    /// the alternative — a centring constraint against the frame guide — stops
    /// the scroll view from scrolling at all once the row overflows.
    private func centerTileRowIfNeeded() {
        tileScrollView.layoutIfNeeded()
        let available = tileScrollView.bounds.width
        guard available > 0, available != lastScrollWidth else { return }
        lastScrollWidth = available
        let inset = max(DS.Space.safeH, (available - tileStack.bounds.width) / 2)
        tileScrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        tileScrollView.contentOffset.x = -inset
    }

    @objc private func handleAccountUpdate() {
        guard step == .chooser else { return }
        reloadAccounts()
    }

    // MARK: - Actions

    private func select(_ account: AccountManager.Account) {
        let currentMID = AccountManager.shared.activeAccount?.profile.mid
        guard account.profile.mid != currentMID else {
            // Picking the account you are already on is "carry on", not a
            // no-op — YouTube TV closes on it too.
            dismissSwitcher()
            AccountManager.shared.refreshActiveAccountProfile()
            return
        }
        AccountManager.shared.setActiveAccount(account)
        dismiss(animated: true) {
            AppDelegate.shared.resetTabBar()
        }
    }

    private func beginAddAccount() {
        session.start()
        transition(to: .add)
    }

    private func showSuccess(for account: AccountManager.Account) {
        successLabel.text = "已添加 \(account.profile.username)"
        if let url = URL(string: account.profile.avatar), !account.profile.avatar.isEmpty {
            successAvatar.kf.setImage(with: url)
        }
        transition(to: .success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.dismiss(animated: true) {
                AppDelegate.shared.resetTabBar()
            }
        }
    }

    private func dismissSwitcher() {
        session.stop()
        dismiss(animated: true)
    }

    /// Menu backs out of the QR code to the row before it closes the screen —
    /// one step at a time, the way every other tvOS flow behaves.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }), step == .add {
            session.stop()
            transition(to: .chooser)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    // MARK: - Step transition

    private func container(for step: Step) -> UIView {
        switch step {
        case .chooser: return chooserView
        case .add: return addView
        case .success: return successView
        }
    }

    /// Outgoing sinks back and fades; incoming rises into place on a spring,
    /// starting before the outgoing has finished so the two overlap. A hard
    /// swap here is what made adding an account feel like a different screen
    /// rather than the next step of this one.
    private func transition(to next: Step) {
        guard next != step else { return }
        let outgoing = container(for: step)
        let incoming = container(for: next)
        step = next

        if next == .chooser {
            // Coming back from a code that was never scanned: the row is
            // rebuilt in case anything changed under it while it was hidden,
            // where `handleAccountUpdate` deliberately ignores updates.
            reloadAccounts()
        }

        incoming.isHidden = false
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 34).scaledBy(x: 1.04, y: 1.04)

        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
            outgoing.alpha = 0
            outgoing.transform = CGAffineTransform(translationX: 0, y: -26).scaledBy(x: 0.96, y: 0.96)
        } completion: { _ in
            outgoing.isHidden = true
            outgoing.transform = .identity
        }

        UIView.animate(withDuration: 0.52, delay: 0.10, usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0, options: [.allowUserInteraction])
        {
            incoming.alpha = 1
            incoming.transform = .identity
        }

        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }
}

// MARK: - Tile

/// One round avatar with its name underneath. The "+" is the same tile with a
/// glyph instead of a picture, so it lines up with the accounts on every
/// baseline instead of being a differently-shaped card at the end of the row.
private final class AccountTileView: UIControl {
    enum Kind {
        case account
        case add
    }

    static let avatar: CGFloat = 220
    /// Ring outer edge, plus the room the 1.06 focus scale needs.
    static let circle: CGFloat = 252
    static let width: CGFloat = 300
    static let height: CGFloat = 44 + 18 + circle + 26 + 38 + 4 + 30

    var onSelect: (() -> Void)?

    private let badge = UILabel()
    private let circleView = UIView()
    private let ringView = UIView()
    private let avatarView = UIImageView()
    private let plusView = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private var focusAnimator: UIViewPropertyAnimator?

    init(kind: Kind) {
        super.init(frame: .zero)
        setup(kind: kind)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(kind: Kind) {
        clipsToBounds = false
        addTarget(self, action: #selector(primaryAction), for: .primaryActionTriggered)

        // "Current user" reads above the avatar, where it cannot be confused
        // with the white ring below it — the ring means *focused*, and the two
        // states are independent.
        badge.text = "当前使用"
        badge.font = DS.Font.badge
        badge.textColor = .white
        badge.backgroundColor = .bilipink
        badge.textAlignment = .center
        badge.layer.cornerRadius = 22
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.alpha = 0
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        circleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circleView)

        // Fixed white, not `DS.Color.ring`: that token flips to near-black in
        // the Light appearance, and this screen's backdrop is dark in both.
        ringView.layer.borderColor = UIColor.white.cgColor
        ringView.layer.borderWidth = 6
        ringView.layer.cornerRadius = 122
        ringView.alpha = 0
        ringView.isUserInteractionEnabled = false
        ringView.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(ringView)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Self.avatar / 2
        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(avatarView)

        if kind == .add {
            plusView.image = UIImage(systemName: "plus",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 86, weight: .light))
            plusView.tintColor = .white
            plusView.contentMode = .center
            plusView.translatesAutoresizingMaskIntoConstraints = false
            circleView.addSubview(plusView)
            nameLabel.text = "添加账号"
        }

        nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .semibold)
        nameLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        statusLabel.font = DS.Font.meta
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: Self.height),

            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.topAnchor.constraint(equalTo: topAnchor),
            badge.heightAnchor.constraint(equalToConstant: 44),
            badge.widthAnchor.constraint(equalToConstant: 148),

            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 18),
            circleView.widthAnchor.constraint(equalToConstant: Self.circle),
            circleView.heightAnchor.constraint(equalToConstant: Self.circle),

            avatarView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Self.avatar),
            avatarView.heightAnchor.constraint(equalToConstant: Self.avatar),

            ringView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            ringView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 244),
            ringView.heightAnchor.constraint(equalToConstant: 244),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 26),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
        ])

        if kind == .add {
            NSLayoutConstraint.activate([
                plusView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
                plusView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            ])
        }
    }

    func configure(with account: AccountManager.Account, active: Bool) {
        nameLabel.text = account.profile.username
        badge.alpha = active ? 1 : 0
        statusLabel.text = active
            ? nil
            : DateFormatter.relativeTimeStringFor(timestamp: Int(account.lastActiveAt.timeIntervalSince1970))
                .map { "上次使用 \($0)" }

        if let url = URL(string: account.profile.avatar), !account.profile.avatar.isEmpty {
            avatarView.kf.setImage(with: url, options: [.transition(.fade(0.25))])
        } else {
            avatarView.image = UIImage(systemName: "person.fill",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 96, weight: .regular))
            avatarView.contentMode = .center
            avatarView.tintColor = UIColor.white.withAlphaComponent(0.7)
        }
    }

    @objc private func primaryAction() {
        onSelect?()
    }

    override var canBecomeFocused: Bool { true }

    // A bare UIControl gets focus for free on tvOS but not actions: only
    // UIButton turns a select press into `.primaryActionTriggered`. `BLButton`
    // relays it the same way.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            setPressed(true)
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            setPressed(false)
            sendActions(for: .primaryActionTriggered)
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        setPressed(false)
        super.pressesCancelled(presses, with: event)
    }

    /// Dips under the finger and springs back on release, so a select reads as
    /// a press rather than as the screen simply changing.
    private func setPressed(_ pressed: Bool) {
        focusAnimator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(duration: pressed ? 0.12 : 0.36,
                                              timingParameters: UISpringTimingParameters(dampingRatio: pressed ? 1 : 0.62))
        let scale: CGFloat = pressed ? 0.97 : (isFocused ? 1.06 : 1)
        animator.addAnimations {
            self.circleView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        animator.startAnimation()
        focusAnimator = animator
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = context.nextFocusedView === self

        // The focus engine's own coordinator runs a fixed ease; a spring that
        // can be interrupted mid-flight is what keeps a fast run along the row
        // from looking like a series of separate jumps.
        focusAnimator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(duration: 0.42,
                                              timingParameters: UISpringTimingParameters(dampingRatio: 0.74))
        animator.addAnimations {
            self.circleView.transform = focused
                ? CGAffineTransform(scaleX: 1.06, y: 1.06)
                : .identity
            self.ringView.alpha = focused ? 1 : 0
            self.nameLabel.textColor = focused ? .white : UIColor.white.withAlphaComponent(0.85)
            self.statusLabel.textColor = UIColor.white.withAlphaComponent(focused ? 0.68 : 0.45)
            self.plusView.tintColor = focused ? .white : UIColor.white.withAlphaComponent(0.8)
            self.avatarView.backgroundColor = UIColor.white.withAlphaComponent(focused ? 0.2 : 0.12)
        }
        animator.startAnimation()
        focusAnimator = animator
    }
}

// MARK: - Presentation

/// Fade-and-settle instead of the stock modal slide. The switcher covers the
/// whole screen, so a slide reads as the app itself moving.
final class FadeScaleTransitioning: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning?
    {
        Animator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        Animator(presenting: false)
    }

    private final class Animator: NSObject, UIViewControllerAnimatedTransitioning {
        private let presenting: Bool

        init(presenting: Bool) {
            self.presenting = presenting
        }

        func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
            presenting ? 0.44 : 0.3
        }

        func animateTransition(using context: UIViewControllerContextTransitioning) {
            let container = context.containerView
            if presenting {
                guard let to = context.view(forKey: .to) else {
                    context.completeTransition(false)
                    return
                }
                to.frame = container.bounds
                to.alpha = 0
                to.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                container.addSubview(to)
                UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.9,
                               initialSpringVelocity: 0, options: [])
                {
                    to.alpha = 1
                    to.transform = .identity
                } completion: { _ in
                    context.completeTransition(!context.transitionWasCancelled)
                }
            } else {
                guard let from = context.view(forKey: .from) else {
                    context.completeTransition(false)
                    return
                }
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
                    from.alpha = 0
                    from.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                } completion: { _ in
                    from.removeFromSuperview()
                    context.completeTransition(!context.transitionWasCancelled)
                }
            }
        }
    }
}

//
//  TheaterCommentsPane.swift
//  BilibiliLive
//
//  The 评论 pane of the docked player panel.
//
//  Opening a thread does NOT present anything: the pane swaps its own contents
//  for the selected comment plus its replies, in the same column, and Menu pops
//  back. A presented screen would cover the picture, which is the one thing the
//  docked player exists to avoid — and `ReplyDetailViewController` is a
//  full-width layout that cannot survive a 570pt column anyway.
//
//  Threads nest: `stack` is the breadcrumb, so a reply-to-a-reply pushes and
//  each Menu press pops exactly one level before the panel itself collapses.
//
//  Rows are flat. Nothing is drawn at rest but text and a hairline; the fill is
//  the focus state.
//

import Kingfisher
import SnapKit
import UIKit

final class TheaterCommentsPane: UIViewController {
    var replies: [Replys.Reply] = [] {
        didSet {
            guard isViewLoaded else { return }
            // An in-flight thread is stale once the root list is replaced.
            stack.removeAll()
            reload()
        }
    }

    private let emptyLabel = UILabel()

    /// Open threads, outermost first. Empty means the root comment list.
    private var stack: [Replys.Reply] = []

    private var isThread: Bool { !stack.isEmpty }

    /// Rows under the header in thread mode, or the whole list at the root.
    private var rows: [Replys.Reply] {
        isThread ? (stack.last?.replies ?? []) : replies
    }

    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(180)))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(180)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        // Tight against the column edges — the rows have no card to inset.
        section.contentInsets = .init(top: 0, leading: 4, bottom: DS.Space.l, trailing: 4)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        cv.backgroundColor = .clear
        // Clips so scrolled rows cannot ride up over the chip bar.
        cv.clipsToBounds = true
        cv.remembersLastFocusedIndexPath = true
        return cv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }
        collectionView.register(TheaterReplyCell.self, forCellWithReuseIdentifier: TheaterReplyCell.identifier)
        collectionView.register(TheaterThreadHeaderCell.self, forCellWithReuseIdentifier: TheaterThreadHeaderCell.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        emptyLabel.font = DS.Font.meta
        emptyLabel.textColor = DS.Color.textTertiary
        emptyLabel.textAlignment = .center
        view.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(DS.Space.xxl)
        }
        reload()
    }

    // MARK: Thread navigation

    private func push(_ reply: Replys.Reply) {
        stack.append(reply)
        reload()
        // Land on the header, which is also the way back out.
        collectionView.setContentOffset(.zero, animated: false)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// Pops one level. Returns false at the root so the container can treat the
    /// press as "collapse the panel" instead.
    @discardableResult
    func popThread() -> Bool {
        guard isThread else { return false }
        stack.removeLast()
        reload()
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        return true
    }

    private func reload() {
        collectionView.reloadData()
        emptyLabel.text = isThread ? "暂无回复" : "暂无评论"
        emptyLabel.isHidden = !rows.isEmpty || isThread
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionView]
    }

    #if DEBUG
        /// Preview hook — see TheaterPreviewLauncher. Opening a thread otherwise
        /// takes a remote, which CI and the simulator screenshot pass do not have.
        func previewOpenFirstThread() {
            guard let first = replies.first else { return }
            push(first)
        }
    #endif
}

extension TheaterCommentsPane: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        rows.count + (isThread ? 1 : 0)
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isThread, indexPath.item == 0 {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterThreadHeaderCell.identifier,
                                              for: indexPath) as! TheaterThreadHeaderCell
            cell.configure(stack.last!, replyCount: rows.count)
            return cell
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterReplyCell.identifier,
                                          for: indexPath) as! TheaterReplyCell
        cell.configure(rows[indexPath.item - (isThread ? 1 : 0)], nested: isThread)
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isThread, indexPath.item == 0 {
            popThread()
            return
        }
        push(rows[indexPath.item - (isThread ? 1 : 0)])
    }
}

// MARK: - Cells

final class TheaterReplyCell: TheaterRowCell {
    static let identifier = String(describing: TheaterReplyCell.self)

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let countLabel = UILabel()

    override func setup() {
        super.setup()

        avatarImageView.layer.cornerRadius = 26
        avatarImageView.clipsToBounds = true
        avatarImageView.backgroundColor = DS.Color.surfaceRaised
        avatarImageView.snp.makeConstraints { $0.size.equalTo(52) }

        nameLabel.font = DS.Font.badge
        nameLabel.textColor = DS.Color.accentBlue
        contentLabel.font = DS.Font.meta
        // Capped: the full text is one press away in the thread, and an
        // uncapped paragraph turns a list row into a screenful.
        contentLabel.numberOfLines = 4
        countLabel.font = DS.Font.badge
        countLabel.textColor = DS.Color.textTertiary

        let text = UIStackView(arrangedSubviews: [nameLabel, contentLabel, countLabel])
        text.axis = .vertical
        text.spacing = 8

        let row = UIStackView(arrangedSubviews: [avatarImageView, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DS.Space.s

        rowContent.addSubview(row)
        row.snp.makeConstraints { make in
            rowLeading = make.leading.equalToSuperview().constraint
            make.trailing.top.bottom.equalToSuperview()
        }
        updateRowAppearance()
    }

    /// Replies inside a thread step in from the comment they answer — the only
    /// thing marking the hierarchy once the rows themselves are flat.
    private var rowLeading: Constraint?

    func configure(_ reply: Replys.Reply, nested: Bool = false) {
        rowLeading?.update(offset: nested ? DS.Space.l : 0)
        avatarImageView.kf.setImage(
            with: URL(string: reply.member.avatar),
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 104, height: 104))),
                .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                .cacheSerializer(FormatIndicatedCacheSerializer.png),
            ]
        )
        nameLabel.text = reply.member.uname
        if let attr = reply.createAttributedString(displayView: contentLabel) {
            contentLabel.attributedText = attr
        } else {
            contentLabel.text = reply.content.message
        }
        let sub = reply.replies?.count ?? 0
        countLabel.text = sub > 0 ? "\(sub) 条回复" : nil
        countLabel.isHidden = sub == 0
        updateRowAppearance()
    }

    override func updateRowAppearance() {
        super.updateRowAppearance()
        // The author name is normally biliblue; on the inverted focus fill that
        // link colour fails contrast, so it collapses to the fill's own ink.
        nameLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.accentBlue
        contentLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
        countLabel.textColor = isFocused ? DS.Color.pillInk.withAlphaComponent(0.7) : DS.Color.textTertiary
    }
}

/// The opened comment, at the top of its own thread. Focusable and selectable
/// because it doubles as the way back — Menu works too, but on tvOS a visible
/// affordance is what makes a nested list navigable.
final class TheaterThreadHeaderCell: TheaterRowCell {
    static let identifier = String(describing: TheaterThreadHeaderCell.self)

    private let backLabel = UILabel()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let imageStack = UIStackView()
    private let countLabel = UILabel()

    override func setup() {
        super.setup()
        backLabel.text = "‹ 返回评论"
        backLabel.font = DS.Font.badge

        avatarImageView.layer.cornerRadius = 26
        avatarImageView.clipsToBounds = true
        avatarImageView.backgroundColor = DS.Color.surfaceRaised
        avatarImageView.snp.makeConstraints { $0.size.equalTo(52) }

        nameLabel.font = DS.Font.badge
        contentLabel.font = DS.Font.meta
        contentLabel.numberOfLines = 0
        countLabel.font = DS.Font.badge

        imageStack.axis = .vertical
        imageStack.spacing = DS.Space.xs

        let head = UIStackView(arrangedSubviews: [avatarImageView, nameLabel])
        head.axis = .horizontal
        head.alignment = .center
        head.spacing = DS.Space.s

        let stack = UIStackView(arrangedSubviews: [backLabel, head, contentLabel, imageStack, countLabel])
        stack.axis = .vertical
        stack.spacing = DS.Space.s
        stack.alignment = .fill

        rowContent.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        updateRowAppearance()
    }

    func configure(_ reply: Replys.Reply, replyCount: Int) {
        avatarImageView.kf.setImage(
            with: URL(string: reply.member.avatar),
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 104, height: 104))),
                .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                .cacheSerializer(FormatIndicatedCacheSerializer.png),
            ]
        )
        nameLabel.text = reply.member.uname
        if let attr = reply.createAttributedString(displayView: contentLabel) {
            contentLabel.attributedText = attr
        } else {
            contentLabel.text = reply.content.message
        }
        countLabel.text = replyCount > 0 ? "\(replyCount) 条回复" : "暂无回复"

        imageStack.arrangedSubviews.forEach {
            imageStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        // Pictures were the one thing only the pushed screen could show; the
        // thread header carries them now so nothing is lost by staying put.
        for picture in reply.content.pictures?.prefix(3) ?? [] {
            guard let url = URL(string: picture.img_src) else { continue }
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 10
            imageView.kf.setImage(with: url)
            imageView.snp.makeConstraints { $0.height.equalTo(240) }
            imageStack.addArrangedSubview(imageView)
        }
        imageStack.isHidden = imageStack.arrangedSubviews.isEmpty
        updateRowAppearance()
    }

    override func updateRowAppearance() {
        super.updateRowAppearance()
        backLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.accentBlue
        nameLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.textSecondary
        contentLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
        countLabel.textColor = isFocused ? DS.Color.pillInk.withAlphaComponent(0.7) : DS.Color.textTertiary
    }
}

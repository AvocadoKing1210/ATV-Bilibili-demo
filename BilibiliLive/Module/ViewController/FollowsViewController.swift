//
//  FollowsViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/4/4.
//

import Alamofire
import Kingfisher
import SwiftyJSON
import UIKit

class FollowsViewController: StandardVideoCollectionViewController<DynamicFeedData> {
    var lastOffset = ""

    /// 顶部关注 UP 主头像栏。index 0 固定为「全部」。
    private var upList = [WebRequest.FollowedUp]()
    /// nil = 全部关注动态；非 nil = 只看该 UP 主
    private var selectedMid: Int?
    private var railView: UICollectionView!

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.pageSize = 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupRail()
        setupRefreshGesture()
        Task { await loadUpList() }
    }

    override func request(page: Int) async throws -> [DynamicFeedData] {
        if page == 1 {
            lastOffset = ""
        }
        let info: WebRequest.DynamicFeedInfo
        if let mid = selectedMid {
            info = try await WebRequest.requestUpSpaceFeed(mid: mid, offset: lastOffset)
        } else {
            info = try await WebRequest.requestFollowsFeed(offset: lastOffset, page: page)
        }
        lastOffset = info.offset
        Logger.debug("request page\(page) mid:\(selectedMid ?? 0) count:\(info.videoFeeds.count) next offset:\(info.offset)")
        return info.videoFeeds
    }

    override func goDetail(with feed: DynamicFeedData) {
        let epid = feed.modules.module_dynamic.major?.pgc?.epid
        VideoPlaybackPresenter.present(aid: feed.aid, cid: feed.cid, epid: epid, title: feed.title, from: self)
    }

    // MARK: - Up rail

    private func setupRail() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: UpRailCell.itemWidth, height: 168)
        // Horizontal flow: the gap between two avatars is the *line* spacing,
        // not the interitem one — that was the old 12 that never took effect.
        // The cell already carries half a gutter on each side, exactly like a
        // card, so zero here leaves one full gutter between avatars.
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        // Rail and grid are two scroll views on one page, so both pick up the
        // same safe-area lead; matching the grid's own section inset is all
        // that is needed to put 「全部」 on the first card's left edge.
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: collectionVC.cardLeadingInset - DS.Space.gutter / 2,
            bottom: 0,
            right: DS.Space.gutter / 2
        )

        railView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        railView.register(UpRailCell.self, forCellWithReuseIdentifier: UpRailCell.reuseID)
        railView.dataSource = self
        railView.delegate = self
        railView.backgroundColor = .clear
        railView.remembersLastFocusedIndexPath = true
        view.addSubview(railView)

        // StandardVideoCollectionViewController 已把 feed 绑到四边，
        // 解开顶边，把头像栏插进去。
        let feedView = collectionVC.view!
        railView.translatesAutoresizingMaskIntoConstraints = false
        for c in view.constraints where c.firstItem === feedView && c.firstAttribute == .top {
            c.isActive = false
        }
        NSLayoutConstraint.activate([
            railView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            railView.leftAnchor.constraint(equalTo: view.leftAnchor),
            railView.rightAnchor.constraint(equalTo: view.rightAnchor),
            railView.heightAnchor.constraint(equalToConstant: 190),
            feedView.topAnchor.constraint(equalTo: railView.bottomAnchor),
        ])
    }

    private func loadUpList() async {
        if let ups = try? await WebRequest.requestFollowedUpPortal(), !ups.isEmpty {
            upList = ups
        } else if let ups = try? await WebRequest.requestFollowing(page: 1) {
            // portal 接口失败时退回关注列表（按关注时间排序，无更新标记）
            upList = ups.map { WebRequest.FollowedUp(mid: $0.mid, uname: $0.uname, face: $0.face, has_update: false) }
        }
        railView.reloadData()
    }

    // MARK: - Refresh

    private func setupRefreshGesture() {
        // 遥控器播放/暂停键 = 刷新当前列表
        let tap = UITapGestureRecognizer(target: self, action: #selector(refresh))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(tap)
    }

    @objc private func refresh() {
        reloadData()
        Task { await loadUpList() }
    }
}

// MARK: - Rail data source / delegate

extension FollowsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return upList.isEmpty ? 0 : upList.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UpRailCell.reuseID, for: indexPath) as! UpRailCell
        if indexPath.item == 0 {
            cell.configureAsAll(selected: selectedMid == nil)
        } else {
            let up = upList[indexPath.item - 1]
            cell.configure(with: up, selected: selectedMid == up.mid)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let newMid: Int? = indexPath.item == 0 ? nil : upList[indexPath.item - 1].mid
        if newMid != selectedMid {
            selectedMid = newMid
        }
        // 再次选中当前项时等同于刷新
        reloadData()
        railView.reloadData()
    }
}

// MARK: - Rail cell

private class UpRailCell: UICollectionViewCell {
    static let reuseID = "UpRailCell"

    static let avatarSize: CGFloat = 96
    /// The avatar plus half a gutter on each side, which is exactly how a card
    /// is built — so a row of avatars is spaced like a row of cards and its
    /// first item starts on the same column edge.
    static let itemWidth = avatarSize + DS.Space.gutter
    /// Names may run a little past the avatar, but not far enough to close up
    /// against the next one.
    private static let labelInset: CGFloat = 8

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let updateDot = UIView()
    private var isFilterSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        avatarView.layer.borderWidth = 4
        avatarView.layer.borderColor = UIColor.clear.cgColor
        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 24)
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        updateDot.backgroundColor = UIColor(red: 0.98, green: 0.45, blue: 0.60, alpha: 1) // B站粉
        updateDot.layer.cornerRadius = 9
        updateDot.isHidden = true
        updateDot.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(updateDot)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 10),
            nameLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: Self.labelInset),
            nameLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -Self.labelInset),
            updateDot.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: 2),
            updateDot.rightAnchor.constraint(equalTo: avatarView.rightAnchor, constant: -2),
            updateDot.widthAnchor.constraint(equalToConstant: 18),
            updateDot.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with up: WebRequest.FollowedUp, selected: Bool) {
        nameLabel.text = up.uname
        avatarView.contentMode = .scaleAspectFill
        avatarView.kf.setImage(with: up.face, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: Self.avatarSize, height: Self.avatarSize)))])
        updateDot.isHidden = !up.has_update
        isFilterSelected = selected
        applyStyle(focused: isFocused)
    }

    func configureAsAll(selected: Bool) {
        nameLabel.text = "全部"
        avatarView.kf.cancelDownloadTask()
        avatarView.image = UIImage(systemName: "person.2.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 40))
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        avatarView.contentMode = .center
        updateDot.isHidden = true
        isFilterSelected = selected
        applyStyle(focused: isFocused)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            self.applyStyle(focused: self.isFocused)
        })
    }

    private func applyStyle(focused: Bool) {
        transform = focused ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
        if focused {
            avatarView.layer.borderColor = UIColor.white.cgColor
        } else if isFilterSelected {
            avatarView.layer.borderColor = UIColor(red: 0.98, green: 0.45, blue: 0.60, alpha: 1).cgColor
        } else {
            avatarView.layer.borderColor = UIColor.clear.cgColor
        }
        nameLabel.textColor = focused || isFilterSelected ? .label : .secondaryLabel
    }
}

// MARK: - API

extension WebRequest {
    struct DynamicFeedInfo: Codable {
        let items: [DynamicFeedData]
        let offset: String
        let update_num: Int
        let update_baseline: String
        let has_more: Bool
        var videoFeeds: [DynamicFeedData] {
            return items
                .filter({ $0.aid != 0 || $0.modules.module_dynamic.major?.pgc != nil })
        }

        enum CodingKeys: String, CodingKey {
            case items, offset, update_num, update_baseline, has_more
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([DynamicFeedData].self, forKey: .items)
            // feed/space 不返回 update_num / update_baseline，全部宽松解码
            offset = (try? container.decode(String.self, forKey: .offset)) ?? ""
            if let intVal = try? container.decode(Int.self, forKey: .update_num) {
                update_num = intVal
            } else if let strVal = try? container.decode(String.self, forKey: .update_num) {
                update_num = Int(strVal) ?? 0
            } else {
                update_num = 0
            }
            update_baseline = (try? container.decode(String.self, forKey: .update_baseline)) ?? ""
            has_more = (try? container.decode(Bool.self, forKey: .has_more)) ?? false
        }
    }

    struct FollowedUp: Codable, Hashable {
        let mid: Int
        let uname: String
        let face: URL?
        let has_update: Bool

        enum CodingKeys: String, CodingKey {
            case mid, uname, face, has_update
        }

        init(mid: Int, uname: String, face: URL?, has_update: Bool) {
            self.mid = mid
            self.uname = uname
            self.face = face
            self.has_update = has_update
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mid = try container.decode(Int.self, forKey: .mid)
            uname = try container.decode(String.self, forKey: .uname)
            face = try? container.decode(URL.self, forKey: .face)
            if let boolVal = try? container.decode(Bool.self, forKey: .has_update) {
                has_update = boolVal
            } else if let intVal = try? container.decode(Int.self, forKey: .has_update) {
                has_update = intVal != 0
            } else {
                has_update = false
            }
        }
    }

    /// 最近有更新的关注 UP 主列表（对应手机端动态页顶部头像栏）
    static func requestFollowedUpPortal() async throws -> [FollowedUp] {
        struct Resp: Codable {
            let up_list: [FollowedUp]
        }
        let resp: Resp = try await request(url: "https://api.bilibili.com/x/polymer/web-dynamic/v1/portal")
        return resp.up_list
    }

    /// 单个 UP 主的动态视频流（feed/space），响应结构与 feed/all 相同
    static func requestUpSpaceFeed(mid: Int, offset: String) async throws -> DynamicFeedInfo {
        var param: [String: Any] = ["host_mid": mid, "timezone_offset": "-480"]
        if !offset.isEmpty {
            param["offset"] = offset
        }
        let res: DynamicFeedInfo = try await request(url: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space", parameters: param)
        if res.videoFeeds.isEmpty, res.has_more, !res.offset.isEmpty {
            return try await requestUpSpaceFeed(mid: mid, offset: res.offset)
        }
        return res
    }

    static func requestFollowsFeed(offset: String, page: Int) async throws -> DynamicFeedInfo {
        var param: [String: Any] = ["type": "all", "timezone_offset": "-480", "page": page]
        if let offsetNum = Int(offset) {
            param["offset"] = offsetNum
        }
        let res: DynamicFeedInfo = try await request(url: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all", parameters: param)
        if res.videoFeeds.isEmpty, res.has_more {
            return try await requestFollowsFeed(offset: res.offset, page: page)
        }
        return res
    }
}

struct DynamicFeedData: Codable, PlayableData, DisplayData {
    var aid: Int {
        if let str = modules.module_dynamic.major?.archive?.aid {
            return Int(str) ?? 0
        }
        return 0
    }

    var cid: Int { return 0 }

    var title: String {
        return modules.module_dynamic.major?.archive?.title ?? modules.module_dynamic.major?.pgc?.title ?? ""
    }

    var ownerName: String {
        return modules.module_author.name
    }

    var pic: URL? {
        return URL(string: modules.module_dynamic.major?.archive?.cover ?? "") ?? modules.module_dynamic.major?.pgc?.cover
    }

    var avatar: URL? {
        return URL(string: modules.module_author.face)
    }

    var date: String? {
        return modules.module_author.pub_time
    }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        var rightItems = [DisplayOverlay.DisplayOverlayItem]()
        if let stat = modules.module_dynamic.major?.archive?.stat {
            if let play = stat.play {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "play.rectangle", text: play == "0" ? "-" : "\(play)"))
            }
            if let danmaku = stat.danmaku {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "list.bullet.rectangle", text: danmaku == "0" ? "-" : "\(danmaku)"))
            }
        }
        if let durationText = modules.module_dynamic.major?.archive?.duration_text {
            rightItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: durationText))
        }
        return DisplayOverlay(leftItems: leftItems, rightItems: rightItems)
    }

    let type: String
    let basic: Basic
    let modules: Modules
    let id_str: String

    struct Basic: Codable, Hashable {
        let comment_id_str: String
        let comment_type: Int
    }

    struct Modules: Codable, Hashable {
        let module_author: ModuleAuthor
        let module_dynamic: ModuleDynamic

        struct ModuleAuthor: Codable, Hashable {
            let face: String
            let mid: Int
            let name: String
            let pub_time: String
        }

        struct ModuleDynamic: Codable, Hashable {
            let major: Major?

            struct Major: Codable, Hashable {
                let archive: Archive?
                let pgc: Pgc?

                struct Archive: Codable, Hashable {
                    let aid: String?
                    let cover: String?
                    let desc: String?
                    let title: String?
                    let duration_text: String?
                    let stat: Stat?

                    struct Stat: Codable, Hashable {
                        let danmaku: String?
                        let play: String?
                    }
                }

                struct Pgc: Codable, Hashable {
                    let epid: Int?
                    let title: String?
                    let cover: URL?
                    let jump_url: URL?

                    enum CodingKeys: String, CodingKey {
                        case epid, title, cover, jump_url
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .epid) {
                            epid = intVal
                        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .epid) {
                            epid = Int(strVal)
                        } else {
                            epid = nil
                        }
                        title = try container.decodeIfPresent(String.self, forKey: .title)
                        cover = try container.decodeIfPresent(URL.self, forKey: .cover)
                        jump_url = try container.decodeIfPresent(URL.self, forKey: .jump_url)
                    }
                }
            }
        }
    }
}

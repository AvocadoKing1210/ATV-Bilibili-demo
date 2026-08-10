//
//  TheaterSettingsPane.swift
//  BilibiliLive
//
//  The 设置 pane of the docked player panel.
//
//  Rows bind straight to `Settings` / `Defaults.shared`, so flipping one here
//  is the same write the main settings screen performs — 显示弹幕 in particular
//  goes through `Defaults.shared.showDanmu`, which `DanmuViewPlugin` observes
//  via Combine, so danmaku appear/disappear live behind the panel.
//
//  Rows that need per-playback plugin state (the concrete stream from
//  `BVideoQualityPlugin`, the CDN line from `LineCandidatePlugin`) deliberately
//  stay in the transport-bar menu: they are built from data those plugins hold,
//  not from a persisted key, and duplicating them here would drift.
//

import AVKit
import UIKit

// MARK: - Row model

/// Mirrors the shape `SettingsViewController` uses, so both screens describe a
/// setting the same way. `desp` is re-read on every reload rather than cached.
final class TheaterSettingRow {
    let title: String
    let note: String?
    let desp: () -> String
    /// Toggles tint their value with the accent when on.
    let isOn: (() -> Bool)?
    let action: (_ reload: @escaping () -> Void) -> Void

    init(title: String,
         note: String? = nil,
         desp: @escaping () -> String,
         isOn: (() -> Bool)? = nil,
         action: @escaping (_ reload: @escaping () -> Void) -> Void)
    {
        self.title = title
        self.note = note
        self.desp = desp
        self.isOn = isOn
        self.action = action
    }
}

struct TheaterSettingSection {
    let title: String
    let rows: [TheaterSettingRow]
}

// MARK: - Pane

final class TheaterSettingsPane: UIViewController {
    /// The live player item, used for the subtitle row. Subtitles are HLS
    /// renditions injected by `BilibiliVideoResourceLoaderDelegate`, so they are
    /// a media selection on the item — not a persisted boolean.
    weak var playerItem: AVPlayerItem?

    /// Menu elements contributed by the player plugins. With the system
    /// transport bar gone these have nowhere else to surface, so they are
    /// rendered as rows here — see `pluginRows()`.
    var playerMenuItems = [UIMenuElement]() {
        didSet {
            guard isViewLoaded else { return }
            reload()
        }
    }

    private var sections = [TheaterSettingSection]()
    private var legibleGroup: AVMediaSelectionGroup?

    /// UIAction's handler is not callable directly. Hanging it on a button and
    /// firing primaryActionTriggered is the only public way to invoke it, so we
    /// keep the buttons alive for as long as the rows that reference them.
    private var actionProxies = [UIButton]()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(96)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(96)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            // Tight against the column edges — the rows are flat now, so there
            // is no card whose corner needs clearing, only the focus scale.
            section.contentInsets = .init(top: 0, leading: 4, bottom: DS.Space.l, trailing: 4)
            if self?.sections[index].title.isEmpty == false {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(46)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        // Must clip: unclipped, scrolled rows ride up out of the pane and land
        // on top of the chip bar. The side inset above buys back the room the
        // focus scale needs.
        cv.clipsToBounds = true
        cv.remembersLastFocusedIndexPath = true
        return cv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }
        collectionView.register(TheaterSettingCell.self,
                                forCellWithReuseIdentifier: TheaterSettingCell.identifier)
        collectionView.register(TheaterSectionHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: TheaterSectionHeader.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        rebuild()
        loadSubtitleGroup()
    }

    /// `mediaSelectionGroup(forMediaCharacteristic:)` is async on modern SDKs;
    /// the row stays hidden until the group resolves.
    private func loadSubtitleGroup() {
        guard let asset = playerItem?.asset else { return }
        Task { [weak self] in
            let group = try? await asset.loadMediaSelectionGroup(for: .legible)
            await MainActor.run {
                guard let self, let group, !group.options.isEmpty else { return }
                self.legibleGroup = group
                self.rebuild()
                self.collectionView.reloadData()
            }
        }
    }

    private func reload() {
        rebuild()
        collectionView.reloadData()
    }

    // MARK: Row builders

    private func toggle(_ title: String,
                        note: String? = nil,
                        get: @escaping () -> Bool,
                        set: @escaping (Bool) -> Void,
                        extra: ((Bool) -> Void)? = nil) -> TheaterSettingRow
    {
        TheaterSettingRow(title: title, note: note,
                          desp: { get() ? "开" : "关" },
                          isOn: get)
        { reload in
            set(!get())
            extra?(get())
            reload()
        }
    }

    private func options<T>(_ title: String,
                            note: String? = nil,
                            current: @escaping () -> String,
                            values: [T],
                            titles: [String],
                            select: @escaping (T) -> Void) -> TheaterSettingRow
    {
        TheaterSettingRow(title: title, note: note, desp: current) { [weak self] reload in
            let alert = UIAlertController(title: title, message: note, preferredStyle: .actionSheet)
            for (i, name) in titles.enumerated() {
                alert.addAction(UIAlertAction(title: name, style: .default) { _ in
                    select(values[i])
                    reload()
                })
            }
            alert.addAction(UIAlertAction(title: nil, style: .cancel))
            self?.present(alert, animated: true)
        }
    }

    private func subtitleRow(_ group: AVMediaSelectionGroup) -> TheaterSettingRow {
        let options = group.options
        let titles = ["关"] + options.map { $0.displayName }
        return TheaterSettingRow(
            title: "字幕",
            note: nil,
            desp: { [weak self] in
                guard let item = self?.playerItem else { return "关" }
                guard let sel = item.currentMediaSelection.selectedMediaOption(in: group) else { return "关" }
                return sel.displayName
            })
        { [weak self] reload in
            let alert = UIAlertController(title: "字幕", message: nil, preferredStyle: .actionSheet)
            for (i, name) in titles.enumerated() {
                alert.addAction(UIAlertAction(title: name, style: .default) { _ in
                    self?.playerItem?.select(i == 0 ? nil : options[i - 1], in: group)
                    reload()
                })
            }
            alert.addAction(UIAlertAction(title: nil, style: .cancel))
            self?.present(alert, animated: true)
        }
    }

    // MARK: Plugin menus

    private func fire(_ action: UIAction) {
        let proxy = UIButton(primaryAction: action)
        actionProxies.append(proxy)
        proxy.sendActions(for: .primaryActionTriggered)
    }

    /// Flattens one level of a plugin's menu tree into rows. A `UIAction`
    /// becomes a row that fires it; a `UIMenu` becomes a row whose sheet lists
    /// its children (recursing through inline submenus, which is how
    /// DanmuViewPlugin nests 弹幕展示时长 / 弹幕屏蔽等级).
    private func pluginRows() -> [TheaterSettingRow] {
        playerMenuItems.compactMap { element in
            if let action = element as? UIAction {
                return TheaterSettingRow(
                    title: action.title,
                    desp: { action.state == .on ? "开" : "关" },
                    isOn: { action.state == .on })
                { [weak self] reload in
                    self?.fire(action)
                    reload()
                }
            }
            guard let menu = element as? UIMenu else { return nil }
            let leaves = Self.leaves(of: menu)
            guard !leaves.isEmpty else { return nil }
            return TheaterSettingRow(
                title: menu.title,
                desp: { leaves.first(where: { $0.state == .on })?.title ?? "" })
            { [weak self] reload in
                guard let self else { return }
                let alert = UIAlertController(title: menu.title, message: nil, preferredStyle: .actionSheet)
                for leaf in leaves {
                    let mark = leaf.state == .on ? " ✓" : ""
                    alert.addAction(UIAlertAction(title: leaf.title + mark, style: .default) { _ in
                        self.fire(leaf)
                        reload()
                    })
                }
                alert.addAction(UIAlertAction(title: nil, style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }

    private static func leaves(of menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { child -> [UIAction] in
            if let action = child as? UIAction { return [action] }
            if let sub = child as? UIMenu { return leaves(of: sub) }
            return []
        }
    }

    // MARK: Schema

    private func rebuild() {
        var av: [TheaterSettingRow] = []
        if let legibleGroup { av.append(subtitleRow(legibleGroup)) }
        av += [
            options("最高画质", note: "4k以上需要大会员",
                    current: { Settings.mediaQuality.desp },
                    values: MediaQualityEnum.allCases,
                    titles: MediaQualityEnum.allCases.map(\.desp)) { Settings.mediaQuality = $0 },
            toggle("Avc优先", note: "卡顿时尝试开启",
                   get: { Settings.preferAvc }, set: { Settings.preferAvc = $0 }),
            toggle("无损音频和杜比全景声",
                   get: { Settings.losslessAudio }, set: { Settings.losslessAudio = $0 }),
            toggle("匹配视频内容",
                   get: { Settings.contentMatch }, set: { Settings.contentMatch = $0 }),
            toggle("仅在HDR视频匹配视频内容",
                   get: { Settings.contentMatchOnlyInHDR }, set: { Settings.contentMatchOnlyInHDR = $0 }),
        ]

        sections = [
            TheaterSettingSection(title: "弹幕", rows: [
                // DanmuViewPlugin observes this through Combine — the danmaku
                // layer behind the panel reacts immediately.
                toggle("显示弹幕",
                       get: { Defaults.shared.showDanmu },
                       set: { Defaults.shared.showDanmu = $0 }),
                options("弹幕展示时长",
                        current: { "\(Int(Settings.danmuDuration)) 秒" },
                        values: [4.0, 6.0, 8.0], titles: ["4 秒", "6 秒", "8 秒"]) { Settings.danmuDuration = $0 },
                options("弹幕屏蔽等级",
                        current: { "\(Settings.danmuAILevel)" },
                        values: Array<Int32>(1...10), titles: (1...10).map(String.init)) { Settings.danmuAILevel = $0 },
                options("弹幕大小", note: "默认为36",
                        current: { Settings.danmuSize.title },
                        values: DanmuSize.allCases, titles: DanmuSize.allCases.map(\.title)) { Settings.danmuSize = $0 },
                options("弹幕显示区域",
                        current: { Settings.danmuArea.title },
                        values: DanmuArea.allCases, titles: DanmuArea.allCases.map(\.title)) { Settings.danmuArea = $0 },
                options("弹幕透明度",
                        current: { Settings.danmuAlpha.title },
                        values: DanmuAlpha.allCases, titles: DanmuAlpha.allCases.map(\.title)) { Settings.danmuAlpha = $0 },
                options("弹幕描边宽度",
                        current: { Settings.danmuStrokeWidth.title },
                        values: DanmuStrokeWidth.allCases, titles: DanmuStrokeWidth.allCases.map(\.title)) { Settings.danmuStrokeWidth = $0 },
                options("弹幕描边透明度",
                        current: { Settings.danmuStrokeAlpha.title },
                        values: DanmuStrokeAlpha.allCases, titles: DanmuStrokeAlpha.allCases.map(\.title)) { Settings.danmuStrokeAlpha = $0 },
                toggle("智能防档弹幕",
                       get: { Settings.danmuMask }, set: { Settings.danmuMask = $0 }),
                toggle("按需本地运算智能防档弹幕", note: "实验性",
                       get: { Settings.vnMask }, set: { Settings.vnMask = $0 }),
                toggle("用户自定义弹幕屏蔽",
                       get: { Settings.enableDanmuFilter }, set: { Settings.enableDanmuFilter = $0 }),
                toggle("移除重复弹幕",
                       get: { Settings.enableDanmuRemoveDup }, set: { Settings.enableDanmuRemoveDup = $0 }),
            ]),
            TheaterSettingSection(title: "画面与音频", rows: av),
            TheaterSettingSection(title: "播放", rows: [
                options("播放速度",
                        current: { Settings.mediaPlayerSpeed.name },
                        values: PlaySpeed.blDefaults, titles: PlaySpeed.blDefaults.map(\.name)) { Settings.mediaPlayerSpeed = $0 },
                toggle("循环播放", get: { Settings.loopPlay }, set: { Settings.loopPlay = $0 }),
                toggle("连续播放", get: { Settings.continouslyPlay }, set: { Settings.continouslyPlay = $0 }),
                toggle("从上次退出的位置继续播放",
                       get: { Settings.continuePlay }, set: { Settings.continuePlay = $0 }),
                toggle("自动跳过片头片尾", get: { Settings.autoSkip }, set: { Settings.autoSkip = $0 }),
                options("空降助手广告屏蔽",
                        current: { Settings.enableSponsorBlock.title },
                        values: SponsorBlockType.allCases,
                        titles: SponsorBlockType.allCases.map(\.title)) { Settings.enableSponsorBlock = $0 },
            ]),
        ]

        // 画质 and 画面线路 are built from live plugin state (available streams,
        // CDN candidates) rather than a persisted key, so they can only come
        // from the plugins themselves.
        let plugin = pluginRows()
        if !plugin.isEmpty {
            sections.append(TheaterSettingSection(title: "播放器", rows: plugin))
        }
    }
}

extension TheaterSettingsPane: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in _: UICollectionView) -> Int { sections.count }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: TheaterSettingCell.identifier,
                                          for: indexPath) as! TheaterSettingCell
        cell.configure(sections[indexPath.section].rows[indexPath.item])
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView
    {
        let v = cv.dequeueReusableSupplementaryView(ofKind: kind,
                                                    withReuseIdentifier: TheaterSectionHeader.identifier,
                                                    for: indexPath) as! TheaterSectionHeader
        v.label.text = sections[indexPath.section].title
        return v
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let row = sections[indexPath.section].rows[indexPath.item]
        row.action { [weak self] in
            // Re-read every visible row: one setting can change another's text.
            guard let self else { return }
            for cell in cv.visibleCells {
                guard let ip = cv.indexPath(for: cell),
                      let c = cell as? TheaterSettingCell else { continue }
                c.configure(self.sections[ip.section].rows[ip.item])
            }
        }
    }
}

// MARK: - Views

final class TheaterSettingCell: TheaterRowCell {
    static let identifier = String(describing: TheaterSettingCell.self)

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let valueLabel = UILabel()

    /// Denser than a comment row: this pane is a long list of one-line settings
    /// and the full inset would push half of them off the screen.
    override var rowInsets: UIEdgeInsets {
        UIEdgeInsets(top: 14, left: Theater.Row.hInset, bottom: 14, right: Theater.Row.hInset)
    }

    override func setup() {
        super.setup()

        titleLabel.font = DS.Font.meta
        titleLabel.numberOfLines = 2
        noteLabel.font = DS.Font.badge
        noteLabel.numberOfLines = 1
        valueLabel.font = DS.Font.meta
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [titleLabel, noteLabel])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [text, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DS.Space.s

        rowContent.addSubview(row)
        row.snp.makeConstraints { $0.edges.equalToSuperview() }
        updateRowAppearance()
    }

    func configure(_ row: TheaterSettingRow) {
        titleLabel.text = row.title
        noteLabel.text = row.note
        noteLabel.isHidden = row.note == nil
        valueLabel.text = row.desp()
        isValueOn = row.isOn?() ?? false
        updateRowAppearance()
    }

    private var isValueOn = false

    /// Focus inverts the row wholesale, so the accent has to give way — on the
    /// light `pill` fill an accent-tinted value would drop below contrast.
    override func updateRowAppearance() {
        super.updateRowAppearance()
        titleLabel.textColor = isFocused ? DS.Color.pillInk : DS.Color.textPrimary
        noteLabel.textColor = isFocused ? DS.Color.pillInk.withAlphaComponent(0.7) : DS.Color.textTertiary
        if isFocused {
            valueLabel.textColor = DS.Color.pillInk
        } else {
            valueLabel.textColor = isValueOn ? DS.Color.accent : DS.Color.textSecondary
        }
    }
}

final class TheaterSectionHeader: UICollectionReusableView {
    static let identifier = String(describing: TheaterSectionHeader.self)
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = DS.Font.badge
        label.textColor = DS.Color.textTertiary
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(DS.Space.xs)
            make.bottom.equalToSuperview().offset(-DS.Space.xs)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

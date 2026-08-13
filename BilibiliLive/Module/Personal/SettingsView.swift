//
//  SettingsView.swift
//  BilibiliLive
//
//  设置 — the app's settings screen, modelled on the settings chrome of
//  Discord's web client and built the way discord-tvos-proto builds its own:
//  SwiftUI over the measured web tokens in `Theme`, with tvOS focus standing
//  in for web hover. No native lift, halo or scale — a focused row restyles
//  itself with the same translucent overlays the web client hovers with.
//
//  The nav column carries identity (avatar + name → account switcher), the
//  settings groups under muted category labels, and 登出 alone in red past a
//  divider. The pane answers with a heading and flat rows: drawn switches
//  for toggles, value + chevron for pickers.
//

import SwiftUI

// MARK: - Focus plumbing
// Custom ButtonStyle so tvOS doesn't add its own lift/halo; focus state is
// forwarded to the label through the environment so rows can restyle
// themselves the way web rows do on hover. Ported from the prototype.

private struct RowFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var rowFocused: Bool {
        get { self[RowFocusedKey.self] }
        set { self[RowFocusedKey.self] = newValue }
    }
}

private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .environment(\.rowFocused, focused)
        }
    }
}

// MARK: - Sections

/// The settings groups, as an addressable list — the nav column lays them
/// out and the pane renders the selected one.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case display = "界面"
    case media = "音视频"
    case playback = "进度控制"
    case danmu = "弹幕"
    case areaLimit = "港澳台解锁"

    var id: String { rawValue }
    var title: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .display: return "paintpalette"
        case .media: return "waveform"
        case .playback: return "play.circle"
        case .danmu: return "text.bubble"
        case .areaLimit: return "globe.asia.australia"
        }
    }
}

/// The few doors that still lead into UIKit: modal controllers the SwiftUI
/// screen cannot present itself.
///
/// `presentModal` is one of them by choice rather than necessity. SwiftUI's own
/// `confirmationDialog` draws tvOS's system sheet, which is not this app's
/// modal; hosting `MorphingModalView` in a presented controller instead gets
/// the app's panel *and* takes the rows behind it out of the focus engine's
/// reach for free, which an in-place overlay would have to fake.
struct SettingsBridge {
    var presentAccountSwitcher: () -> Void = {}
    var presentTabCustomization: () -> Void = {}
    var presentModal: (MorphingModalRequest) -> Void = { _ in }
}

// MARK: - Screen

struct SettingsScreen: View {
    let bridge: SettingsBridge

    @State private var selected: SettingsSection = .general
    /// Settings are read straight from `Settings` statics during body
    /// evaluation; bumping this after any write is what re-evaluates them.
    @State private var revision = 0
    @FocusState private var focusedSection: SettingsSection?

    /// The nav column's shape: which groups exist is `SettingsSection`'s
    /// business, this only says how they read as a column.
    private let groups: [(title: String, sections: [SettingsSection])] = [
        ("用户设置", [.general, .display]),
        ("播放设置", [.media, .playback, .danmu]),
        ("其他", [.areaLimit]),
    ]

    var body: some View {
        let _ = revision
        HStack(spacing: 0) {
            sidebar
                .frame(width: Theme.Metrics.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.Colors.baseLowest.ignoresSafeArea())
                // Each column is a focus section: a horizontal move lands in
                // the other column's nearest row even when nothing overlaps
                // the focused row's own vertical band — the raw beam search
                // finds no target from a low sidebar row to a high pane row.
                .focusSection()
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Colors.baseLower.ignoresSafeArea())
                .focusSection()
        }
        .onChange(of: focusedSection) { section in
            guard Settings.sideMenuAutoSelectChange, let section else { return }
            selected = section
        }
        .onReceive(NotificationCenter.default.publisher(for: AccountManager.didUpdateNotification)) { _ in
            revision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            revision += 1
        }
    }

    // MARK: - Nav column

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Metrics.rowGap) {
                profileRow
                divider
                    .padding(.vertical, Theme.Metrics.dividerVPad)
                ForEach(groups, id: \.title) { group in
                    categoryLabel(group.title)
                    ForEach(group.sections) { section in
                        navRow(section)
                    }
                }
                divider
                    .padding(.vertical, Theme.Metrics.dividerVPad)
                logoutRow
            }
            .padding(.top, 24 * Theme.scale)
            .padding(.horizontal, 8 * Theme.scale)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, Theme.Metrics.rowInnerPadH)
    }

    private func categoryLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.categoryLabel)
            .foregroundStyle(Theme.Colors.channelsDefault)
            .padding(.leading, Theme.Metrics.rowInnerPadH)
            .padding(.top, Theme.Metrics.categoryTopPad)
            .padding(.bottom, Theme.Metrics.categoryBottomPad)
    }

    private var profileRow: some View {
        let profile = AccountManager.shared.activeAccount?.profile
        return Button {
            bridge.presentAccountSwitcher()
        } label: {
            ProfileRowLabel(
                name: profile?.username ?? "未登录",
                avatar: profile.flatMap { $0.avatar.isEmpty ? nil : URL(string: $0.avatar) }
            )
        }
        .buttonStyle(BareButtonStyle())
    }

    private func navRow(_ section: SettingsSection) -> some View {
        Button {
            selected = section
        } label: {
            NavRowLabel(title: section.title, symbol: section.symbol,
                        selected: selected == section, destructive: false)
        }
        .buttonStyle(BareButtonStyle())
        .focused($focusedSection, equals: section)
    }

    private var logoutRow: some View {
        Button {
            bridge.presentModal(MorphingModalRequest(
                title: "确定登出？",
                options: [.init("登出", role: .destructive) { performLogout() }]
            ))
        } label: {
            NavRowLabel(title: "登出", symbol: "rectangle.portrait.and.arrow.right",
                        selected: false, destructive: true)
        }
        .buttonStyle(BareButtonStyle())
    }

    private func performLogout() {
        WebRequest.logout {
            ApiRequest.logout { hasRemainingAccount in
                if hasRemainingAccount {
                    AccountManager.shared.refreshActiveAccountProfile()
                } else {
                    AppDelegate.shared.showLogin()
                }
            }
        }
    }

    // MARK: - Pane

    private var pane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.title)
                    .font(Theme.Fonts.paneHeading)
                    .foregroundStyle(Theme.Colors.textStrong)
                    .padding(.leading, Theme.Metrics.rowInnerPadH)
                    .padding(.bottom, Theme.Metrics.paneHeadingGap)
                paneRows
            }
            .frame(maxWidth: Theme.Metrics.paneMaxWidth, alignment: .leading)
            .padding(.top, Theme.Metrics.panePadTop)
            .padding(.horizontal, Theme.Metrics.panePadH)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var paneRows: some View {
        switch selected {
        case .general:
            toggleRow("启用投屏", isOn: Settings.enableDLNA) {
                Settings.enableDLNA = $0
                BiliBiliUpnpDMR.shared.start()
            }
            toggleRow("热门个性化推荐", isOn: Settings.requestHotWithoutCookie) {
                Settings.requestHotWithoutCookie = $0
            }

        case .display:
            navPaneRow("自定义导航栏") {
                bridge.presentTabCustomization()
            }
            pickerRow("视频每行显示个数", message: "重启app生效",
                      value: Settings.displayStyle.desp,
                      options: FeedDisplayStyle.allCases.filter { !$0.hideInSetting },
                      label: { $0.desp })
            {
                Settings.displayStyle = $0
            }
            toggleRow("焦点移动即切换菜单", isOn: Settings.sideMenuAutoSelectChange) {
                Settings.sideMenuAutoSelectChange = $0
            }

        case .media:
            pickerRow("最高画质", message: "4k以上需要大会员",
                      value: Settings.mediaQuality.desp,
                      options: MediaQualityEnum.allCases,
                      label: { $0.desp })
            {
                Settings.mediaQuality = $0
            }
            pickerRow("默认播放速度", message: "默认设置为1.0",
                      value: Settings.mediaPlayerSpeed.name,
                      options: PlaySpeed.blDefaults,
                      label: { $0.name })
            {
                Settings.mediaPlayerSpeed = $0
            }
            toggleRow("Avc优先(卡顿尝试开启)", isOn: Settings.preferAvc) {
                Settings.preferAvc = $0
            }
            toggleRow("无损音频和杜比全景声", isOn: Settings.losslessAudio) {
                Settings.losslessAudio = $0
            }
            toggleRow("匹配视频内容", isOn: Settings.contentMatch) {
                Settings.contentMatch = $0
            }
            toggleRow("仅在HDR视频匹配视频内容", isOn: Settings.contentMatchOnlyInHDR) {
                Settings.contentMatchOnlyInHDR = $0
            }

        case .playback:
            toggleRow("从上次退出的位置继续播放", isOn: Settings.continuePlay) {
                Settings.continuePlay = $0
            }
            toggleRow("自动跳过片头片尾", isOn: Settings.autoSkip) {
                Settings.autoSkip = $0
            }
            toggleRow("连续播放", isOn: Settings.continouslyPlay) {
                Settings.continouslyPlay = $0
            }
            pickerRow("空降助手广告屏蔽", message: nil,
                      value: Settings.enableSponsorBlock.title,
                      options: SponsorBlockType.allCases,
                      label: { $0.title })
            {
                Settings.enableSponsorBlock = $0
            }

        case .danmu:
            toggleRow("用户自定义弹幕屏蔽", isOn: Settings.enableDanmuFilter) { enabled in
                Settings.enableDanmuFilter = enabled
                if enabled {
                    Task { @MainActor in
                        let message = await VideoDanmuFilter.shared.update()
                        bridge.presentModal(.notice(title: "同步结果", message: message))
                    }
                }
            }
            toggleRow("移除重复弹幕", isOn: Settings.enableDanmuRemoveDup) {
                Settings.enableDanmuRemoveDup = $0
            }
            pickerRow("弹幕大小", message: "默认为36",
                      value: Settings.danmuSize.title,
                      options: DanmuSize.allCases,
                      label: { $0.title })
            {
                Settings.danmuSize = $0
            }
            pickerRow("弹幕显示区域", message: "设置弹幕显示区域",
                      value: Settings.danmuArea.title,
                      options: DanmuArea.allCases,
                      label: { $0.title })
            {
                Settings.danmuArea = $0
            }
            toggleRow("智能防档弹幕", isOn: Settings.danmuMask) {
                Settings.danmuMask = $0
            }
            toggleRow("按需本地运算智能防档弹幕(Exp)", isOn: Settings.vnMask) {
                Settings.vnMask = $0
            }
            pickerRow("弹幕透明度", message: "调整弹幕的透明度",
                      value: Settings.danmuAlpha.title,
                      options: DanmuAlpha.allCases,
                      label: { $0.title })
            {
                Settings.danmuAlpha = $0
            }
            pickerRow("弹幕描边宽度", message: "调整弹幕描边的粗细",
                      value: Settings.danmuStrokeWidth.title,
                      options: DanmuStrokeWidth.allCases,
                      label: { $0.title })
            {
                Settings.danmuStrokeWidth = $0
            }
            pickerRow("弹幕描边透明度", message: "调整弹幕描边的透明度",
                      value: Settings.danmuStrokeAlpha.title,
                      options: DanmuStrokeAlpha.allCases,
                      label: { $0.title })
            {
                Settings.danmuStrokeAlpha = $0
            }

        case .areaLimit:
            toggleRow("解锁港澳台番剧限制", isOn: Settings.areaLimitUnlock) {
                Settings.areaLimitUnlock = $0
            }
            valueRow("设置港澳台解析服务器",
                     value: Settings.areaLimitCustomServer.isEmpty ? "未设置" : Settings.areaLimitCustomServer)
            {
                bridge.presentModal(MorphingModalRequest(
                    title: "设置港澳台解析服务器",
                    message: "为了安全考虑建议自建服务器，公共服务器可用性难保证，请多尝试几个。\n公共服务器请参考：http://985.so/mjq9u",
                    field: .init(placeholder: "api.example.com",
                                 text: Settings.areaLimitCustomServer),
                    options: [.init("确定") { text in
                        Settings.areaLimitCustomServer = text
                        revision += 1
                    }]
                ))
            }
        }
    }

    // MARK: - Row builders

    private func toggleRow(_ title: String, isOn: Bool, apply: @escaping (Bool) -> Void) -> some View {
        Button {
            apply(!isOn)
            revision += 1
        } label: {
            PaneRowLabel(title: title) {
                SettingsSwitch(isOn: isOn)
            }
        }
        .buttonStyle(BareButtonStyle())
    }

    private func pickerRow<T>(_ title: String, message: String?, value: String,
                              options: [T], label: @escaping (T) -> String,
                              apply: @escaping (T) -> Void) -> some View
    {
        valueRow(title, value: value) {
            bridge.presentModal(MorphingModalRequest(
                title: title,
                message: message,
                // `value` is the row's own live reading, so the option that
                // matches it is the one the modal opens focused on.
                options: options.map { option in
                    .init(label(option), isSelected: label(option) == value) {
                        apply(option)
                        revision += 1
                    }
                }
            ))
        }
    }

    private func valueRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PaneRowLabel(title: title) {
                Text(value)
                    .font(Theme.Fonts.rowValue)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(1)
                chevron
            }
        }
        .buttonStyle(BareButtonStyle())
    }

    private func navPaneRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PaneRowLabel(title: title) {
                chevron
            }
        }
        .buttonStyle(BareButtonStyle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12 * Theme.scale, weight: .semibold))
            .foregroundStyle(Theme.Colors.textMuted)
    }
}

// MARK: - Row labels

/// A nav-column row: icon + label, restyled by selection and focus with the
/// web client's overlay fills. The destructive variant inks itself red and
/// never carries selection — 登出 is an action, not a place.
private struct NavRowLabel: View {
    let title: String
    let symbol: String
    let selected: Bool
    let destructive: Bool
    @Environment(\.rowFocused) private var focused

    var body: some View {
        let emphasized = selected || focused
        let ink: Color = destructive
            ? Theme.Colors.danger
            : emphasized ? Theme.Colors.textStrong : Theme.Colors.channelsDefault
        HStack(spacing: Theme.Metrics.rowIconGap) {
            Image(systemName: symbol)
                .font(.system(size: 15 * Theme.scale, weight: .medium))
                .frame(width: Theme.Metrics.rowIconSize, height: Theme.Metrics.rowIconSize)
                .foregroundStyle(ink)
            Text(title)
                .font(Theme.Fonts.navRow)
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metrics.rowInnerPadH)
        .frame(height: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCornerRadius)
                .fill(selected ? Theme.Colors.selectedOverlay
                    : focused ? Theme.Colors.hoverOverlay
                    : Color.clear)
        )
    }
}

/// The identity block: avatar, name, and where pressing it leads. Opens the
/// account switcher — this screen's "Edit Profiles".
private struct ProfileRowLabel: View {
    let name: String
    let avatar: URL?
    @Environment(\.rowFocused) private var focused

    var body: some View {
        HStack(spacing: 10 * Theme.scale) {
            ZStack {
                Circle().fill(Theme.Colors.blurple)
                if let avatar {
                    AsyncImage(url: avatar) { $0.resizable().scaledToFill() } placeholder: {
                        initial
                    }
                    .clipShape(Circle())
                } else {
                    initial
                }
            }
            .frame(width: Theme.Metrics.profileAvatar, height: Theme.Metrics.profileAvatar)

            VStack(alignment: .leading, spacing: 1 * Theme.scale) {
                Text(name)
                    .font(Theme.Fonts.profileName)
                    .foregroundStyle(Theme.Colors.textStrong)
                    .lineLimit(1)
                Text("切换账号")
                    .font(Theme.Fonts.profileSub)
                    .foregroundStyle(focused ? Theme.Colors.textSubtle : Theme.Colors.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metrics.rowInnerPadH)
        .frame(height: Theme.Metrics.profileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCornerRadius)
                .fill(focused ? Theme.Colors.hoverOverlay : Color.clear)
        )
    }

    private var initial: some View {
        Text(String(name.first ?? "?"))
            .font(Theme.Fonts.sans(18, .medium))
            .foregroundStyle(Theme.Colors.white)
    }
}

/// A content-pane row: title on the left, whatever states the control on the
/// right, a hairline under it, and the hover overlay when focused.
private struct PaneRowLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.rowFocused) private var focused

    var body: some View {
        HStack(spacing: 12 * Theme.scale) {
            Text(title)
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(focused ? Theme.Colors.textStrong : Theme.Colors.textDefault)
                .lineLimit(1)
            Spacer(minLength: 16 * Theme.scale)
            trailing()
        }
        .padding(.horizontal, Theme.Metrics.rowInnerPadH)
        .frame(height: Theme.Metrics.paneRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCornerRadius)
                .fill(focused ? Theme.Colors.hoverOverlay : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if !focused {
                Rectangle()
                    .fill(Theme.Colors.borderSubtle)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.Metrics.rowInnerPadH)
            }
        }
    }
}

/// The toggle, drawn after the web client's: a capsule that goes green when
/// engaged, with a white knob that slides to the engaged side. UISwitch does
/// not exist on tvOS, and "开"/"关" text made every toggle read like a picker.
private struct SettingsSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Theme.Colors.online : Theme.Colors.interactiveMuted)
            Circle()
                .fill(Theme.Colors.white)
                .frame(width: Theme.Metrics.switchKnob, height: Theme.Metrics.switchKnob)
                .padding((Theme.Metrics.switchHeight - Theme.Metrics.switchKnob) / 2)
        }
        .frame(width: Theme.Metrics.switchWidth, height: Theme.Metrics.switchHeight)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

extension FeedDisplayStyle {
    var desp: String {
        switch self {
        case .large:
            return "3个"
        case .normal:
            return "4个"
        case .sideBar:
            return "-"
        }
    }
}

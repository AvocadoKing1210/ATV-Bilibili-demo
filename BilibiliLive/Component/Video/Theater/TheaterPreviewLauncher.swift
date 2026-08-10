//
//  TheaterPreviewLauncher.swift
//  BilibiliLive
//
//  DEBUG-only shortcut into the docked-player layout.
//
//  Iterating on the theater panel otherwise means walking feed → detail →
//  play → transport bar → 详情 on a remote for every single build. This
//  presents the theater directly, already docked, so the layout can be
//  inspected (and screenshotted in CI/simulator) in one launch.
//
//      xcrun simctl launch <device> com.zeelu.BilibiliLive -TheaterPreview 1
//      # optionally pick the pane and a real video:
//      #   -TheaterPreviewPane settings|comments|info|pages
//      #   -TheaterPreviewAid <aid> -TheaterPreviewCid <cid>
//      #   -TheaterPreviewLoading 1   起播/缓冲指示器 + 假网速
//
//  With no aid the player has nothing to load and stays black — that is fine,
//  the point is the surrounding chrome. Pass a real aid/cid to see the picture
//  dock with live video.
//

#if DEBUG

    import UIKit

    enum TheaterPreviewLauncher {
        static var isEnabled: Bool {
            UserDefaults.standard.bool(forKey: "TheaterPreview")
        }

        static func present(from root: UIViewController) {
            let defaults = UserDefaults.standard
            let aid = defaults.integer(forKey: "TheaterPreviewAid")
            let cid = defaults.integer(forKey: "TheaterPreviewCid")
            let pane: TheaterPane = {
                switch defaults.string(forKey: "TheaterPreviewPane") {
                case "comments": return .comments
                case "info": return .info
                case "pages": return .pages
                default: return .settings
                }
            }()

            let theater = VideoTheaterViewController(
                playInfo: PlayInfo(aid: aid, cid: cid, title: "Theater preview"))
            theater.pages = (1...6).map {
                VideoPage(cid: $0, page: $0, epid: nil, from: "preview", part: "预览分P \($0)")
            }
            // Stand-in content so the rail, the 简介 list and the comment thread
            // all have something to lay out. Covers on a fresh simulator will
            // not load (no network / no cookies) — the placeholder fill is the
            // point, the geometry is what is being checked.
            theater.detail = sampleDetail()
            theater.replies = sampleReplies()

            // -TheaterPreviewDock 0 stops at the full-bleed state with the
            // self-drawn transport up, for checking that half of the layout.
            let shouldDock = defaults.object(forKey: "TheaterPreviewDock") == nil
                || defaults.bool(forKey: "TheaterPreviewDock")

            // -TheaterPreviewRail 1 — sends the opening focus into 相关推荐
            // rather than the play button, i.e. the state a Down press on the
            // action row produces, with the rail lifted off the edge. Set
            // before presenting so the first focus update already sees it.
            if defaults.bool(forKey: "TheaterPreviewRail") {
                theater.previewPreferRail()
            }

            root.present(theater, animated: false) {
                // One runloop turn so the player's view hierarchy settles before
                // the dock animation starts from a valid full-bleed frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    shouldDock ? theater.dock(to: pane) : theater.showControls()
                    // -TheaterPreviewThread 1 opens the first comment's thread,
                    // the one state that otherwise needs a remote to reach.
                    if defaults.bool(forKey: "TheaterPreviewThread") {
                        theater.previewOpenFirstThread()
                    }
                    // -TheaterPreviewToast 已收藏 — raises a confirmation toast,
                    // which otherwise only an action-row press can produce.
                    if let toast = defaults.string(forKey: "TheaterPreviewToast") {
                        theater.previewShowToast(toast)
                    }
                    // -TheaterPreviewLoading 1 — pins the loading indicator up
                    // with a synthetic download rate, the one state that
                    // otherwise needs a genuinely bad line to reach.
                    if defaults.bool(forKey: "TheaterPreviewLoading") {
                        theater.previewHoldLoading()
                    }
                }
            }
        }

        // MARK: Sample data

        private static func sampleDetail() -> VideoDetail {
            let owner = VideoOwner(mid: 1, name: "预览UP主", face: nil)
            let stat = VideoDetail.Info.Stat(favorite: 12043, coin: 8021, like: 90211,
                                             share: 1200, danmaku: 3021, view: 1_204_331)
            func info(_ i: Int) -> VideoDetail.Info {
                VideoDetail.Info(
                    aid: 1000 + i, cid: 2000 + i,
                    title: "推荐视频标题 \(i) —— 一个足够长的标题用来检查截断",
                    videos: 1, pic: nil, desc: nil, owner: owner, pages: nil, dynamic: nil,
                    bvid: "BV\(i)", duration: 120 * i, pubdate: nil, ugc_season: nil,
                    redirect_url: nil, stat: stat)
            }
            let view = VideoDetail.Info(
                aid: 1, cid: 2, title: "Theater preview", videos: 1, pic: nil,
                desc: String(repeating: "这是一段用于预览的视频简介文本。", count: 14),
                owner: owner, pages: nil, dynamic: nil, bvid: "BV1", duration: 3600,
                pubdate: nil, ugc_season: nil, redirect_url: nil, stat: stat)
            return VideoDetail(View: view, Related: (1...8).map(info),
                               Card: VideoDetail.Owner(following: false, follower: 88123))
        }

        private static func sampleReplies() -> [Replys.Reply] {
            func reply(_ i: Int, children: Int) -> Replys.Reply {
                Replys.Reply(
                    member: .init(uname: "预览用户 \(i)", avatar: ""),
                    content: .init(message: String(repeating: "预览评论内容 \(i)。", count: i % 4 + 1),
                                   pictures: nil, emote: nil, jump_url: nil),
                    replies: children == 0 ? nil : (1...children).map { reply(i * 10 + $0, children: 0) })
            }
            return (1...8).map { reply($0, children: $0 % 3) }
        }
    }

#endif

//
//  VideoPlaybackPresenter.swift
//  BilibiliLive
//
//  The one way into playback.
//
//  A detail screen used to sit between a feed selection and the player. It was
//  inflated from Main.storyboard, presented, made its own round of requests,
//  and only once those came back did it put a theater up on top of itself. All
//  of that was on the path between the press and the first frame — and on the
//  default (direct-enter) path the screen was never even meant to be seen; it
//  was presented invisibly, purely as a data source, behind a black curtain.
//
//  It is gone. See Archive/VideoDetailViewController.swift.
//
//  The theater now goes up on the press with nothing but the aid/cid the feed
//  cell already had, so the play-URL request is in flight during the present
//  animation instead of after it. Everything the panes need — 简介, 评论, 选集,
//  相关推荐 — is fetched behind the picture and pushed in as it lands. Nothing
//  on the playback path waits for it.
//
//  This object owns the *sequence* of theaters, not just one: choosing another
//  part or a 相关推荐 pick tears the current theater down and puts the next one
//  up in its place, which is why it outlives any single theater and keeps
//  itself alive until the last one is dismissed.
//

import UIKit

final class VideoPlaybackPresenter: NSObject {
    // MARK: Entry points

    /// A regular video. `cid` may be 0/nil — the player resolves it.
    static func present(aid: Int, cid: Int?, epid: Int? = nil, seasonId: Int? = nil,
                        title: String? = nil, from host: UIViewController)
    {
        let info = PlayInfo(aid: aid,
                            cid: cid ?? 0,
                            epid: epid ?? 0,
                            seasonId: seasonId ?? 0,
                            title: title)
        VideoPlaybackPresenter(playInfo: info, host: host).start()
    }

    /// A 番剧 season. The player resolves the episode to play.
    static func present(seasonId: Int, title: String? = nil, from host: UIViewController) {
        present(aid: 0, cid: nil, seasonId: seasonId, title: title, from: host)
    }

    /// A specific 番剧 episode.
    static func present(epid: Int, title: String? = nil, from host: UIViewController) {
        present(aid: 0, cid: nil, epid: epid, title: title, from: host)
    }

    // MARK: State

    private weak var host: UIViewController?
    private weak var theater: VideoTheaterViewController?

    private var playInfo: PlayInfo
    private var detail: VideoDetail?
    private var pages = [VideoPage]()
    private var replies = [Replys.Reply]()
    private var ugcEpisodes = [VideoDetail.Info.UgcSeason.UgcVideoInfo]()
    private var subType: Int?

    /// Handed to the player before the episode list is known and seeded once it
    /// arrives — see `VideoNextProvider.seed`.
    private var nextProvider = VideoNextProvider(seq: [])

    private var loadTask: Task<Void, Never>?
    /// Nothing else holds this object: the presenting screen has moved on and
    /// the theater only knows it through closures. It keeps itself alive until
    /// the last theater it owns is gone.
    private var keepAlive: VideoPlaybackPresenter?

    private var aid: Int { playInfo.aid }
    private var isBangumi: Bool { playInfo.isBangumi }

    private init(playInfo: PlayInfo, host: UIViewController) {
        self.playInfo = playInfo
        self.host = host
    }

    private func start() {
        keepAlive = self
        showTheater(animated: true)
        load()
    }

    private func finish() {
        loadTask?.cancel()
        loadTask = nil
        keepAlive = nil
    }

    // MARK: Theater

    private func showTheater(animated: Bool) {
        guard let host else { finish(); return }
        let theater = VideoTheaterViewController(playInfo: playInfo, nextProvider: nextProvider)
        theater.detail = detail
        theater.pages = pages
        theater.replies = replies
        theater.onSelectPage = { [weak self] page in self?.play(page: page) }
        theater.onSelectRelated = { [weak self] info in self?.play(related: info) }
        theater.onExit = { [weak self] in self?.finish() }
        self.theater = theater
        host.present(theater, animated: animated)
    }

    /// Another part of the same video: the detail we already hold still
    /// describes it, so only the player is rebuilt.
    private func play(page: VideoPage) {
        let next = PlayInfo(aid: isBangumi ? page.page : playInfo.aid,
                            cid: page.cid,
                            epid: page.epid,
                            seasonId: playInfo.seasonId,
                            subType: subType,
                            title: page.part)
        // A 番剧 episode is a different video with its own description and
        // comments; a 分P is not.
        swap(to: next, keepingDetail: !isBangumi)
    }

    /// A 相关推荐 pick — a different video entirely.
    private func play(related info: VideoDetail.Info) {
        let next = PlayInfo(aid: info.aid, cid: info.cid, title: info.title)
        swap(to: next, keepingDetail: false)
    }

    /// Tears the current theater down so the next can take its place.
    ///
    /// `onExit` is cleared first: this is a swap, not the user leaving, and
    /// letting it fire would release the presenter mid-swap.
    private func swap(to info: PlayInfo, keepingDetail keep: Bool) {
        let outgoing = theater
        outgoing?.onExit = nil
        loadTask?.cancel()

        playInfo = info
        // The provider is per-player; a stale one would offer the previous
        // video's 下一集.
        nextProvider = VideoNextProvider(seq: [])
        if !keep {
            detail = nil
            pages = []
            replies = []
            ugcEpisodes = []
            subType = nil
        }

        // Both halves unanimated: the dismissal only exists to free the
        // presentation slot, and animating either one shows the screen
        // underneath for half a second on the way through.
        outgoing?.dismiss(animated: false) { [weak self] in
            guard let self else { return }
            showTheater(animated: false)
            if keep {
                seedNextProvider()
            } else {
                load()
            }
        }
    }

    // MARK: Data

    private func load() {
        loadTask = Task { [weak self] in
            await self?.loadData()
        }
    }

    @MainActor
    private func loadData() async {
        if isBangumi {
            await loadBangumiInfo()
        }
        guard !Task.isCancelled, aid > 0 else { return }

        do {
            // Coalesced with the player's own fetch of the same aid — whichever
            // asks first opens the connection and the other joins it.
            let detail = try await VideoDataCache.detail(aid: aid)
            guard !Task.isCancelled else { return }
            apply(detail)
        } catch {
            Logger.warn("[playback] detail load failed for aid \(self.aid): \(error)")
        }

        loadReplies()
    }

    @MainActor
    private func loadBangumiInfo() async {
        do {
            let info: BangumiInfo
            if let seasonId = playInfo.seasonId, seasonId > 0 {
                info = try await VideoDataCache.bangumi(seasonID: seasonId)
            } else if let epid = playInfo.epid, epid > 0 {
                info = try await VideoDataCache.bangumi(epid: epid)
            } else {
                return
            }
            guard !Task.isCancelled else { return }

            subType = info.type
            playInfo.subType = info.type
            playInfo.seasonId = info.season_id

            // Which episode is playing: the one asked for, else where the user
            // left off, else the first.
            let requested = (playInfo.epid ?? 0) > 0 ? info.findEpisodeById(playInfo.epid!) : nil
            let resumed = info.episodes.first { $0.id == info.user_status?.progress?.last_ep_id }
            if let epi = requested ?? resumed ?? info.episodes.first ?? info.section?.first?.episodes.first {
                playInfo.aid = epi.aid
                playInfo.cid = epi.cid
                playInfo.epid = epi.id
            }

            pages = info.episodes.map {
                VideoPage(cid: $0.cid, page: $0.aid, epid: $0.id, from: "",
                          part: $0.title + " " + $0.long_title)
            }
            theater?.pages = pages
            seedNextProvider()
        } catch {
            Logger.warn("[playback] bangumi info failed: \(error)")
        }
    }

    @MainActor
    private func apply(_ detail: VideoDetail) {
        self.detail = detail
        theater?.detail = detail

        if !isBangumi {
            pages = detail.View.pages ?? []
            theater?.pages = pages
        }

        if let season = detail.View.ugc_season {
            if season.sections.count > 1,
               let section = season.sections.first(where: { section in
                   section.episodes.contains { $0.aid == detail.View.aid }
               })
            {
                ugcEpisodes = section.episodes
            } else {
                ugcEpisodes = season.sections.first?.episodes ?? []
            }
            ugcEpisodes.sort { $0.arc.ctime < $1.arc.ctime }
        }

        seedNextProvider()
    }

    private func loadReplies() {
        WebRequest.requestReplys(aid: aid) { [weak self] replys in
            guard let self else { return }
            replies = replys.replies ?? []
            theater?.replies = replies
        }
    }

    /// 下一集 / autoplay. The list is only known once the detail (or season)
    /// request lands, which is after the player was built — hence seeding
    /// rather than passing it in.
    private func seedNextProvider() {
        let currentCid = playInfo.cid ?? 0

        if !pages.isEmpty, let index = pages.firstIndex(where: { $0.cid == currentCid }) {
            let seq = pages.dropFirst(index).map {
                PlayInfo(aid: isBangumi ? $0.page : aid, cid: $0.cid, epid: $0.epid,
                         seasonId: playInfo.seasonId, subType: subType, title: $0.part)
            }
            nextProvider.seed(Array(seq))
            return
        }

        if !ugcEpisodes.isEmpty, let index = ugcEpisodes.firstIndex(where: { $0.cid == currentCid }) {
            let seq = ugcEpisodes.dropFirst(index).map {
                PlayInfo(aid: $0.aid, cid: $0.cid, title: $0.title)
            }
            nextProvider.seed(Array(seq))
        }
    }
}

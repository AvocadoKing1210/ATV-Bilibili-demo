//
//  VideoDataCache.swift
//  BilibiliLive
//
//  In-flight de-duplication for the handful of requests that are issued twice
//  on the way into playback.
//
//  Entering a video fires two independent readers of the same data: the player
//  needs the video detail for its title/description plugin and the SponsorBlock
//  lookup, and the theater's panes need it for 简介 / 相关推荐. Bangumi entries
//  are worse — the season lookup resolves both the episode list for 选集 and the
//  aid/cid the player has to have before it can ask for a play URL.
//
//  Coalescing them means the second reader joins the first request instead of
//  opening its own, which on the startup path is a whole round trip saved.
//

import Foundation

/// Coalesces concurrent loads of the same key and holds the result briefly.
///
/// The TTL is deliberately short: this exists to collapse the burst of requests
/// that one press produces, not to serve stale data later.
actor RequestCoalescer<Key: Hashable, Value> {
    private enum Entry {
        case inProgress(Task<Value, Error>)
        case ready(Value, Date)
    }

    private var entries = [Key: Entry]()
    private let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func value(for key: Key, load: @escaping () async throws -> Value) async throws -> Value {
        switch entries[key] {
        case let .ready(value, time) where Date().timeIntervalSince(time) < ttl:
            return value
        case let .inProgress(task):
            // A failure here belongs to whoever started the request; joining it
            // and losing is the same as having made the call ourselves.
            return try await task.value
        default:
            break
        }

        let task = Task { try await load() }
        entries[key] = .inProgress(task)
        do {
            let value = try await task.value
            entries[key] = .ready(value, Date())
            return value
        } catch {
            // Never cache a failure — the next press should retry.
            entries[key] = nil
            throw error
        }
    }

    func invalidate(_ key: Key) {
        entries[key] = nil
    }
}

enum VideoDataCache {
    /// Long enough to cover one press's fan-out (and an immediate retry), short
    /// enough that view counts and 关注 state are never visibly stale.
    private static let ttl: TimeInterval = 30

    private static let details = RequestCoalescer<Int, VideoDetail>(ttl: ttl)
    private static let seasons = RequestCoalescer<Int, BangumiInfo>(ttl: ttl)
    private static let episodes = RequestCoalescer<Int, BangumiInfo>(ttl: ttl)

    static func detail(aid: Int) async throws -> VideoDetail {
        try await details.value(for: aid) {
            try await WebRequest.requestDetailVideo(aid: aid)
        }
    }

    static func bangumi(seasonID: Int) async throws -> BangumiInfo {
        try await seasons.value(for: seasonID) {
            try await WebRequest.requestBangumiInfo(seasonID: seasonID)
        }
    }

    static func bangumi(epid: Int) async throws -> BangumiInfo {
        try await episodes.value(for: epid) {
            try await WebRequest.requestBangumiInfo(epid: epid)
        }
    }
}

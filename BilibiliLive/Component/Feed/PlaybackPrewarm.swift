//
//  PlaybackPrewarm.swift
//  BilibiliLive
//
//  Resolving a video's cid while the user is still looking at the card.
//
//  Almost every feed hands out `cid: 0` — the list endpoints simply do not
//  return one. The player cannot ask for a play URL without it, so the first
//  thing entering a video does is spend a whole round trip on
//  `/x/player/pagelist`, and nothing else can start until it comes back. It is
//  the last strictly serial hop left in front of the play URL.
//
//  It is also completely predictable: on a 10-foot interface the focused card
//  is the one about to be selected, and it is usually focused for well over a
//  second first. Resolving the cid during that dwell moves the round trip off
//  the click path entirely — the same request, just made while the user was
//  still deciding.
//
//  Deliberately only the cid. Prefetching the play URL too was considered and
//  rejected: those responses carry short-lived signed CDN URLs and cost a real
//  API call against a rate-limited endpoint, which is not something to spend on
//  every card someone scrolls past.
//

import Foundation

@MainActor
final class PlaybackPrewarm {
    static let shared = PlaybackPrewarm()

    private var tasks = [Int: Task<Int, Error>]()
    /// Insertion order, for a crude bound on the map.
    private var order = [Int]()
    private var pending: Task<Void, Never>?

    private let dwell: UInt64 = 250 * NSEC_PER_MSEC
    private let capacity = 64

    private init() {}

    /// Call whenever focus lands on a card. Cheap and safe to call for every
    /// focus change: a fast scroll cancels each pending prefetch before it
    /// fires, so only cards actually dwelt on cost a request.
    func focused(aid: Int, cid: Int) {
        guard aid > 0, cid <= 0, tasks[aid] == nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.dwell ?? 250 * NSEC_PER_MSEC)
            guard !Task.isCancelled else { return }
            _ = self?.task(for: aid)
        }
    }

    /// The cid for a video, from the prefetch if it happened.
    ///
    /// Joins an in-flight prefetch rather than racing it, and falls back to a
    /// fresh request if the prefetched one failed — a prefetch that lost the
    /// network must never be the reason a deliberate press fails.
    func cid(aid: Int) async throws -> Int {
        do {
            return try await task(for: aid).value
        } catch {
            tasks[aid] = nil
            return try await task(for: aid).value
        }
    }

    @discardableResult
    private func task(for aid: Int) -> Task<Int, Error> {
        if let existing = tasks[aid] { return existing }
        let task = Task { try await WebRequest.requestCid(aid: aid) }
        tasks[aid] = task
        order.append(aid)
        if order.count > capacity {
            let evicted = order.removeFirst()
            tasks[evicted] = nil
        }
        return task
    }
}

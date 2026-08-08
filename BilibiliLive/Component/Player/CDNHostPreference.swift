//
//  CDNHostPreference.swift
//  BilibiliLive
//
//  Which CDN host to start on, remembered across videos.
//
//  Measuring the candidates costs a real fraction of a second — they have to be
//  probed one at a time or they steal each other's bandwidth and every number
//  comes out wrong. That measurement used to sit in front of the AVURLAsset on
//  every single play, so every video paid for it again.
//
//  It only has to be paid once. B 站 hands out the same handful of CDN hosts
//  across a session, and which of them is fastest is a property of the network
//  the box is on, not of the video. So: measure after playback has started (out
//  of the startup path, and out of the way of the first segments), remember the
//  winner, and let every later video start on it for free.
//

import Foundation

enum CDNHostPreference {
    private struct Entry {
        let host: String
        let time: Date
    }

    /// Long enough to cover an evening's viewing, short enough that a network
    /// that changed underneath us (Wi-Fi → wired, VPN on/off) is re-measured.
    private static let ttl: TimeInterval = 10 * 60

    private static let lock = NSLock()
    private static var entries = [String: Entry]()

    /// Keyed on the candidate set rather than a single host: a video whose
    /// playurl came back with a different set of CDNs has not been measured,
    /// whatever we know about other sets.
    private static func key(for candidates: [String]) -> String {
        Set(candidates.compactMap { URLComponents(string: $0)?.host }).sorted().joined(separator: "|")
    }

    /// The measured-fastest host for this candidate set, if it is still fresh
    /// and still one of the candidates.
    static func best(among candidates: [String]) -> String? {
        let hosts = Set(candidates.compactMap { URLComponents(string: $0)?.host })
        guard hosts.count > 1 else { return nil }
        let key = key(for: candidates)

        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key],
              Date().timeIntervalSince(entry.time) < ttl,
              hosts.contains(entry.host)
        else { return nil }
        return entry.host
    }

    /// True when this candidate set has no fresh measurement — i.e. it is worth
    /// spending a probe on it once playback is comfortable.
    static func needsMeasurement(for candidates: [String]) -> Bool {
        let hosts = Set(candidates.compactMap { URLComponents(string: $0)?.host })
        guard hosts.count > 1 else { return false }
        return best(among: candidates) == nil
    }

    static func record(host: String, for candidates: [String]) {
        let key = key(for: candidates)
        lock.lock()
        entries[key] = Entry(host: host, time: Date())
        lock.unlock()
        Logger.info("[cdn] 记住起播 host: \(host)")
    }
}

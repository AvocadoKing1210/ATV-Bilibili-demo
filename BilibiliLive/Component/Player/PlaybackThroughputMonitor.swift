//
//  PlaybackThroughputMonitor.swift
//  BilibiliLive
//
//  「当前网速」——正在转圈时，到底还有没有字节在进来。
//

import AVFoundation
import QuartzCore

/// Live download rate for whatever the player is pulling right now.
///
/// `AVPlayerItemAccessLogEvent.observedBitrate` looks like the obvious source
/// and is the wrong one: it is an average over everything downloaded so far, so
/// a line that has just gone dead keeps reporting the healthy rate it used to
/// have — precisely the moment this number is worth showing.
/// `numberOfBytesTransferred` differentiated against wall-clock does fall to
/// zero, which is the answer someone staring at a spinner actually wants.
///
/// Only media traffic is counted, because that is all `AVPlayer` knows about.
/// The startup chain before it (cid → playurl → sidx) goes through Alamofire
/// and shows up as no reading at all rather than as a wrong one.
final class PlaybackThroughputMonitor {
    /// Bytes per second, or nil when there is nothing to measure yet.
    private(set) var bytesPerSecond: Double?
    var onUpdate: ((Double?) -> Void)?

    /// Fast enough that a line going dead is visible about when the viewer
    /// starts to suspect it, slow enough to stay under the burst granularity
    /// of a segment fetch.
    private let interval: TimeInterval = 0.5
    /// Weight of a fresh sample. Segment downloads are bursty — a 6s segment
    /// arrives in one gulp and then nothing does — so the raw delta swings
    /// between tens of MB/s and zero twice a second. This leaves ~1.5s of
    /// memory, which is enough to read off a screen without lying about a
    /// stall for long.
    private let smoothing: Double = 0.4

    private var timer: Timer?
    private var provider: (() -> AVPlayer?)?
    private var lastItem: ObjectIdentifier?
    private var lastBytes: Int64 = 0
    private var lastAt: CFTimeInterval = 0

    deinit { timer?.invalidate() }

    /// The player is fetched per tick rather than held: switching quality or
    /// CDN host swaps the whole `AVPlayer`, and a captured one would quietly
    /// keep reporting the rate of a player nobody is watching.
    func start(player: @escaping () -> AVPlayer?) {
        stop()
        provider = player
        // Baseline now, first real reading one interval later.
        sample()
        // `.common` rather than `scheduledTimer`: focus-driven scrolling in the
        // 相关推荐 rail runs the loop in tracking mode, and a default-mode timer
        // stops dead for as long as the viewer keeps moving.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        provider = nil
        reset()
    }

    private func reset() {
        lastItem = nil
        lastBytes = 0
        lastAt = 0
        bytesPerSecond = nil
    }

    private func sample() {
        guard let item = provider?()?.currentItem else { return publish(nil) }
        let id = ObjectIdentifier(item)
        let now = CACurrentMediaTime()
        let bytes = totalBytes(of: item)
        // The baseline moves on every path, including the ones that publish
        // nothing — otherwise the tick after an item swap reports the new
        // item's whole backlog as if it had arrived in half a second.
        defer {
            lastItem = id
            lastBytes = bytes
            lastAt = now
        }
        guard id == lastItem, lastAt > 0, bytes >= lastBytes else { return publish(nil) }
        let elapsed = now - lastAt
        guard elapsed > 0 else { return }
        let instant = Double(bytes - lastBytes) / elapsed
        publish(bytesPerSecond.map { $0 + (instant - $0) * smoothing } ?? instant)
    }

    /// Sum rather than `events.last`: a server change or a playlist refresh
    /// appends a new event, and each one counts only its own stretch. The total
    /// is the only figure that rises monotonically.
    private func totalBytes(of item: AVPlayerItem) -> Int64 {
        guard let log = item.accessLog() else { return 0 }
        return log.events.reduce(0) { $0 + max(0, $1.numberOfBytesTransferred) }
    }

    private func publish(_ value: Double?) {
        bytesPerSecond = value
        onUpdate?(value)
    }
}

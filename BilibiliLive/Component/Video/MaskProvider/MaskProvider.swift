//
//  MaskProvider.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/6/10.
//
import AVKit

protocol MaskProvider: AnyObject {
    /// Begin any expensive setup — downloads, parsing.
    ///
    /// Separate from `init` so a provider that fetches something can be built
    /// while the plugins are assembled but not start pulling bytes until the
    /// picture is actually up. See `BMaskProvider`.
    func start()
    func getMask(for time: CMTime, frame: CGRect, onGet: @escaping (CALayer) -> Void)
    func needVideoOutput() -> Bool
    func setVideoOutout(ouput: AVPlayerItemVideoOutput)
    func preferFPS() -> Int
}

extension MaskProvider {
    func start() {}
}

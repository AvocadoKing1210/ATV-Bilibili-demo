//
//  Icon.swift
//  BilibiliLive
//
//  Tabler (MIT) glyphs, shipped as vector PDFs in Assets.xcassets/Icons and
//  marked template-rendering so tintColor drives the colour. That is what
//  lets one asset serve a grey idle rail row, a white active one, and a
//  black one on the focus pill — in both tvOS appearances.
//
//  Regenerate with:  docs/preview/tools/make-icon-assets.py
//

import UIKit

enum Icon: String, CaseIterable {
    case search = "icon.search"
    case home = "icon.home"
    case live = "icon.live"
    case follow = "icon.follow"
    case favorite = "icon.favorite"
    case profile = "icon.profile"
    case settings = "icon.settings"
    case hot = "icon.hot"
    case ranking = "icon.ranking"
    case recommend = "icon.recommend"
    case weekly = "icon.weekly"
    case bangumi = "icon.bangumi"
    case history = "icon.history"
    case watchLater = "icon.watchlater"
    case play = "icon.play"
    case danmaku = "icon.danmaku"
    case like = "icon.like"
    case coin = "icon.coin"
    /// The player's danmaku switch. Not Tabler: these two are bilibili's own
    /// 弹 glyph with a check / circle-slash badge, so the toggle reads as the
    /// same control users know from the web and phone players. The badge is
    /// what carries the state — tint alone is not legible at 10 feet.
    case danmakuOn = "icon.danmaku.on"
    case danmakuOff = "icon.danmaku.off"
    /// bilibili's own 稍后再看 mark — a play triangle inside a broken ring.
    /// `watchLater` (Tabler's clock) stays the rail's, where it sits among the
    /// rest of the Tabler set; this one is for the player's action row, where
    /// it has to read as the same control the web and phone apps use.
    case watchLaterPlay = "icon.watchlater.play"

    /// Always template — a non-template copy would ignore tintColor and
    /// vanish on the focus pill.
    var image: UIImage? {
        UIImage(named: rawValue)?.withRenderingMode(.alwaysTemplate)
    }

    /// Emphasised variant for the current section.
    ///
    /// Filled where Tabler ships a fill (search, home, favorite, settings,
    /// hot, bangumi, watchLater, play, like, coin); a heavier stroke where it
    /// does not (live, follow, profile, ranking, history, danmaku). Tabler's
    /// filled set has no `users`, `broadcast` or `user-circle`, and
    /// substituting the single-person `user` would change the glyph's
    /// silhouette between states — worse than a weight step.
    var activeImage: UIImage? {
        UIImage(named: rawValue + ".active")?.withRenderingMode(.alwaysTemplate) ?? image
    }
}

extension TabBarPage {
    /// Rail glyph for each page the app already ships.
    var railIcon: Icon {
        switch self {
        case .live: return .live
        case .feed: return .recommend
        case .hot: return .hot
        case .ranking: return .ranking
        case .follows: return .follow
        case .favorite: return .favorite
        case .personal: return .settings
        case .search: return .search
        case .followBangumi: return .bangumi
        case .followUps: return .follow
        case .toView: return .watchLater
        case .history: return .history
        case .weeklyWatch: return .weekly
        }
    }
}

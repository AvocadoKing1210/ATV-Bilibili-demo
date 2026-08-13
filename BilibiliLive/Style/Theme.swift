//
//  Theme.swift
//  BilibiliLive
//
//  The design tokens behind the settings screen, ported from the
//  discord-tvos-proto prototype (app/DiscordTV/DesignTokens.swift), which
//  extracted them from Discord's live web client CSS custom properties
//  (dark theme + visual refresh) on 2026-08-12. See that repo's
//  docs/DESIGN-TOKENS.md for the extraction record.
//
//  The settings screen is where they landed first: it drops the app's own
//  design system (`DS`) in favour of these — SwiftUI, flat web-hover focus,
//  no tvOS lift/scale — and other views have since picked the same tokens up.
//  Values are web px; tvOS points at 1080p map 1:1, and `scale` grows the
//  whole system uniformly for 10-foot legibility.
//
//  Every colour is a *pair*, the way `DS.Color` already is. The extraction only
//  ever captured Discord's dark theme, and shipping those values raw meant the
//  settings screen stayed dark while the rail beside it went light, and the
//  modal — whose surface is the system's own material, and therefore flips —
//  drew near-white text on a near-white panel. The dark column is unchanged;
//  the light column is its role-for-role counterpart, pitched into the same
//  warm neutral family `DS` uses so the two systems sit side by side.
//

import SwiftUI
import UIKit

extension Color {
    /// sRGB hex color, e.g. Color(hex: 0x5865F2).
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    /// Uniform scale over the whole metric system. 1.0 = exact web pixels;
    /// the prototype ships 1.0 for parity, this app runs 1.5 because a 16px
    /// row label does not survive 10 feet.
    static let scale: CGFloat = 1.5

    // MARK: - Colors (sRGB, resolved from CSS custom properties)

    enum Colors {
        // Backgrounds. The hierarchy inverts wholesale: where Dark seats the
        // nav column *below* the pane, Light seats it above — a grey rail
        // against a near-white pane, which is the arrangement the web client
        // ships in its own light theme.
        static let baseLowest = dynamic(dark: 0x121214, light: 0xE9E8E6) // app frame, rail, sidebar
        static let baseLower = dynamic(dark: 0x1A1A1E, light: 0xFAF9F8) // chat/content panel
        static let baseLow = dynamic(dark: 0x202024, light: 0xF2F1F0) // user panel
        static let surfaceHigh = dynamic(dark: 0x242429, light: 0xE4E3E1) // rail tiles, surfaces
        static let surfaceHigher = dynamic(dark: 0x28282D, light: 0xDCDBD9)
        static let surfaceRaised = dynamic(dark: 0x27272C, light: 0xE0DFDD) // embeds

        // Text
        static let textDefault = dynamic(dark: 0xEFEFF1, light: 0x2E2E30) // body
        static let textStrong = dynamic(dark: 0xFBFBFB, light: 0x101010) // titles, selected rows
        static let textMuted = dynamic(dark: 0x96979E, light: 0x6B6C72) // values, timestamps
        static let textSubtle = dynamic(dark: 0xABACB2, light: 0x5A5B61) // secondary icons
        static let channelsDefault = dynamic(dark: 0x81828A, light: 0x6A6B72) // nav rows at rest
        /// The switch's off-track. Has to read as a filled-but-inert capsule
        /// against its ground, so it darkens in Dark and lightens in Light
        /// rather than keeping one value that would vanish into one of them.
        static let interactiveMuted = dynamic(dark: 0x4F505A, light: 0xB9B9C0)

        // Brand. Fixed in both: a brand colour that shifts is not one.
        static let blurple = Color(hex: 0x5865F2) // brand-500
        static let blurpleActive = Color(hex: 0x4654C0) // brand-560
        /// Ink for things drawn *on* a brand fill, so it stays white in both.
        static let white = Color(hex: 0xFFFFFF)

        // Status. Meanings, not brand — but each still has to hold contrast
        // against its own ground, so the light column darkens.
        static let online = dynamic(dark: 0x3D9E60, light: 0x2F7D4F)
        static let danger = dynamic(dark: 0xDA3E44, light: 0xC02A31)
        static let warning = dynamic(dark: 0xFDB833, light: 0xB07508)

        // Borders & interactive overlays. These are the tokens a straight port
        // gets most wrong: they are *lightenings* of the ground in Dark, and a
        // lightening laid over a pale ground is nothing at all. Light darkens
        // instead, at the alphas that come out to the same apparent strength.
        static let borderSubtle = dynamic(dark: 0x94949C, light: 0x2E2E30,
                                          darkAlpha: 0.12, lightAlpha: 0.14) // dividers
        static let borderFaint = dynamic(dark: 0x94949C, light: 0x2E2E30,
                                         darkAlpha: 0.04, lightAlpha: 0.06) // 1px panel edges
        static let hoverOverlay = dynamic(dark: 0x94949C, light: 0x1A1A1E,
                                          darkAlpha: 0.12, lightAlpha: 0.08) // mod-subtle
        static let activeOverlay = dynamic(dark: 0x9595A2, light: 0x1A1A1E,
                                           darkAlpha: 0.16, lightAlpha: 0.10) // mod-normal
        static let selectedOverlay = dynamic(dark: 0x9696A0, light: 0x1A1A1E,
                                             darkAlpha: 0.20, lightAlpha: 0.13) // mod-strong
        static let scrim = Color(hex: 0x000000, alpha: 0.72)
    }

    /// One colour, stated for both appearances. Bridged from a dynamic
    /// `UIColor` rather than built from `@Environment(\.colorScheme)` so that a
    /// token can be read from a `static let` — SwiftUI resolves the provider
    /// against whatever trait collection the view is drawn in, which is also
    /// what makes these work inside a `UIHostingController`.
    static func dynamic(dark: Int, light: Int,
                        darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color
    {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(rgb: light, alpha: lightAlpha)
                : UIColor(rgb: dark, alpha: darkAlpha)
        })
    }

    // MARK: - Metrics (web px × scale)
    //
    // The settings chrome, measured off the web client's settings view the
    // same way the prototype measured the chat chrome: a nav column of 32px
    // rows with 8px radius, 14px category labels, hairline group dividers,
    // and a content pane led by a 20px semibold heading.

    enum Metrics {
        // Nav column
        static let sidebarWidth = 260 * scale
        static let rowHeight = 36 * scale
        static let rowCornerRadius = 8 * scale
        static let rowInnerPadH = 10 * scale
        static let rowIconSize = 20 * scale
        static let rowIconGap = 8 * scale
        static let rowGap = 2 * scale
        static let categoryTopPad = 20 * scale
        static let categoryBottomPad = 6 * scale
        static let dividerVPad = 12 * scale

        // Profile block at the top of the nav column
        static let profileAvatar = 44 * scale
        static let profileHeight = 64 * scale

        // Content pane
        static let paneGap = 32 * scale
        static let panePadH = 40 * scale
        static let panePadTop = 40 * scale
        static let paneHeadingGap = 16 * scale
        static let paneRowHeight = 46 * scale
        static let paneMaxWidth = 660 * scale

        // Toggle switch (measured off the web client at 40×24, knob 18)
        static let switchWidth = 40 * scale
        static let switchHeight = 24 * scale
        static let switchKnob = 18 * scale
    }

    // MARK: - Typography
    // Web uses "gg sans" (proprietary); the system font stands in at the
    // same sizes/weights, and CJK falls through to PingFang either way.

    enum Fonts {
        static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size * scale, weight: weight)
        }

        static var navRow: Font { sans(16, .medium) } // channel name 16/500
        static var categoryLabel: Font { sans(13, .semibold) } // 14/500, tightened
        static var paneHeading: Font { sans(20, .semibold) } // settings heading 20/600
        static var rowTitle: Font { sans(16, .medium) }
        static var rowValue: Font { sans(15) }
        static var profileName: Font { sans(16, .semibold) }
        static var profileSub: Font { sans(12) }
    }
}

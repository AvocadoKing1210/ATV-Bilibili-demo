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

import SwiftUI

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
        // Backgrounds
        static let baseLowest = Color(hex: 0x121214) // app frame, rail, sidebar
        static let baseLower = Color(hex: 0x1A1A1E) // chat/content panel
        static let baseLow = Color(hex: 0x202024) // user panel
        static let surfaceHigh = Color(hex: 0x242429) // rail tiles, surfaces
        static let surfaceHigher = Color(hex: 0x28282D)
        static let surfaceRaised = Color(hex: 0x27272C) // embeds

        // Text
        static let textDefault = Color(hex: 0xEFEFF1) // body
        static let textStrong = Color(hex: 0xFBFBFB) // titles, selected rows
        static let textMuted = Color(hex: 0x96979E) // values, timestamps
        static let textSubtle = Color(hex: 0xABACB2) // secondary icons
        static let channelsDefault = Color(hex: 0x81828A) // nav rows at rest
        static let interactiveMuted = Color(hex: 0x4F505A)

        // Brand
        static let blurple = Color(hex: 0x5865F2) // brand-500
        static let blurpleActive = Color(hex: 0x4654C0) // brand-560
        static let white = Color(hex: 0xFFFFFF)

        // Status
        static let online = Color(hex: 0x3D9E60)
        static let danger = Color(hex: 0xDA3E44)
        static let warning = Color(hex: 0xFDB833)

        // Borders & interactive overlays
        static let borderSubtle = Color(hex: 0x94949C, alpha: 0.12) // dividers
        static let borderFaint = Color(hex: 0x94949C, alpha: 0.04) // 1px panel edges
        static let hoverOverlay = Color(hex: 0x94949C, alpha: 0.12) // mod-subtle
        static let activeOverlay = Color(hex: 0x9595A2, alpha: 0.16) // mod-normal
        static let selectedOverlay = Color(hex: 0x9696A0, alpha: 0.20) // mod-strong
        static let scrim = Color(hex: 0x000000, alpha: 0.72)
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

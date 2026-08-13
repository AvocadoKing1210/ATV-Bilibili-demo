//
//  DS.swift
//  BilibiliLive
//
//  Design tokens for the reworked UI. Transcribed from docs/UI-REWORK.md §2
//  and verified at 1920x1080 in docs/preview/index.html.
//
//  Everything here is appearance-aware: tvOS ships both Light and Dark, so
//  each colour is a dynamic provider rather than a fixed value. The focus
//  fill (`pill`) is always the opposite pole of the ground, and `pillInk` is
//  its counterpart — that pair is what lets a glyph invert on focus instead
//  of washing out.
//

import CoreText
import UIKit

enum DS {
    // MARK: - Colour

    enum Color {
        /// Screen background. Never pure black — pure black is the player's.
        static let bg = dynamic(dark: 0x14_14_14, light: 0xF2_F1_F0)
        /// Cards, rails, panels.
        static let surface = dynamic(dark: 0x1F_1F_1F, light: 0xE4_E3_E1)
        /// Chips and focus-adjacent surfaces.
        static let surfaceRaised = dynamic(dark: 0x2A_2A_2A, light: 0xD8_D7_D4)

        static let textPrimary = dynamic(dark: 0xFF_FF_FF, light: 0x10_10_10)
        static let textSecondary = dynamic(dark: 0xFF_FF_FF, light: 0x10_10_10, darkAlpha: 0.60, lightAlpha: 0.62)
        static let textTertiary = dynamic(dark: 0xFF_FF_FF, light: 0x10_10_10, darkAlpha: 0.38, lightAlpha: 0.42)

        /// Bilibili pink. Functional and rare — progress, LIVE, selection.
        /// Darkened in Light so it still holds contrast on a pale ground.
        static let accent = dynamic(dark: 0xFF_66_99, light: 0xE0_44_7A)
        /// Links and VIP badges only.
        static let accentBlue = dynamic(dark: 0x00_AE_EC, light: 0x00_89_BA)

        /// Focus fill — the opposite pole of `bg`.
        static let pill = dynamic(dark: 0xF4_F4_F4, light: 0x14_14_14)
        /// Everything sitting on `pill`, glyphs included.
        static let pillInk = dynamic(dark: 0x0C_0C_0C, light: 0xF4_F4_F4)
        /// Focus ring around thumbnails and chips.
        static let ring = dynamic(dark: 0xFF_FF_FF, light: 0x10_10_10)

        static let scrim = UIColor.black.withAlphaComponent(0.6)
        static let skeleton = dynamic(dark: 0xFF_FF_FF, light: 0x00_00_00, darkAlpha: 0.08, lightAlpha: 0.07)

        private static func dynamic(dark: Int, light: Int,
                                    darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> UIColor
        {
            UIColor { trait in
                trait.userInterfaceStyle == .light
                    ? UIColor(rgb: light, alpha: lightAlpha)
                    : UIColor(rgb: dark, alpha: darkAlpha)
            }
        }
    }

    // MARK: - Type
    //
    // The reference's own face is Circular, which is licensed and cannot ship
    // here, so the ramp runs on Outfit — an OFL geometric sans, bundled from
    // `Supporting Files/Fonts` as a single variable file. One file buys the
    // whole 100–900 axis, which is why it is preferred over the four static
    // cuts the ramp would otherwise need.
    //
    // It is not a Circular clone, and the difference has a name: Outfit's `a`
    // is single-storey, a circle and a stem, where Circular's is double-storey.
    // That is the one letter that reads as "not the reference" to anyone who
    // knows it — the trade was made deliberately. Everything else lines up:
    // near-circular bowls, tall x-height, open apertures, and a `1` with no
    // base serif, which is closer to Circular than Avenir Next ever was.
    //
    // Only Latin and figures actually change. Outfit carries 360 glyphs and no
    // CJK, so every Chinese glyph still resolves to PingFang through the
    // fallback cascade — exactly what the all-system ramp resolved to before —
    // which leaves the bulk of the UI untouched and swaps the face precisely
    // where the reference's is most recognisable: counts, durations and dates.
    // PingFang has no Bold, so a Bold request renders CJK Semibold, which is
    // optically right. Never track or letter-space CJK.
    //
    // Floor is 23pt; nothing below that survives 10 feet. The one exception is
    // `overlay`, which is read at arm's length off a solid pill on the
    // thumbnail rather than as running text.

    enum Font {
        static let screenTitle = face(57, .bold)
        static let rowHeader = face(38, .semibold)
        static let cardTitle = face(29, .semibold)
        /// A step further down than it was (25). At 4pt from the title the two
        /// card lines read as one block; the extra step, on top of the 60%
        /// ink `textSecondary` already carries, is what makes the title the
        /// thing you land on.
        static let meta = face(23, .medium)
        static let badge = face(23, .semibold)
        /// Counts and duration on the thumbnail. Smaller than `badge` on
        /// purpose — these sit over picture and should read as an annotation,
        /// not as a second title competing with the one below the card.
        static let overlay = face(21, .semibold)
        static let body = face(29, .medium)
        static let navLabel = face(31, .medium)
        /// Chips only, and one weight for both states. The reference never
        /// re-weights a chip on selection — the fill is the whole state signal —
        /// and a weight step would also reflow the row, since Semibold is wider
        /// than Medium and every chip beside the selected one would shift.
        static let chipLabel = face(31, .semibold)

        /// Every weight is dialled in on the `wght` axis, and it has to be:
        /// the variable file's *default* instance is Thin, and its named
        /// instances carry no PostScript names of their own. `UIFont(name:)`
        /// finds nothing to match, and a bare family lookup lands on 100-weight
        /// hairlines that vanish at ten feet.
        ///
        /// A family CoreText cannot find is substituted rather than refused —
        /// ask for one that does not exist and Helvetica comes back, with no
        /// error — so the resolved family is checked before the font is handed
        /// out. If the bundle ever ships without the file, the ramp degrades to
        /// the system font at the right weight instead of silently to Helvetica.
        private static func face(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            outfit(size, wght: axisValue(for: weight)) ?? .systemFont(ofSize: size, weight: weight)
        }

        private static func outfit(_ size: CGFloat, wght: CGFloat) -> UIFont? {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: family,
                variationAttribute: [wghtAxis: wght],
            ])
            let font = UIFont(descriptor: descriptor, size: size)
            guard font.familyName == family else { return nil }
            return font
        }

        /// The ramp only ever asks for these four, though the axis runs 100–900.
        /// Heavier-than-bold requests clamp to 700 rather than climbing into
        /// ExtraBold, which at 57pt on a 10-foot screen closes the counters up.
        private static func axisValue(for weight: UIFont.Weight) -> CGFloat {
            switch weight {
            case .bold, .heavy, .black: return 700
            case .semibold: return 600
            case .medium: return 500
            default: return 400
            }
        }

        private static let family = "Outfit"
        /// `wght`, as the four-character code CoreText wants for a variation axis.
        private static let wghtAxis = 0x7767_6874
        /// UIKit exposes no typed key for variations; the CoreText one is it.
        private static let variationAttribute = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
    }

    // MARK: - Metrics

    enum Space {
        static let xs: CGFloat = 8
        static let s: CGFloat = 16
        static let m: CGFloat = 24
        static let l: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 64

        /// Apple HIG grid gutter.
        static let gutter: CGFloat = 40
        /// Minimum gap between shelves.
        static let shelfGap: CGFloat = 48
        static let safeH: CGFloat = 80
        static let safeV: CGFloat = 60
        /// Shared baseline for the first rail row and the first chip, so the
        /// two columns start on one line.
        static let topRow: CGFloat = 52
        /// Gap between the rail's trailing edge and the content column.
        /// Must clear the focus overshoot — a 1.08-scaled 528pt card grows
        /// ~21pt past its own left edge — or the leftmost card is clipped
        /// against the rail by the collection view's bounds.
        static let contentLead: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let railRow: CGFloat = 14
    }

    /// The two chips drawn over a card thumbnail: counts on the bottom-left,
    /// duration on the bottom-right.
    ///
    /// They are one row and are read as one, so they take one height and one
    /// baseline. Sizing each to its own content is what put them out of line —
    /// the left chip carries icons and the right does not, so it came out ~5pt
    /// taller off the same bottom inset, and the mismatch shows at the top edge
    /// where nothing anchors them.
    ///
    /// `radius` is derived, not chosen. An inner corner sitting `inset` inside
    /// an outer corner of `Radius.card` has to be `card - inset` for the two
    /// curves to stay parallel; anything else and the chip reads as a sticker
    /// laid on the card rather than part of it. Move `card` or `inset` and the
    /// chip follows on its own.
    enum CardChip {
        /// From the thumbnail's edges. Also the gap the radius is derived from.
        static let inset: CGFloat = 8
        static let height: CGFloat = 34
        static let radius: CGFloat = Radius.card - inset
        /// Real padding, which is what lets both chips share one rule — the
        /// duration used to buy its breathing room with spaces around the text.
        static let hInset: CGFloat = 10
        /// Icon and its gap to the label, on the counts chip.
        static let icon: CGFloat = 20
        static let iconGap: CGFloat = 5
        /// Between the count groups inside the left chip.
        static let groupGap: CGFloat = 14
    }

    enum Rail {
        static let collapsed: CGFloat = 150
        static let expanded: CGFloat = 440
        static let rowHeight: CGFloat = 64
        /// Collapsed, the rail is nothing but glyphs, so it needs more air
        /// between them than the labelled state does to stay readable.
        static let rowGap: CGFloat = 26
        static let icon: CGFloat = 44
        static let inset: CGFloat = 24
    }

    /// Chip geometry, transcribed from the reference chip row (Spotify's TV
    /// chips) and re-expressed against our own 31pt label, since the type ramp
    /// is fixed by the 10-foot floor and the box is what has to move.
    ///
    /// Every number below is a ratio of the label size, so the whole set scales
    /// together if the ramp ever changes:
    ///
    ///     height  2.6 em   hInset  1.15 em   icon  1.1 em
    ///     gap     0.9 em   iconGap 0.32 em   radius height/2
    ///
    /// The one the old spec had backwards is `height`. At 64 against a 31pt
    /// label the box was 2.06 em — the text nearly filled it, which is what made
    /// our chips read as tight buttons next to the reference's airy pills.
    enum Chip {
        /// 2.6 em. Corroborated independently by `Theater.Metrics`, which
        /// measured the reference's own chip strip at 79 in 1920×1080 space.
        static let height: CGFloat = 80
        static let gap: CGFloat = 28
        static let hInset: CGFloat = 36
        /// Just over the label, not over-weight against it. The old 38 came from
        /// wanting the glyph to out-shout two CJK characters at 10 feet; the
        /// reference does the opposite — icon and text are one optical size, and
        /// the icon leads rather than dominates.
        static let icon: CGFloat = 34
        /// Icon-to-label. Tighter than it measures, because an SF Symbol carries
        /// its own slack inside the box and the drawn gap comes out wider.
        static let iconGap: CGFloat = 10
        /// topRow + height + 22, i.e. the full sticky bar.
        static let barHeight: CGFloat = 154
    }

    enum Focus {
        static let cardScale: CGFloat = 1.08
        static let rowScale: CGFloat = 1.05
        static let duration: TimeInterval = 0.18
        static let shadowOffset = CGSize(width: 0, height: 16)
        static let shadowRadius: CGFloat = 24
        static let shadowOpacity: Float = 0.25
    }

    /// A cubic curve kept as raw control points, so one definition can drive
    /// both a `UIViewPropertyAnimator` and a `CAMediaTimingFunction`.
    /// `UICubicTimingParameters` does not hand its points back, so deriving
    /// one from the other is not possible.
    struct Curve {
        let p1: CGPoint
        let p2: CGPoint

        var timingParameters: UICubicTimingParameters {
            UICubicTimingParameters(controlPoint1: p1, controlPoint2: p2)
        }

        var mediaTimingFunction: CAMediaTimingFunction {
            CAMediaTimingFunction(controlPoints: Float(p1.x), Float(p1.y), Float(p2.x), Float(p2.y))
        }
    }

    /// Motion for things that *travel*, as opposed to `Focus`, which is the
    /// clock for things that merely change colour or lift under the cursor.
    ///
    /// The rail cannot ride the focus engine's implicit timing. That duration
    /// is tuned for a card growing 8% in place; the rail moves 290pt and takes
    /// the whole content column with it, and at focus speed the pill does not
    /// read as *extending* — it reads as a white block appearing, then a hard
    /// edge wiping across it.
    enum Motion {
        /// Rail open and close. 300ms is where the extension becomes legible:
        /// under ~240 the pill still pops, over ~360 the remote feels laggy.
        /// Both directions share it, so opening and closing are mirror images.
        static let rail: TimeInterval = 0.30

        /// Opening is a plain decelerate — UIKit's own `.curveEaseOut` points.
        ///
        /// Both of these were measured back off a 60fps capture rather than
        /// picked by eye, because a curve that *sounds* right can be nothing of
        /// the sort: an earlier, harder ease-out (0.17, 0.84, 0.24, 1) put 35%
        /// of the travel into the first frame and 92% into the first six. The
        /// duration was 300ms and it still read as a snap followed by a creep,
        /// because by the time the eye caught up the rail was already open.
        /// These two spend ~9% of the distance on the first frame and reach
        /// halfway at the halfway point, which is what makes the extension
        /// something you can actually watch.
        static let railOpenCurve = Curve(p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 0.58, y: 1))
        /// Closing eases in as well as out. Leaving on a pure decelerate
        /// snatches the content column back the instant focus clears the rail;
        /// this lets it start moving before it commits.
        static let railCloseCurve = Curve(p1: CGPoint(x: 0.3, y: 0), p2: CGPoint(x: 0.4, y: 1))

        /// Fraction of `rail` to wait before labels start arriving, so they
        /// fade up in space the rail has already opened instead of underneath
        /// its moving edge.
        static let railLabelDelay: CGFloat = 0.32
        /// Closing, they go first and fast: a label still at full strength when
        /// the edge reaches it gets visibly sliced.
        static let railLabelOut: TimeInterval = 0.12
    }

    /// Card width is derived from the space the rail actually leaves, never
    /// asserted — see docs/preview: a hardcoded 410 overflows once the rail
    /// takes its 150.
    /// Columns the display can carry, resolved once at launch.
    ///
    /// tvOS reports a 1920×1080 *layout* on every device, so bounds tell you
    /// nothing about the hardware. `nativeBounds` does: 3840 on a 4K Apple TV,
    /// 1920 at 1080p, 1280 on an HD one. That is the only runtime signal that
    /// separates a big screen from a small one.
    static let displayColumns: Int = {
        let nativeWidth = UIScreen.main.nativeBounds.width
        return nativeWidth >= 1920 ? 4 : 3
    }()

    /// Smallest card that still reads at 10 feet. Below this, drop a column
    /// rather than shrink further.
    private static let minCardWidth: CGFloat = 360

    /// Starts from what the display can carry, then backs off if the space the
    /// rail actually leaves would squeeze cards below `minCardWidth`.
    static func columns(forContentWidth width: CGFloat) -> Int {
        var cols = displayColumns
        while cols > 3, cardWidth(containerWidth: width, columns: cols) < minCardWidth {
            cols -= 1
        }
        return cols
    }

    static func cardWidth(containerWidth: CGFloat, columns: Int) -> CGFloat {
        let usable = containerWidth
            - Space.contentLead - Space.safeH
            - Space.gutter * CGFloat(columns - 1)
        return (usable / CGFloat(columns)).rounded(.down)
    }
}

extension UIColor {
    convenience init(rgb: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

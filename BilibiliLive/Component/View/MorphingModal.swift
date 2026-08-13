//
//  MorphingModal.swift
//  BilibiliLive
//
//  One modal for the whole app, drawn after beui.dev's morphing modal
//  (beui.dev/components/motion/morphing-modal).
//
//  What that component actually is: a single panel that springs in, then
//  *resizes itself* when its content changes while the content cross-fades
//  through a blur — so a change of question reads as one panel re-forming
//  rather than two panels swapping. Its numbers are ported here verbatim:
//  panel spring (stiffness 420, damping 40, mass 0.5), content 0.24s ease-out
//  in / 0.16s out with a 4px blur and a small vertical drift, a rounded-3xl
//  bordered panel over a blurred, saturated backdrop.
//
//  Two departures from the reference, both deliberate. The panel takes beui's
//  *bottom* placement — anchored near the lower edge and rising into it —
//  rather than the centred one, because a dialog that grows out of the middle
//  of a ten-foot screen reads as an interruption. And its surface is the
//  system's own glass where the OS has it, so the modal belongs to the TV
//  rather than to any one screen's palette; nothing here is a brand colour.
//
//  Web px map to points through `Theme.scale`, the same way the settings
//  screen's tokens do — the modal is most often read on top of that screen and
//  has to sit in its type ramp.
//
//  Everything modal in this app routes here: the settings pickers, the
//  theater player's option sheets, and the few plain notices. `UIAlertController`
//  ordering is preserved — the panel leaves the screen *before* an action's
//  handler runs, which callers like `VideoTheaterViewController` depend on
//  (their OK handler dismisses the presenter itself).
//

import SwiftUI
import UIKit

// MARK: - Request

/// What a modal is asking. One title, an optional line of explanation, an
/// optional text field, and the rows you can land on.
struct MorphingModalRequest: Identifiable {
    struct Option: Identifiable {
        enum Role {
            case normal
            /// Inked red at rest, red-filled on focus — 登出, 删除.
            case destructive
        }

        let id = UUID()
        let title: String
        /// Draws the checkmark: this is the value the setting currently holds.
        let isSelected: Bool
        let role: Role
        /// Handed the field's text, so a text-entry modal's confirm row can
        /// read it without the caller holding state of its own.
        let handler: (String) -> Void

        init(_ title: String, isSelected: Bool = false, role: Role = .normal,
             handler: @escaping (String) -> Void)
        {
            self.title = title
            self.isSelected = isSelected
            self.role = role
            self.handler = handler
        }

        init(_ title: String, isSelected: Bool = false, role: Role = .normal,
             handler: @escaping () -> Void = {})
        {
            self.init(title, isSelected: isSelected, role: role) { _ in handler() }
        }
    }

    struct Field {
        var placeholder: String = ""
        var text: String = ""
    }

    let id = UUID()
    var title: String
    var message: String? = nil
    var field: Field? = nil
    var options: [Option] = []
    /// The row that only closes the panel. `nil` leaves the modal without one,
    /// which is only right when an option always has to be picked.
    var cancelTitle: String? = "取消"

    /// A notice: one line to read, one row to leave by.
    static func notice(title: String, message: String? = nil,
                       dismissTitle: String = "OK",
                       onDismiss: @escaping () -> Void = {}) -> MorphingModalRequest
    {
        MorphingModalRequest(title: title, message: message,
                             options: [Option(dismissTitle, handler: onDismiss)],
                             cancelTitle: nil)
    }

    /// One-of-N, the shape every settings picker takes.
    static func picker(title: String, message: String? = nil,
                       titles: [String], selected: Int?,
                       select: @escaping (Int) -> Void) -> MorphingModalRequest
    {
        MorphingModalRequest(
            title: title,
            message: message,
            options: titles.enumerated().map { index, name in
                Option(name, isSelected: index == selected) { select(index) }
            }
        )
    }
}

// MARK: - Tokens

enum MorphingModal {
    /// Web px × `Theme.scale`, as in `Theme`.
    enum Style {
        static let panelWidth = 400 * Theme.scale
        /// rounded-3xl.
        static let radius = 24 * Theme.scale
        static let hairline = 1 * Theme.scale
        static let panelPad = 24 * Theme.scale
        static let rowHeight = 44 * Theme.scale
        static let rowRadius = 12 * Theme.scale
        static let rowPadH = 16 * Theme.scale
        static let rowGap = 8 * Theme.scale
        static let titleGap = 6 * Theme.scale
        static let headerGap = 20 * Theme.scale
        /// Between the options and the row that only leaves.
        static let cancelGap = 12 * Theme.scale
        /// Past this the options scroll instead of growing the panel.
        static let listMaxHeight = 380 * Theme.scale

        /// shadow-2xl, opened up for a dark ground.
        static let shadowRadius = 30 * Theme.scale
        static let shadowY = 12 * Theme.scale
        static let shadowOpacity = 0.55

        /// How far below its resting place the panel starts. beui's bottom
        /// placement uses 40px; at ten feet that reads as a twitch, so the
        /// rise is doubled — far enough to be a movement you can watch,
        /// short enough that the spring still lands inside its own duration.
        static let entryOffset = 80 * Theme.scale
        /// Clear of the display's own overscan, and enough ground under the
        /// panel that it reads as resting there rather than falling off.
        static let bottomInset = 56 * Theme.scale
        /// Not zero, and that is not a rounding artefact: a fully transparent
        /// view is not focusable, so a panel that entered from 0 had no rows
        /// for the focus engine to choose from during its first update.
        static let entryOpacity = 0.01
        /// The 4px blur, on the way in and between contents.
        static let blur = 4 * Theme.scale
        static let contentDrift = 8 * Theme.scale

        // Neutral, and glass where the OS will draw it. Nothing here is a
        // brand colour: the modal serves the settings screen, the player and
        // the feeds, and a tinted focus fill would speak for whichever one it
        // was borrowed from. Focus is stated the way the rest of the app
        // states it — a light fill with dark ink (`DS.Color.pill`/`pillInk`).
        static let panelBorder = Color(hex: 0xFFFFFF, alpha: 0.14)
        /// A row at rest is a lightening of the glass, not a surface laid on
        /// it — a second opaque fill over a material reads as a sticker.
        static let rowFill = Color(hex: 0xFFFFFF, alpha: 0.10)
        /// The row that only leaves sits a step back from the ones that act.
        static let rowMutedFill = Color(hex: 0xFFFFFF, alpha: 0.06)
        static let rowFocusFill = Color(hex: 0xFFFFFF)
        static let rowFocusInk = Color(hex: 0x0C0C0C)
        /// Destructive keeps its red — that is a meaning, not a brand.
        static let dangerFill = Theme.Colors.danger
        static let dangerInk = Color(hex: 0xFFFFFF)
        /// Read against the system's white focused text field, not against us.
        static let fieldFocusInk = Color(hex: 0x0C0C0C)
        /// bg-background/5 over the backdrop blur. Kept light on purpose: the
        /// material already carries most of the separation, and the screen
        /// behind should stay recognisable rather than go to black.
        static let scrimTint = Color(hex: 0x000000, alpha: 0.18)

        static var title: Font { Theme.Fonts.sans(20, .semibold) }
        static var message: Font { Theme.Fonts.sans(15) }
        static var row: Font { Theme.Fonts.sans(16, .medium) }
    }

    enum Motion {
        /// beui's SPRING_PANEL is mass 0.5 / stiffness 420 / damping 40, and
        /// those are the numbers this started with. They are *overdamped* —
        /// critical damping at that mass and stiffness is 2√(km) ≈ 29, so 40
        /// puts the ratio at ~1.38 — and an overdamped spring spends its last
        /// third of travel crawling. That crawl is what read as unfluent: the
        /// panel arrived quickly and then took another fifth of a second to
        /// finish arriving.
        ///
        /// Retuned to *exactly* critical, which is both the fastest a spring
        /// can settle without overshooting and the only ratio with no tail to
        /// crawl through. The numbers are picked so the identities come out
        /// whole: ω₀ = √(k/m) = √(640/0.4) = 40 rad/s, and damping = 2√(km)
        /// = 2√256 = 32. Settling (95%) ≈ 4.75/ω₀ ≈ 120ms, half of what the
        /// ported values took. No overshoot is deliberate — a dialog that
        /// wobbles on a ten-foot screen reads as cheap, not as lively.
        static let panel = Animation.interpolatingSpring(mass: 0.4, stiffness: 640, damping: 32)
        /// Content follows the panel's new clock rather than beui's 0.24/0.16.
        static let contentIn = Animation.easeOut(duration: 0.14)
        static let contentOut = Animation.easeIn(duration: 0.1)
        /// How long to hold the modal on screen after it starts leaving.
        /// Matches `contentOut` — any longer and the modal is gone but the
        /// controller is still up, which the user reads as lag on dismissal.
        static let exitDuration: TimeInterval = 0.1
        /// A ladder, not a delay. `defaultFocus` loses to the focus engine's
        /// own first update often enough that the panel needs to re-state
        /// where focus belongs — and a single late correction is exactly the
        /// visible 取消-then-jump this replaces. Every rung lands inside the
        /// entrance, while the panel is still rising, so the claim that wins
        /// is never one the eye can catch; whichever rung takes, the rest
        /// see the right target already focused and do nothing.
        ///
        /// Compressed along with the spring: the entrance is ~120ms now, so
        /// rungs that used to be masked by the rise would land on a settled
        /// panel — where a correction is exactly the jump this exists to
        /// prevent. The first four sit inside the rise; the last is
        /// insurance, and reaching it means something is wrong anyway.
        static let focusClaims: [TimeInterval] = [0, 0.016, 0.04, 0.08, 0.16]
    }
}

// MARK: - View

struct MorphingModalView: View {
    let request: MorphingModalRequest
    /// Close, then run this. The two are ordered, not concurrent: the host
    /// tears the modal down first so a handler is free to dismiss whatever
    /// presented it.
    let onClose: (@escaping () -> Void) -> Void

    private enum Target: Hashable {
        case field
        case option(Int)
        case cancel
    }

    @State private var shown = false
    @State private var fieldText = ""
    @FocusState private var focus: Target?

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            panel
                .padding(.bottom, MorphingModal.Style.bottomInset)
        }
        .ignoresSafeArea()
        .onAppear {
            fieldText = request.field?.text ?? ""
            shown = true
            claimFocus()
        }
        .onExitCommand { close {} }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(MorphingModal.Style.scrimTint)
            .opacity(shown ? 1 : 0)
            .animation(shown ? MorphingModal.Motion.contentIn : MorphingModal.Motion.contentOut,
                       value: shown)
    }

    // MARK: Panel

    private var panel: some View {
        // `id` + transition on the content alone, chrome outside it: a new
        // request cross-fades what the panel says while the panel itself
        // stays put and resizes to fit.
        content
            .id(request.id)
            .transition(.morphingContent)
            .frame(width: MorphingModal.Style.panelWidth, alignment: .leading)
            .padding(MorphingModal.Style.panelPad)
            .background(panelSurface)
            .overlay(
                RoundedRectangle(cornerRadius: MorphingModal.Style.radius, style: .continuous)
                    .strokeBorder(MorphingModal.Style.panelBorder,
                                  lineWidth: MorphingModal.Style.hairline)
            )
            .shadow(color: .black.opacity(MorphingModal.Style.shadowOpacity),
                    radius: MorphingModal.Style.shadowRadius,
                    y: MorphingModal.Style.shadowY)
            // The morph: a new request resizes the panel on the spring while
            // its content cross-fades through the blur above.
            .animation(MorphingModal.Motion.panel, value: request.id)
            // Rises into place, and only rises — the scale-up that used to
            // ride along with it is what made the panel read as popping into
            // the middle of the screen rather than arriving from below.
            .offset(y: shown ? 0 : MorphingModal.Style.entryOffset)
            .opacity(shown ? 1 : MorphingModal.Style.entryOpacity)
            .blur(radius: shown ? 0 : MorphingModal.Style.blur)
            .animation(shown ? MorphingModal.Motion.panel : MorphingModal.Motion.contentOut,
                       value: shown)
            // One focus section, so a move inside the panel never beams out to
            // whatever is still mounted behind the backdrop.
            .focusSection()
    }

    /// The panel's ground. On tvOS 26 that is the system's own glass, which
    /// refracts and specularly lights whatever is behind the panel rather
    /// than merely blurring it; older systems get the closest thing SwiftUI
    /// shipped before it. Either way the surface is the OS's, not a fill of
    /// ours — which is the whole point of asking for glass.
    @ViewBuilder private var panelSurface: some View {
        let shape = RoundedRectangle(cornerRadius: MorphingModal.Style.radius, style: .continuous)
        if #available(tvOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(request.title)
                .font(MorphingModal.Style.title)
                .foregroundStyle(Theme.Colors.textStrong)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(MorphingModal.Style.message)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, MorphingModal.Style.titleGap)
            }

            if let field = request.field {
                fieldRow(field)
                    .padding(.top, MorphingModal.Style.headerGap)
            }

            if !request.options.isEmpty {
                optionList
                    .padding(.top, MorphingModal.Style.headerGap)
            }

            if let cancelTitle = request.cancelTitle {
                row(title: cancelTitle, role: .normal, selected: false,
                    focused: focus == .cancel, muted: true) { close {} }
                    .focused($focus, equals: .cancel)
                    .padding(.top, request.options.isEmpty
                        ? MorphingModal.Style.headerGap : MorphingModal.Style.cancelGap)
            }
        }
        // `.userInitiated`, not the default priority: the panel enters at
        // opacity 0, so nothing here is focusable when the engine runs its
        // first update, and by the time the entrance lands the engine has
        // already picked for itself — the last row, 取消. This states a
        // preference strong enough to override that.
        .defaultFocus($focus, initialTarget, priority: .userInitiated)
    }

    // MARK: Rows

    private var optionList: some View {
        let stack = VStack(spacing: MorphingModal.Style.rowGap) {
            ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                row(title: option.title, role: option.role, selected: option.isSelected,
                    focused: focus == .option(index), muted: false)
                {
                    let text = fieldText
                    close { option.handler(text) }
                }
                .focused($focus, equals: .option(index))
            }
        }
        // Rows are one line by contract, so the list's height is arithmetic —
        // and it has to be, because a ScrollView left to itself would claim
        // the whole screen and the panel would stop hugging its content.
        let full = CGFloat(request.options.count) * MorphingModal.Style.rowHeight
            + CGFloat(max(request.options.count - 1, 0)) * MorphingModal.Style.rowGap
        return ScrollView(showsIndicators: false) { stack }
            .frame(height: min(full, MorphingModal.Style.listMaxHeight))
    }

    /// The one row this file does not get to style through: tvOS draws a
    /// focused text field as its own white capsule, with black text, and there
    /// is no opting out. So the row yields — capsule-shaped to match what the
    /// system will draw over it, no fill of its own once focused (a rounded
    /// rect behind that capsule showed as blue corners), and dark ink while
    /// focused, without which typed text is white on white.
    private func fieldRow(_ field: MorphingModalRequest.Field) -> some View {
        let focused = focus == .field
        return TextField(field.placeholder, text: $fieldText)
            .font(MorphingModal.Style.row)
            .foregroundStyle(focused ? MorphingModal.Style.fieldFocusInk : Theme.Colors.textDefault)
            .autocorrectionDisabled()
            .textFieldStyle(.plain)
            .padding(.horizontal, MorphingModal.Style.rowPadH)
            .frame(height: MorphingModal.Style.rowHeight)
            .background(Capsule().fill(focused ? Color.clear : MorphingModal.Style.rowFill))
            .focused($focus, equals: .field)
    }

    private func row(title: String, role: MorphingModalRequest.Option.Role,
                     selected: Bool, focused: Bool, muted: Bool,
                     action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: MorphingModal.Style.rowGap) {
                Text(title)
                    .font(MorphingModal.Style.row)
                    .foregroundStyle(ink(role: role, focused: focused, muted: muted))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14 * Theme.scale, weight: .semibold))
                        .foregroundStyle(ink(role: role, focused: focused, muted: false))
                }
            }
            .padding(.horizontal, MorphingModal.Style.rowPadH)
            .frame(maxWidth: .infinity)
            .frame(height: MorphingModal.Style.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: MorphingModal.Style.rowRadius, style: .continuous)
                    .fill(fill(role: role, focused: focused, muted: muted))
            )
        }
        .buttonStyle(FlatButtonStyle())
    }

    private func ink(role: MorphingModalRequest.Option.Role, focused: Bool, muted: Bool) -> Color {
        if focused {
            return role == .destructive
                ? MorphingModal.Style.dangerInk : MorphingModal.Style.rowFocusInk
        }
        if role == .destructive { return Theme.Colors.danger }
        return muted ? Theme.Colors.textMuted : Theme.Colors.textDefault
    }

    private func fill(role: MorphingModalRequest.Option.Role, focused: Bool, muted: Bool) -> Color {
        guard focused else {
            return muted ? MorphingModal.Style.rowMutedFill : MorphingModal.Style.rowFill
        }
        return role == .destructive
            ? MorphingModal.Style.dangerFill : MorphingModal.Style.rowFocusFill
    }

    // MARK: Behaviour

    /// Land on the value the setting already holds — a picker opened by
    /// mistake should close on the same value it opened with.
    private var initialTarget: Target {
        if request.field != nil { return .field }
        if let index = request.options.firstIndex(where: { $0.isSelected }) { return .option(index) }
        if !request.options.isEmpty { return .option(0) }
        return .cancel
    }

    /// Say where focus belongs, repeatedly, for as long as the entrance lasts.
    /// See `Motion.focusClaims` for why once is not enough.
    private func claimFocus() {
        for delay in MorphingModal.Motion.focusClaims {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard shown, focus != initialTarget else { return }
                focus = initialTarget
            }
        }
    }

    private func close(_ work: @escaping () -> Void) {
        guard shown else { return }
        shown = false
        onClose(work)
    }
}

/// tvOS's own button styles bring a lift, a halo and a scale. Rows here state
/// focus with fill alone, the way the settings screen behind them does.
private struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// beui's blur cross-fade, as a transition: content arrives and leaves with a
/// small drift and a 4px blur, which is what keeps a resize reading as one
/// panel re-forming.
private struct ContentPhase: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? MorphingModal.Style.contentDrift : 0)
            .blur(radius: hidden ? MorphingModal.Style.blur : 0)
    }
}

extension AnyTransition {
    fileprivate static var morphingContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: ContentPhase(hidden: true),
                                 identity: ContentPhase(hidden: false))
                .animation(MorphingModal.Motion.contentIn),
            removal: .modifier(active: ContentPhase(hidden: true),
                               identity: ContentPhase(hidden: false))
                .animation(MorphingModal.Motion.contentOut)
        )
    }
}

// MARK: - UIKit presentation

/// Hosts the panel over whatever presented it. Presented un-animated on
/// purpose: the panel and its backdrop run their own entrance, and UIKit's
/// cross-dissolve on top would fade the blur in twice.
final class MorphingModalController: UIViewController {
    @discardableResult
    static func present(_ request: MorphingModalRequest,
                        from presenter: UIViewController) -> MorphingModalController
    {
        let modal = MorphingModalController(request: request)
        presenter.present(modal, animated: false)
        return modal
    }

    private let request: MorphingModalRequest

    init(request: MorphingModalRequest) {
        self.request = request
        super.init(nibName: nil, bundle: nil)
        // Over, not instead of: the backdrop blurs the screen behind it, which
        // only exists to be sampled if UIKit keeps it mounted.
        modalPresentationStyle = .overFullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let root = MorphingModalView(request: request) { [weak self] work in
            guard let self else { return }
            // Let the exit animation play, then leave, then act — the order
            // `UIAlertController` uses and callers already rely on.
            DispatchQueue.main.asyncAfter(deadline: .now() + MorphingModal.Motion.exitDuration) {
                self.dismiss(animated: false) { work() }
            }
        }

        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.makeConstraintsToBindToSuperview()
        hosting.didMove(toParent: self)
    }
}

extension UIViewController {
    /// The app's modal, from any UIKit screen.
    func presentModal(_ request: MorphingModalRequest) {
        MorphingModalController.present(request, from: self)
    }

    /// A notice with one way out.
    func presentModalNotice(title: String, message: String? = nil,
                            dismissTitle: String = "OK",
                            onDismiss: @escaping () -> Void = {})
    {
        presentModal(.notice(title: title, message: message,
                             dismissTitle: dismissTitle, onDismiss: onDismiss))
    }

    /// One-of-N.
    func presentModalPicker(title: String, message: String? = nil,
                            titles: [String], selected: Int?,
                            select: @escaping (Int) -> Void)
    {
        presentModal(.picker(title: title, message: message,
                             titles: titles, selected: selected, select: select))
    }
}

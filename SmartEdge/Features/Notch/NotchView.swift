import SwiftUI
import Combine
import EventKit
import CoreBluetooth

struct NotchView: View {
    @StateObject private var viewModel: NotchViewModel
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var isHovering = false
    /// Brief opacity/scale pulse that fires when the notch swaps content
    /// (music → pomodoro, notification arrives, etc). Gives the user
    /// confirmation that the underlying state actually changed instead
    /// of leaving them wondering whether their action did anything.
    @State private var actionPulse: Double = 0.0


    /// The accent color reflecting the current "mode" of the notch.
    /// Highest priority: drop target → hover → pomodoro phase → default.
    private var themeAccent: Color? {
        if isDropTargeted { return .accentColor }
        if isHovering { return .white }
        return viewModel.pomodoroThemeAccent
    }

    // Border only shows during a drag-and-drop receive, as visual feedback
    // that the notch is the drop target. Idle / hover / theme-accent states
    // get NO border so the box reads as a seamless extension of the
    // hardware camera notch — matching the user request to eliminate the
    // pale outline that otherwise gave the overlay a "card" feel.
    private var borderColor: Color {
        isDropTargeted ? (themeAccent ?? NotchTheme.dropTargetBorder) : .clear
    }

    private var borderWidth: CGFloat {
        isDropTargeted ? NotchTheme.dropTargetBorderWidth : NotchTheme.idleBorderWidth
    }

    // Shadow is always a dark drop shadow — never white or themed.
    // A bright shadow on a black box reads as a glowing rim, which the user
    // perceived as a white border. Keeping it black means the box appears
    // to be physically attached to the screen bezel rather than floating
    // over it, which is the look we want.
    private var shadowColor: Color {
        Color.black.opacity(NotchTheme.shadowOpacity(
            isDark: colorScheme == .dark,
            isDropping: isDropTargeted
        ))
    }

    private var shadowRadius: CGFloat {
        if isDropTargeted { return NotchTheme.shadowRadiusDrop }
        if isHovering { return NotchTheme.shadowRadiusHover }
        if themeAccent != nil { return NotchTheme.shadowRadiusThemed }
        return NotchTheme.shadowRadiusIdle
    }

    /// Hardware camera notch inset used to keep expanded content from
    /// being clipped by the camera cutout. We read the live screen's
    /// `safeAreaInsets.top` (macOS 12+) which is the OS's own measurement
    /// of the notch height, then add a small buffer because the OS value
    /// is pixel-exact but the user reads "uncomfortable" when text lives
    /// right at the edge of the curve. Falls back to the static notch
    /// height baseline if no screen reports a non-zero inset (e.g. on a
    /// Mac without a notch the box still gets a small top gutter so the
    /// content doesn't hug the menu bar).
    private var hardwareNotchInset: CGFloat {
        let buffer: CGFloat = 6
        if #available(macOS 12.0, *) {
            let reported = NSScreen.screens
                .map { $0.safeAreaInsets.top }
                .max() ?? 0
            if reported > 0 { return reported + buffer }
        }
        return NotchConfiguration.default.height + buffer
    }

    /// Scale modifier. The collapsed pillow now sits *behind* the hardware
    /// notch by design (200×32 matches the camera housing exactly), so the
    /// user never sees it — and a hover scale of 1.04 would have nothing
    /// to act on. The visible hover affordance is the dramatic expand
    /// (200×32 → 480×180) triggered by `handleHover()`.
    ///
    /// We keep two scale paths:
    /// - drop-target: 1.05 nudge so a file dragged over the still-invisible
    ///   pillow gets a hint that the surface accepts drops.
    /// - actionPulse: brief +3% bump when content swaps so the user sees a
    ///   physical reaction to whatever action they just triggered.
    private var scaleAmount: CGFloat {
        if isDropTargeted { return NotchTheme.dropScale }
        return 1.0 + actionPulse
    }

    init(viewModel: NotchViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    private var contentAccessibilityLabel: String {
        switch viewModel.currentContent {
        case .collapsed: return "SmartEdge notch"
        case .musicPlayer: return "Music player"
        case .calendar: return "Calendar"
        case .shelf: return "Shelf"
        case .systemStatus: return "System status"
        case .notification(let title, _, _): return "Notification: \(title)"
        case .pomodoro: return "Focus timer"
        case .clipboardHistory: return "Clipboard history"
        case .actions: return "Quick actions"
        case .settings: return "Settings"
        }
    }

    var body: some View {
        ZStack {
            notchBackground
                .overlay(alignment: .top) {
                    // Inset the content area below the hardware camera notch
                    // when expanded. The background shape still drapes over
                    // the notch (matching boring.notch's silhouette), but the
                    // actual music/HUD/clipboard content lives entirely below
                    // it so titles and artwork are never visually clipped by
                    // the camera cutout.
                    //
                    // `NotchConfiguration.default.height` is sized to match
                    // the hardware notch, so reusing it here keeps the inset
                    // honest if the notch dimensions are ever retuned.
                    //
                    // Padding only applies in the expanded state; collapsed
                    // already fits inside the notch silhouette, so no offset
                    // is needed (and adding one would push content below the
                    // visible window).
                    contentView
                        .padding(.top, viewModel.isExpanded ? hardwareNotchInset : 0)
                        // Force dark-on-black readability for every child view.
                        // The notch background is hard-coded `Color.black` (to
                        // tonally match the hardware camera notch), so the
                        // automatic light/dark adaptation of `.primary` would
                        // render text in near-black on the light system theme
                        // and become invisible. Pinning the environment to
                        // `.dark` makes `.primary` resolve to white, `.secondary`
                        // to a readable light gray, etc. — without every leaf
                        // view having to hard-code `.white` individually.
                        .environment(\.colorScheme, .dark)
                        .foregroundColor(.white)
                }
        }
        .frame(
            width: viewModel.isExpanded ? NotchConfiguration.expanded.width : NotchConfiguration.default.width,
            height: viewModel.isExpanded ? NotchConfiguration.expanded.height : NotchConfiguration.default.height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(contentAccessibilityLabel)
        .accessibilityHint(isDropTargeted ? "Drop files to add to shelf" : "")
        .scaleEffect(scaleAmount)
        // Brightness boost applies any time the cursor is over the notch,
        // not just when collapsed — the previous gating made the effect
        // invisible because hover auto-expands instantly.
        .brightness(isHovering ? NotchTheme.hoverBrightnessBoost : 0)
        // Visual-only hover. Expansion policy lives in
        // `NotchWindowContentView` → `NotchWindowManager.handleHoverIntent`
        // because that path is anchored to an AppKit tracking area which
        // doesn't get retoggled when the SwiftUI frame interpolates during
        // the expand/collapse animation. Touching `viewModel.handleHover`
        // here was producing an expand→collapse→expand loop.
        .onHover { isHovered in
            isHovering = isHovered
        }
        // Fire a brief pulse whenever the content type changes so the user
        // gets clear visual confirmation that the action they triggered
        // (⌘⇧V for clipboard, hover for music, etc) actually landed.
        .onChange(of: viewModel.currentContent) { _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                actionPulse = NotchTheme.actionPulseDelta
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    actionPulse = 0
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        // Centralized motion language — see NotchAnimation.swift for the
        // rationale behind each curve. Keeping these as separate value
        // bindings (rather than one global animation) lets each state
        // type ride its own spring without contaminating the others.
        .animation(NotchAnimation.expand, value: viewModel.isExpanded)
        .animation(NotchAnimation.contentSwap, value: viewModel.currentContent)
        .animation(NotchAnimation.drop, value: isDropTargeted)
        .animation(NotchAnimation.hover, value: isHovering)
        .animation(NotchAnimation.theme, value: viewModel.pomodoroThemeAccent)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // Immediate visual confirmation that the drop landed. We use
        // `.fileTransfer` (not `.airdropReceiving`) because AirDrop
        // receives go through macOS' own UI, not this NotchView onDrop —
        // anything that hits here is a manual user drag. The follow-up
        // pulse from `NotchViewModel.handleShelfItemsUpdate` fires once
        // the items are persisted into the shelf service, giving the
        // user a "saved" confirmation on top of this "received" beat.
        let operation = ShelfOperation(
            type: .fileTransfer,
            fileName: providers.count == 1 ? nil : "\(providers.count) items",
            progress: nil,
            isActive: true
        )
        viewModel.forceShowContent(.shelf(operation: operation))
        return appCoordinator.shelfViewModel.handleDrop(providers: providers)
    }
    
    // MARK: - Private Views

    /// Composes the visual chrome — material fill, accent-aware border,
    /// drop shadow — over the actual notch path. Each layer reads the same
    /// `NotchShape` so they morph together as `isExpanded` changes; using
    /// the shape (rather than RoundedRectangle) is what gives the bottom
    /// corners their proper curve without the top corners poking past the
    /// menu bar.
    private var notchBackground: some View {
        // Pure black fill, no material overlay, no border by default.
        //
        // Earlier this layer stacked an `ultraThinMaterial` overlay on top
        // of the black fill for a "frosted glass" texture, but that overlay
        // shifted the rendered color to a noticeably lighter gray. Against
        // the actual hardware camera notch (which is dead black) the result
        // looked like a separate floating card rather than a seamless
        // extension of the notch. Dropping the material overlay makes the
        // box read as part of the bezel.
        //
        // The stroke is conditional on `borderWidth > 0`, which currently
        // only happens during a drop receive. `.stroke` (not `.strokeBorder`)
        // because the custom Shape doesn't conform to InsettableShape.
        NotchShape(isExpanded: viewModel.isExpanded)
            .fill(NotchTheme.notchBackground)
            .overlay(
                NotchShape(isExpanded: viewModel.isExpanded)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.currentContent {
        case .collapsed:
            EmptyView()

        case .musicPlayer:
            MusicPlayerView(viewModel: appCoordinator.musicPlayerViewModel)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))

        case .calendar:
            CalendarView(viewModel: appCoordinator.calendarViewModel)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))

        case .shelf(let operation):
            if operation.isActive {
                ShelfTransferContentView(operation: operation)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                ShelfView(viewModel: appCoordinator.shelfViewModel)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }

        case .systemStatus(let battery, let bluetooth):
            NotchSystemStatusView(battery: battery, bluetooth: bluetooth)
                .transition(.opacity)

        case .notification(let title, let body, let icon):
            NotificationContentView(title: title, message: body, icon: icon)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))

        case .pomodoro:
            PomodoroContentView(viewModel: appCoordinator.pomodoroViewModel)
                .transition(.scale.combined(with: .opacity))

        case .clipboardHistory:
            ClipboardContentView(viewModel: appCoordinator.clipboardViewModel)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))

        case .actions:
            ActionsContentView(
                pomodoro: appCoordinator.pomodoroViewModel,
                clipboard: appCoordinator.clipboardViewModel,
                onOpenClipboard: { appCoordinator.showClipboardHistory() },
                onOpenPomodoro: { appCoordinator.showPomodoro() },
                onOpenMusic: { appCoordinator.notchViewModel.forceShowContent(
                    .musicPlayer(isPlaying: false, title: nil, artist: nil)
                ) }
            )
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))

        case .settings:
            EmptyView()
        }
    }
}

// MARK: - Preview
//
// Preview uses `previewMode: true` on AppCoordinator so Xcode doesn't spawn
// a real NSStatusItem, register notification routing, or attach the menu bar
// every time the canvas re-renders. The notch view itself still gets a full
// VM and a coordinator environment so all reactive bindings work.
#Preview {
    NotchView(viewModel: NotchViewModel(
        mediaService: PreviewMockMediaService(),
        calendarService: PreviewMockCalendarService(),
        shelfService: PreviewMockShelfService(),
        batteryService: PreviewMockBatteryService(),
        bluetoothService: PreviewMockBluetoothService()
    ))
    .environmentObject(AppCoordinator(
        windowManager: ServiceContainer.shared.notchWindowManager,
        settingsService: ServiceContainer.shared.settingsService,
        mediaService: ServiceContainer.shared.mediaService,
        systemService: ServiceContainer.shared.systemService,
        previewMode: true
    ))
    .frame(width: 400, height: 120)
}

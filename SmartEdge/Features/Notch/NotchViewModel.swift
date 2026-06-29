import Foundation
import Combine
import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var isExpanded = false
    @Published private(set) var currentContent: NotchContent = .collapsed
    @Published private(set) var isVisible = true

    // Persistent status data for the always-on top strip of the expanded
    // notch. Unlike the old `.systemStatus` content (which swapped the
    // whole notch to a battery-only view), these stay continuously fresh so
    // the status bar can render above whatever content is in the middle
    // (music, etc.). Updated on every battery/bluetooth publisher tick.
    @Published private(set) var statusBattery: BatteryInfo?
    @Published private(set) var statusBluetooth: BluetoothInfo?
    /// Short clock string (e.g. "3:14") for the status bar's left side.
    /// Refreshed once a minute.
    @Published private(set) var clockText: String = ""

    /// Accent color for the notch border/shadow, mirrored from a connected
    /// pomodoro view model. nil means "use the default subtle styling".
    /// Set up via `bindPomodoroTheme(_:)` from the AppCoordinator so the view
    /// layer doesn't reach into a service.
    @Published private(set) var pomodoroThemeAccent: Color?
    
    // MARK: - Service Dependencies
    private let mediaService: MediaServiceProtocol
    private let calendarService: any CalendarServiceProtocol
    private let shelfService: any ShelfServiceProtocol
    private let batteryService: any BatteryServiceProtocol
    private let bluetoothService: any BluetoothServiceProtocol
    
    // MARK: - Private Properties
    private var contentTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let notificationCenter = NotificationCenter.default
    
    // Content management
    private var contentQueue: [NotchContentRequest] = []
    private var previousContent: NotchContent = .collapsed

    // Tracks whether the current expansion was triggered by user hover
    private var isHoverExpanded: Bool = false
    
    init(
        mediaService: MediaServiceProtocol,
        calendarService: any CalendarServiceProtocol,
        shelfService: any ShelfServiceProtocol,
        batteryService: any BatteryServiceProtocol,
        bluetoothService: any BluetoothServiceProtocol
    ) {
        self.mediaService = mediaService
        self.calendarService = calendarService
        self.shelfService = shelfService
        self.batteryService = batteryService
        self.bluetoothService = bluetoothService

        setupServiceObservers()
        loadAndObservePulseSettings()
        loadAndObserveCalendarSettings()
        startClock()
    }

    /// Drives `clockText`. Fires every 30s (cheap) so the minute rollover is
    /// never more than ~30s stale; the status bar only shows hour:minute so
    /// sub-minute precision isn't needed.
    private func startClock() {
        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateClock() }
        }
    }

    private func updateClock() {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        clockText = f.string(from: Date())
    }

    private var clockTimer: Timer?

    /// True while a focus/break session is counting down. Observed by the
    /// notch view + window manager to show a compact resting countdown bar at
    /// rest (it does NOT keep the notch fully expanded — the timer settles into
    /// a small indicator the user can glance at, and hovering still shows music).
    @Published private(set) var isPomodoroRunning = false

    /// Auto-collapse for the brief "session started" reveal.
    private var pomodoroIntroWorkItem: DispatchWorkItem?

    /// Mirrors the pomodoro view model's themeAccent into this VM so the
    /// notch view can observe a single source of truth.
    func bindPomodoroTheme(_ pomodoro: PomodoroViewModel) {
        // The combineLatest of phase + isRunning is enough to derive the
        // accent — themeAccent on PomodoroViewModel reads both.
        Publishers.CombineLatest(pomodoro.$phase, pomodoro.$isRunning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak pomodoro] _, isRunning in
                guard let self = self else { return }
                self.pomodoroThemeAccent = pomodoro?.themeAccent

                let wasRunning = self.isPomodoroRunning
                self.isPomodoroRunning = isRunning
                if isRunning, !wasRunning {
                    self.introducePomodoro()
                } else if !isRunning, wasRunning {
                    // Session ended — drop the resting bar back to a hidden notch
                    // unless the user is actively hovering.
                    self.pomodoroIntroWorkItem?.cancel()
                    if !self.isHoverExpanded {
                        self.currentContent = .collapsed
                        self.isExpanded = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Briefly expand to show the focus timer when a session starts, then settle
    /// to the compact resting countdown the notch displays while running.
    private func introducePomodoro() {
        forceShowContent(.pomodoro)
        pomodoroIntroWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.isPomodoroRunning, !self.isHoverExpanded else { return }
            if case .pomodoro = self.currentContent {
                self.currentContent = .collapsed
                self.isExpanded = false
            }
        }
        pomodoroIntroWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    deinit {
        contentTimer?.invalidate()
        clockTimer?.invalidate()
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    func toggleExpansion() {
        isExpanded.toggle()
    }
    
    func requestContent(_ content: NotchContent, source: ContentSource = .user) {
        let request = NotchContentRequest(
            content: content,
            source: source
        )
        
        processContentRequest(request)
    }
    
    func hideCurrentContent(returnToPrevious: Bool = true) {
        contentTimer?.invalidate()
        contentTimer = nil
        
        let targetContent: NotchContent = returnToPrevious ? previousContent : .collapsed

        currentContent = targetContent
        isExpanded = shouldExpand(for: targetContent)

        processNextInQueue()
    }
    
    func forceShowContent(_ content: NotchContent) {
        previousContent = currentContent

        currentContent = content
        isExpanded = shouldExpand(for: content)

        if let delay = content.autoHideDelay {
            scheduleContentHide(after: delay)
        }
    }
    
    // MARK: - AppCoordinator Compatibility Methods
    func expand(to content: NotchContent) {
        currentContent = content
        isExpanded = true

        if let delay = content.autoHideDelay {
            scheduleContentHide(after: delay)
        }
    }

    func setContent(_ content: NotchContent) {
        currentContent = content
        isExpanded = shouldExpand(for: content)

        if let delay = content.autoHideDelay {
            scheduleContentHide(after: delay)
        }
    }

    func handleHover(_ isHovered: Bool) {
        // Direct state mutation — bypassing `requestContent` / queue /
        // `hideCurrentContent` because those paths run an auto-hide timer
        // and re-evaluate `processNextInQueue()` which was leaving the
        // notch stuck in `.musicPlayer` even after the cursor left. For a
        // hover gesture (which is a 1:1 visible reaction) we want
        // deterministic show / hide with nothing else fighting it.
        if isHovered {
            // Cancel any pending auto-hide from previous content swaps —
            // otherwise a timer scheduled by an earlier `forceShowContent`
            // could collapse the notch mid-hover.
            contentTimer?.invalidate()
            contentTimer = nil

            isHoverExpanded = true
            previousContent = currentContent
            currentContent = preferredContentForHover()
            isExpanded = true
        } else {
            guard isHoverExpanded else { return }
            isHoverExpanded = false
            contentTimer?.invalidate()
            contentTimer = nil
            // Collapse on hover-exit. If a pomodoro session is running, the
            // collapsed state renders the compact resting countdown (driven by
            // `isPomodoroRunning` in the view), not an empty notch.
            currentContent = .collapsed
            isExpanded = false
        }
    }

    private func preferredContentForHover() -> NotchContent {
        // If the focus timer panel is open (e.g. just shown from the menu),
        // keep it on hover so its play / skip controls stay reachable instead
        // of flipping to music. A *running* session rests as the compact
        // countdown (currentContent == .collapsed), so hovering then correctly
        // falls through to music below.
        if case .pomodoro = currentContent { return .pomodoro }

        // If the system reports a currently-loaded track (paused OR
        // playing — we don't care, the user wants to see it), prefer
        // that. Falling back to a placeholder "no metadata" musicPlayer
        // was confusing because the user's actually-playing track was
        // already in mediaService — we just weren't reading it here.
        if let track = mediaService.currentNowPlaying,
           (track.title?.isEmpty == false) || (track.artist?.isEmpty == false) {
            return .musicPlayer(
                isPlaying: track.playbackState == .playing,
                title: track.title,
                artist: track.artist
            )
        }
        return .musicPlayer(isPlaying: false, title: nil, artist: nil)
    }

    // MARK: - Private Methods

    /// Loads the current pulse preference values from UserDefaults into
    /// stored properties and subscribes to future changes via KVO-backed
    /// Combine publishers. This is O(1) on every media event instead of
    /// performing plist I/O on every call.
    private func loadAndObservePulseSettings() {
        // Read initial values.
        let storedEnabled = UserDefaults.standard.object(forKey: SettingsKeys.notchPulseOnTrackChange) as? Bool
        pulseEnabled = storedEnabled ?? true

        let storedDuration = UserDefaults.standard.double(forKey: SettingsKeys.notchPulseDurationSeconds)
        pulseDuration = storedDuration > 0 ? min(max(storedDuration, 1.0), 10.0) : 4.0

        // React to changes in Settings without requiring an app restart.
        UserDefaults.standard
            .publisher(for: \.notchPulseOnTrackChangeRaw)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Re-read via object(forKey:) to distinguish "absent"
                // (→ default ON) from "explicitly set to false".
                let stored = UserDefaults.standard.object(
                    forKey: SettingsKeys.notchPulseOnTrackChange) as? Bool
                self?.pulseEnabled = stored ?? true
            }
            .store(in: &cancellables)

        UserDefaults.standard
            .publisher(for: \.notchPulseDurationSeconds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                let clamped = value > 0 ? min(max(value, 1.0), 10.0) : 4.0
                self?.pulseDuration = clamped
            }
            .store(in: &cancellables)
    }

    /// Same pattern as `loadAndObservePulseSettings`. See its comment for
    /// the rationale (cached values, KVO-backed Combine bridge to dodge
    /// per-event plist I/O).
    private func loadAndObserveCalendarSettings() {
        // Initial read with sane defaults — `object(forKey:)` is used for
        // the Bool reads so absent-key (first launch) maps to a default
        // instead of `false`.
        let storedShow = UserDefaults.standard.object(forKey: SettingsKeys.showUpcomingEvents) as? Bool
        calendarShowUpcomingEnabled = storedShow ?? true

        let storedAllDay = UserDefaults.standard.object(forKey: SettingsKeys.showAllDayEvents) as? Bool
        calendarShowAllDayEnabled = storedAllDay ?? false

        // CalendarSettingsPanel's slider is hours, 1...168 (1h to 1wk).
        // Same range here so panel UI and notch behavior agree. Default
        // 1h matches the original hardcoded value.
        let storedLookAhead = UserDefaults.standard.double(forKey: SettingsKeys.eventLookAhead)
        calendarLookAheadHours = storedLookAhead > 0 ? min(max(storedLookAhead, 1), 168) : 1

        // Reactive updates: settings panel writes through @AppStorage, we
        // pick the changes up via KVO without forcing the user to relaunch.
        UserDefaults.standard
            .publisher(for: \.calendarShowUpcomingRaw)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let stored = UserDefaults.standard.object(forKey: SettingsKeys.showUpcomingEvents) as? Bool
                self?.calendarShowUpcomingEnabled = stored ?? true
            }
            .store(in: &cancellables)

        UserDefaults.standard
            .publisher(for: \.calendarShowAllDayRaw)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let stored = UserDefaults.standard.object(forKey: SettingsKeys.showAllDayEvents) as? Bool
                self?.calendarShowAllDayEnabled = stored ?? false
            }
            .store(in: &cancellables)

        UserDefaults.standard
            .publisher(for: \.calendarLookAheadHours)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.calendarLookAheadHours = value > 0 ? min(max(value, 1), 168) : 1
            }
            .store(in: &cancellables)
    }

    private func setupServiceObservers() {
        // Media Service
        mediaService.currentTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mediaInfo in
                self?.handleMediaUpdate(mediaInfo)
            }
            .store(in: &cancellables)

        // Calendar Service
        // `upcomingEventsPublisher` was added in the Calendar sprint; before
        // that this block was a `TODO: ...` comment and `handleCalendarEvents`
        // was dead. Now every CalendarService refresh (5-min timer +
        // EKEventStoreChanged + on-grant) flows into the notch policy.
        calendarService.upcomingEventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.handleCalendarEvents(events)
            }
            .store(in: &cancellables)

        // Shelf Service — diff-based pulse trigger
        // The notch surfaces a brief shelf preview whenever an item is *added*
        // to the shelf (drop, clipboard capture, programmatic add). Removal
        // and no-change ticks are silenced because the user already saw the
        // item when it landed; popping the notch on every refresh would be
        // noise. `.scan` carries the previous snapshot through so we can
        // detect "what's new" without external state.
        shelfService.shelfItemsPublisher
            .receive(on: DispatchQueue.main)
            .scan(([ShelfItem](), [ShelfItem]())) { acc, next in (acc.1, next) }
            .sink { [weak self] previous, current in
                self?.handleShelfItemsUpdate(previous: previous, current: current)
            }
            .store(in: &cancellables)

        // Battery Service
        batteryService.batteryInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] batteryInfo in
                self?.handleBatteryUpdate(batteryInfo)
            }
            .store(in: &cancellables)
        
        // Bluetooth Service
        bluetoothService.connectedDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.handleBluetoothUpdate(devices)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Service Event Handlers

    private func handleMediaUpdate(_ mediaInfo: NowPlayingInfo?) {
        // We used to gate on `playbackState == .playing` here, which meant
        // a paused track (or one where the helper hadn't surfaced a
        // playing-flag yet) would leave the notch collapsed — even when
        // the user hovered, because the content type drives the bloom.
        // For the boring.notch UX the user asked for the rule is simpler:
        // *any* track metadata, playing or paused, is reason to keep the
        // music player as the current content. The notch still stays
        // collapsed at rest (handleHover does the bloom).
        guard let media = mediaInfo,
              (media.title?.isEmpty == false) || (media.artist?.isEmpty == false) else {
            if case .musicPlayer = currentContent {
                requestContent(.collapsed, source: .service)
            }
            lastSeenTrackKey = nil
            return
        }
        let content = NotchContent.musicPlayer(
            isPlaying: media.playbackState == .playing,
            title: media.title,
            artist: media.artist
        )
        if isHoverExpanded {
            // While the user is actively looking at the notch, just keep
            // the displayed metadata in sync — no pulse logic, no
            // auto-collapse. They'll close it themselves by moving the
            // cursor off the notch.
            requestContent(content, source: .service)
            lastSeenTrackKey = "\(media.title ?? "")|\(media.artist ?? "")"
            lastSeenPlayingState = media.playbackState == .playing
            return
        }

        // Not hovering. We deliberately do NOT call requestContent here
        // because that would silently leave the notch expanded with the
        // music player content until a hover gesture or another event
        // tore it down — exactly the "stays open until I click" behavior
        // the user reported. Anything visible from here on out goes
        // through `pulseForTrackChange`, which schedules its own
        // auto-collapse via the pulse timer.

        // Pulse triggers. When the user isn't actively hovering, briefly
        // surface the player so they don't have to hover to see what
        // changed. Three events qualify:
        //
        //   - First track of the session (lastSeenTrackKey == nil and we
        //     now have one): a welcome blip on launch.
        //   - Track changed (different title|artist).
        //   - Same track, but playback state flipped (play → pause or
        //     pause → play). The user explicitly asked for this — the
        //     previous build kept the notch open after pressing pause
        //     because handleMediaUpdate forced the music player content
        //     into place without any auto-hide, and only a mouse click +
        //     exit would close it.
        let newKey = "\(media.title ?? "")|\(media.artist ?? "")"
        let isPlayingNow = media.playbackState == .playing
        defer {
            lastSeenTrackKey = newKey
            lastSeenPlayingState = isPlayingNow
        }
        guard !isHoverExpanded else { return }
        guard pulseEnabled else { return }
        let trackChanged = lastSeenTrackKey != nil && lastSeenTrackKey != newKey
        let firstSeen = lastSeenTrackKey == nil
        let playStateFlipped = lastSeenPlayingState != nil && lastSeenPlayingState != isPlayingNow
        if trackChanged || firstSeen || playStateFlipped {
            schedulePulse(for: content)
        }
    }

    /// Debounced entry point for the track-change pulse.
    ///
    /// A single track skip in Music.app (or via a media key) fires at least
    /// two mediaremote events in rapid succession:
    ///   1. Old track: playbackRate → 0  (play-state flip)
    ///   2. New track: full snapshot with new title/artist
    ///
    /// Without debouncing, event 1 would briefly expand the notch showing
    /// the *old* track name, then event 2 would re-arm the pulse for the
    /// correct new track — a visible flicker of the wrong title.
    ///
    /// Waiting 150 ms collapses that window: if a second event arrives
    /// within that window, the first work item is cancelled and we fire
    /// with the *latest* content only. 150 ms is imperceptible to users
    /// (~3 animation frames) but safely larger than the typical inter-event
    /// gap (~10–50 ms from mediaremote).
    private func schedulePulse(for content: NotchContent) {
        pendingPulseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPulseWorkItem = nil
            // Re-read the latest content from the service so we always
            // display the most current track, not the one captured at
            // schedule time. If nothing is playing by the time the debounce
            // fires, the guard in pulseForTrackChange handles it gracefully.
            let latest = self.buildCurrentMusicContent() ?? content
            self.pulseForTrackChange(latest)
        }
        pendingPulseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func buildCurrentMusicContent() -> NotchContent? {
        guard let track = mediaService.currentNowPlaying,
              (track.title?.isEmpty == false) || (track.artist?.isEmpty == false) else {
            return nil
        }
        return .musicPlayer(
            isPlaying: track.playbackState == .playing,
            title: track.title,
            artist: track.artist
        )
    }

    /// Briefly forces the music player on screen for `pulseDuration`
    /// seconds, then collapses back. Used to surface a track change to a
    /// user who isn't actively hovering. Re-entrant: a second pulse
    /// within the window cancels the previous timer and extends.
    ///
    /// `isPulsing` is read by `NotchWindowManager.handleHoverIntent` to
    /// ignore the spurious `mouseEntered` AppKit fires when the window
    /// grows underneath the cursor — without that gate the pulse always
    /// transitioned straight into hover mode and only collapsed when
    /// the user physically moved the mouse out of the window.
    private func pulseForTrackChange(_ content: NotchContent) {
        AppLogger.general.notice("NotchVM: track-change pulse for \(String(describing: content), privacy: .public)")
        isPulsing = true
        previousContent = currentContent
        currentContent = content
        isExpanded = true
        contentTimer?.invalidate()
        contentTimer = Timer.scheduledTimer(withTimeInterval: pulseDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endPulse()
            }
        }
    }

    /// Collapses the pulse unconditionally, regardless of whether the
    /// cursor happens to be over the notch right now. The user's
    /// next deliberate hover (which requires a fresh mouseEntered after
    /// the cursor exits and re-enters the notch frame) re-arms the
    /// normal expand path.
    private func endPulse() {
        AppLogger.general.notice("NotchVM: track-change pulse ended")
        isPulsing = false
        contentTimer = nil
        currentContent = .collapsed
        isExpanded = false
    }

    /// Cached pulse preference values. Stored properties instead of
    /// computed properties that hit UserDefaults on every `handleMediaUpdate`
    /// call — each computed access was a synchronous plist I/O on MainActor,
    /// which caused jank every time a track changed or playback state flipped.
    ///
    /// The values are refreshed once on init and again whenever the matching
    /// UserDefaults key changes (via `observePulseSettings`). Because the
    /// entire class is `@MainActor`, all mutations land on the same actor
    /// and no locking is needed.
    private var pulseEnabled: Bool = true
    private var pulseDuration: TimeInterval = 4.0

    /// Calendar UX preferences. Same caching rationale as the pulse
    /// settings above — `handleCalendarEvents` runs on every
    /// CalendarService refresh (5-min timer + EKEventStoreChanged), so
    /// re-reading UserDefaults inline would pay synchronous plist I/O
    /// on every call.
    private var calendarShowUpcomingEnabled: Bool = true
    private var calendarShowAllDayEnabled: Bool = false
    /// Hours before an event's start time at which the notch begins to
    /// surface it. Unit matches CalendarSettingsPanel's slider (1-168h,
    /// i.e. 1 hour to 1 week). Default 1h preserves the original
    /// behavior of "show events that start within the next hour".
    private var calendarLookAheadHours: TimeInterval = 1

    private(set) var isPulsing: Bool = false
    private var lastSeenTrackKey: String?
    private var lastSeenPlayingState: Bool?
    /// Pending pulse work item. Debounces rapid successive events (e.g.
    /// the "old track paused" + "new track playing" pair that mediaremote
    /// emits on every skip) so we always show the *final* state and never
    /// briefly flash the previous track's info.
    private var pendingPulseWorkItem: DispatchWorkItem?
    
    private func handleCalendarEvents(_ events: [CalendarEvent]) {
        // Calendar notch nudges are a Pro feature. Gate silently here —
        // unlike Shelf/Pomodoro (user-initiated, so they get an upsell),
        // calendar surfacing is automatic, so a locked free user simply
        // sees nothing rather than a repeated upsell every refresh.
        guard ServiceContainer.shared.storeService.isPro else { return }

        // Master toggle. User can keep the calendar service running (for
        // the Settings panel's "upcoming" list) but suppress the notch
        // pop-up.
        guard calendarShowUpcomingEnabled else { return }

        // Find the next event that:
        //   1. hasn't started yet
        //   2. isn't an all-day event (or user opted them in)
        //   3. starts within the user's look-ahead window
        let now = Date()
        let lookAheadDeadline = now.addingTimeInterval(calendarLookAheadHours * 3600)
        let candidate = events.first { event in
            guard event.startDate > now else { return false }
            if event.isAllDay && !calendarShowAllDayEnabled { return false }
            return event.startDate <= lookAheadDeadline
        }
        guard let nextEvent = candidate else {
            // No qualifying event — drop the cached id so the NEXT
            // matching event (when it eventually appears) gets shown.
            lastShownCalendarEventID = nil
            return
        }

        // Re-entrancy guard. CalendarService.refreshEvents runs on a
        // 5-minute timer plus the EKEventStoreChanged notification; without
        // this guard we'd re-pop the same event every refresh and the
        // notch would never settle. We use the event id (which is stable
        // across EventKit refreshes) instead of comparing the full struct
        // so that minor metadata changes (e.g. notes edited) don't suppress
        // a legitimate re-show after the window slipped.
        if nextEvent.id == lastShownCalendarEventID { return }
        lastShownCalendarEventID = nextEvent.id

        let content = NotchContent.calendar(event: nextEvent)
        requestContent(content, source: .service)
    }

    /// Last calendar event id surfaced on the notch. See `handleCalendarEvents`.
    private var lastShownCalendarEventID: String?
    
    /// Pulse the notch when a new item lands in the shelf. Compares the
    /// previous and current snapshots by id so a re-ordering of existing
    /// items (e.g. user manually reorders) doesn't falsely trigger a pulse.
    /// Skips on the first emission (when `previous.isEmpty && current.isEmpty`,
    /// or when `previous.isEmpty` and current is just the historical load)
    /// so we don't blast the notch on launch with every cached item.
    private func handleShelfItemsUpdate(previous: [ShelfItem], current: [ShelfItem]) {
        // Suppress the very first emission. Combine's `.scan` fires once
        // with `(empty, initial-value)` even when there's no actual user
        // action — the shelf's @Published just got its first value.
        guard !previous.isEmpty || !shelfFirstEmissionConsumed else {
            shelfFirstEmissionConsumed = true
            return
        }
        let previousIDs = Set(previous.map(\.id))
        let added = current.filter { !previousIDs.contains($0.id) }
        guard let latest = added.last else { return }

        // A local drop has already been copied into the Shelf by the time
        // this fires, so show a brief "added" confirmation (not an in-progress
        // transfer) and auto-collapse back to the prior content after 2s —
        // `.shelf` has no autoHideDelay of its own (in-progress AirDrop must
        // persist until done), so the completed toast schedules its own hide.
        let label = added.count > 1 ? "\(added.count) files" : latest.name
        let operation = ShelfOperation(
            type: .fileAdded,
            fileName: label,
            progress: nil,
            isActive: false
        )
        let content = NotchContent.shelf(operation: operation)
        requestContent(content, source: .service)
        scheduleContentHide(after: 2.0)
    }

    /// `.scan` guard — see `handleShelfItemsUpdate`. Plain Bool because
    /// the entire VM is @MainActor-isolated.
    private var shelfFirstEmissionConsumed = false

    private func handleShelfOperation(_ operation: ShelfOperationStatus) {
        let shelfOp = ShelfOperation(
            type: operation.type,
            fileName: operation.fileName,
            progress: operation.progress,
            isActive: operation.isActive
        )
        
        if operation.isActive {
            let content = NotchContent.shelf(operation: shelfOp)
            requestContent(content, source: .service)
        } else {
            hideCurrentContent()
        }
    }
    
    private func handleBatteryUpdate(_ batteryInfo: BatteryInfo) {
        // User-configurable low-battery threshold (0-100 in settings,
        // 0..1 normalized in BatteryInfo). Default 20% matches macOS's
        // own "Low Battery" notification threshold so the notch alerts
        // line up with the system tray.
        let thresholdPct = UserDefaults.standard.double(forKey: SettingsKeys.batteryLowThreshold)
        let threshold = thresholdPct > 0 ? thresholdPct / 100.0 : 0.20

        // Master toggle: keep monitoring (for menu bar / settings display)
        // but suppress the notch top-bar battery item if the user opts out.
        let showBattery = UserDefaults.standard.object(forKey: SettingsKeys.showBatteryStatus) as? Bool ?? true

        // Always refresh the persistent top-bar data (when enabled) so the
        // status strip stays live regardless of what's in the notch middle.
        statusBattery = showBattery ? batteryInfo : nil

        guard showBattery else {
            previousBatteryInfo = batteryInfo
            return
        }

        let crossedLowThreshold = batteryInfo.level < threshold
            && (previousBatteryInfo?.level ?? 1.0) >= threshold
        let chargingStateFlipped = batteryInfo.isCharging != previousBatteryInfo?.isCharging
            && previousBatteryInfo != nil  // suppress on first emission

        // Low battery / charging change briefly expands the notch so the
        // top status bar becomes visible (the bar renders over whatever's
        // already in the middle, or nothing if idle).
        if crossedLowThreshold || chargingStateFlipped {
            pulseStatusBar()
        }
        previousBatteryInfo = batteryInfo
    }

    private func handleBluetoothUpdate(_ devices: [BluetoothDevice]) {
        let showBluetooth = UserDefaults.standard.object(forKey: SettingsKeys.showBluetoothStatus) as? Bool ?? true

        // Always refresh persistent top-bar data.
        statusBluetooth = showBluetooth
            ? BluetoothInfo(
                connectedDevices: devices.map(\.name),
                isEnabled: bluetoothService.isBluetoothAvailable,
                activeConnections: devices.count
              )
            : nil

        guard showBluetooth else {
            previousBluetoothDeviceCount = devices.count
            return
        }
        if previousBluetoothDeviceCount >= 0 && devices.count != previousBluetoothDeviceCount {
            pulseStatusBar()
        }
        previousBluetoothDeviceCount = devices.count
    }

    /// Briefly expands the notch so the persistent top status bar is seen,
    /// without swapping the middle content. If music is showing, it stays;
    /// if the notch was collapsed, the middle is empty and only the bar
    /// shows. Auto-collapses after the standard system-status delay unless
    /// the user is hovering.
    private func pulseStatusBar() {
        guard !isHoverExpanded else { return }   // don't fight an active hover
        isExpanded = true
        contentTimer?.invalidate()
        contentTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isHoverExpanded else { return }
                self.isExpanded = false
            }
        }
    }
    
    // MARK: - Content Management
    
    private func processContentRequest(_ request: NotchContentRequest) {
        // High priority content interrupts immediately
        if request.content.priority >= NotchContentPriority.shelf {
            forceShowContent(request.content)
            return
        }
        
        // Lower priority content queues or replaces similar priority
        if request.content.priority >= currentContent.priority {
            previousContent = currentContent

            currentContent = request.content
            isExpanded = shouldExpand(for: request.content)

            if let delay = request.content.autoHideDelay {
                scheduleContentHide(after: delay)
            }
        } else {
            // Queue for later
            contentQueue.append(request)
            contentQueue.sort { $0.content.priority > $1.content.priority }
        }
    }
    
    private func processNextInQueue() {
        guard !contentQueue.isEmpty else { return }
        
        let nextRequest = contentQueue.removeFirst()
        processContentRequest(nextRequest)
    }
    
    private func shouldExpand(for content: NotchContent) -> Bool {
        switch content {
        case .collapsed:
            return false
        case .musicPlayer, .calendar, .shelf, .settings, .notification, .pomodoro, .clipboardHistory, .actions, .systemStatus:
            // systemStatus used to stay collapsed under the camera-notch
            // pillow, which meant low-battery and bluetooth alerts surfaced
            // a content change the user couldn't see. Now it expands like
            // the other transient notifications; the 3s autoHideDelay
            // collapses it again so the notch returns to whatever was
            // showing before.
            return true
        }
    }
    
    // `showSystemStatus()` (which swapped the whole notch to a battery-only
    // content) was removed — system status now lives in the persistent
    // `NotchStatusBar` at the top of the expanded notch, and low-battery /
    // bluetooth events call `pulseStatusBar()` to briefly reveal it.

    private func scheduleContentHide(after delay: TimeInterval) {
        contentTimer?.invalidate()
        contentTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideCurrentContent()
            }
        }
    }
    
    // MARK: - State Tracking
    private var previousBatteryInfo: BatteryInfo?
    /// Sentinel -1 means "no prior emission seen" — see
    /// `handleBluetoothUpdate` for why we suppress the first delta.
    private var previousBluetoothDeviceCount: Int = -1
}

// MARK: - UserDefaults KVO bridge for pulse settings
//
// `UserDefaults.publisher(for:)` requires an @objc dynamic property whose
// name matches the UserDefaults key exactly. These two properties let us
// use Combine to observe changes to the pulse preferences without polling.
private extension UserDefaults {
    /// KVO bridge. Returns true when the user has explicitly set the value
    /// to true, and also when the key is absent (first-run default = ON).
    /// `Bool?` isn't ObjC-representable, so we use a String-keyed raw read
    /// in the observer instead — the `@objc dynamic` property here is only
    /// needed to make `.publisher(for:)` compile.
    @objc dynamic var notchPulseDurationSeconds: Double {
        double(forKey: SettingsKeys.notchPulseDurationSeconds)
    }
    @objc dynamic var notchPulseOnTrackChangeRaw: Bool {
        // Falls back to false when absent; the Combine sink corrects for
        // the absent-key case by reading via `object(forKey:) as? Bool`.
        bool(forKey: SettingsKeys.notchPulseOnTrackChange)
    }
    /// Calendar UX preferences. Same Bool-as-Raw shape as the pulse keys:
    /// the @objc property just needs to exist to make KVO compile; the
    /// Combine sink re-reads the original key via `object(forKey:)` to
    /// distinguish absent-vs-false.
    @objc dynamic var calendarShowUpcomingRaw: Bool {
        bool(forKey: SettingsKeys.showUpcomingEvents)
    }
    @objc dynamic var calendarShowAllDayRaw: Bool {
        bool(forKey: SettingsKeys.showAllDayEvents)
    }
    @objc dynamic var calendarLookAheadHours: Double {
        double(forKey: SettingsKeys.eventLookAhead)
    }
}

// MARK: - Supporting Types
// ContentSource is defined in NotchModels.swift

// MARK: - Placeholder types for compilation
// These should match the actual service protocols when they're implemented

struct MediaInfo {
    let isPlaying: Bool
    let title: String?
    let artist: String?
}

struct ShelfOperationStatus {
    let type: ShelfOperation.ShelfOperationType
    let fileName: String?
    let progress: Double?
    let isActive: Bool
}


// MARK: - Service Protocols
// All service protocols are now defined in their respective protocol files in Core/Protocols/
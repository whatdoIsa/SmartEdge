import SwiftUI
import AppKit

@main
struct SmartEdgeApp: App {

    // Without the adaptor, the AppDelegate is never attached and our URL
    // scheme handler never fires. AppDelegate also owns the
    // applicationShouldTerminateAfterLastWindowClosed override that keeps
    // the menu-bar app running with no visible window.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var serviceContainer = ServiceContainer.shared
    @StateObject private var appCoordinator: AppCoordinator

    @State private var initializationError: Error?
    
    init() {
        // Initialize AppCoordinator with proper dependencies
        let coordinator = AppCoordinator(
            windowManager: ServiceContainer.shared.notchWindowManager,
            settingsService: ServiceContainer.shared.settingsService,
            mediaService: ServiceContainer.shared.mediaService,
            systemService: ServiceContainer.shared.systemService
        )
        _appCoordinator = StateObject(wrappedValue: coordinator)
    }
    
    var body: some Scene {
        // Settings scene is now a thin redirect: when SwiftUI's `Settings { }`
        // scene activates (typically via ⌘, on macOS builds where the
        // `showSettingsWindow:` selector still resolves), we forward to
        // `AppCoordinator.showSettings()` — which routes through
        // `NotchWindowManager.showSettingsWindow()`, the single source of
        // truth for the Settings UI — and immediately close the
        // SwiftUI-spawned placeholder window so the user only ever sees the
        // canonical NSWindow.
        //
        // Previously this scene hosted its own `SettingsView` tree with its
        // own `@StateObject SettingsViewModel`, parallel to the one in
        // NotchWindowManager. That meant two independent VMs could diverge
        // under @AppStorage re-publish ordering. Funneling everything
        // through one path eliminates that drift.
        //
        // App initialization (`initializeApp`) used to live in the scene's
        // `.task` modifier because the Settings scene was the app's only
        // SwiftUI entry point. It's now wired to the redirect-helper view
        // below so initialization still fires exactly once on first launch,
        // independent of whether the user ever opens Settings.
        Settings {
            SettingsRedirector(
                appCoordinator: appCoordinator,
                initialize: initializeApp
            )
        }
    }

    /// Empty SwiftUI view that, when SwiftUI tries to mount it inside the
    /// Settings scene window, asks AppCoordinator to surface the canonical
    /// settings NSWindow and then closes the SwiftUI-spawned shell. Also
    /// kicks off app initialization on first appearance — moved here so we
    /// retain the historical "init runs once SwiftUI is alive" guarantee
    /// without requiring the Settings scene to actually own any UI.
    private struct SettingsRedirector: View {
        let appCoordinator: AppCoordinator
        let initialize: () async -> Void
        @State private var initialized = false
        /// Captured reference to THIS redirector's own hosting window so we
        /// close exactly it — never `NSApp.keyWindow`, which by the time the
        /// deferred close runs could be a different window (e.g. the user
        /// clicked away, or the notch settings NSWindow we just surfaced).
        @State private var ownWindow: NSWindow?

        var body: some View {
            // 1x1 invisible host. Real Settings UI lives in NotchWindowManager.
            Color.clear
                .frame(width: 1, height: 1)
                .background(WindowAccessor { ownWindow = $0 })
                .task {
                    if !initialized {
                        initialized = true
                        await initialize()
                    }
                    // Defer the close-and-forward by one runloop tick so
                    // SwiftUI has finished attaching this view's window
                    // — closing too early can race the scene-mount and
                    // leave a stuck empty window.
                    DispatchQueue.main.async {
                        ownWindow?.close()
                        appCoordinator.showSettings()
                    }
                }
        }
    }

    /// Bridges up the NSWindow hosting a SwiftUI view. Used by
    /// SettingsRedirector to close its own placeholder window precisely.
    private struct WindowAccessor: NSViewRepresentable {
        let onResolve: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            // `view.window` isn't set until the view is in the hierarchy;
            // defer one runloop so SwiftUI has attached it.
            DispatchQueue.main.async { [weak view] in
                onResolve(view?.window)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    
    @MainActor
    private func initializeApp() async {
        appCoordinator.start()
        await serviceContainer.startSystemMonitoring()
    }
}

// MARK: - Content Views

// ContentView was a leftover scaffold from the initial project template —
// never referenced. The Settings scene uses LoadingView / SettingsView /
// ErrorView directly. Removed.

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            
            Text("Initializing SmartEdge...")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Setting up media services and notch overlay")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 250, height: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}


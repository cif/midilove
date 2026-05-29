import AppKit
import SwiftUI
import MidiloveCore

// SPM executable entry: build the SwiftUI scene by hand on top of AppKit
// instead of using `@main App {}`. The `App` protocol assumes a properly
// bundled `.app` with Info.plist; when launched via `swift run` it often
// fails to surface the window. Doing it explicitly works every time.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = ContentView().environmentObject(state)
        let hosting = NSHostingController(rootView: root)
        // Without this, NSHostingController shrinks the window down to the
        // SwiftUI content's intrinsic size every layout pass, ignoring
        // whatever we set on the NSWindow.
        hosting.sizingOptions = []

        // Open near-full-screen by default — there's a lot of dense control
        // info to show and the small default felt cramped.
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1500, height: 950)
        let size = NSSize(
            width: min(1700, screen.width * 0.9),
            height: min(1050, screen.height * 0.9)
        )

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "midilove"
        window.contentViewController = hosting
        window.setContentSize(size) // explicit, post-hosting, just in case
        window.center()
        // Bumping autosave key invalidates the previously-saved tiny frame
        // so the new default actually takes effect on this launch.
        window.setFrameAutosaveName("midilove.mainWindow.v3")
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
        state.start()
        installSpacebarSustainShortcut()
    }

    /// Spacebar → sustain pedal. Lets us keep playing while the physical
    /// pedal situation is being debugged.
    private func installSpacebarSustainShortcut() {
        let spaceKey: UInt16 = 49
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == spaceKey, let self else { return event }
            // Ignore key repeats so we don't spam CC-down events while held.
            if event.type == .keyDown, event.isARepeat { return nil }
            self.state.simulateSustain(down: event.type == .keyDown)
            return nil // consume — don't insert a space into focused text field
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

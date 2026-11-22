import Cocoa
import FlutterMacOS

/// Started by the launch agent to sync with no window: see
/// dev.laneholloway.geas.sync.plist and lib/state/desktop_background.dart.
let isBackgroundSync = CommandLine.arguments.contains("--background-sync")

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // No Dock icon, no menu bar and no window for a background sync.
    if isBackgroundSync {
      NSApp.setActivationPolicy(.prohibited)
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !isBackgroundSync
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

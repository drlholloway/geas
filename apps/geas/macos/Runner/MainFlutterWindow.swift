import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Hand the command line to Dart's main(), which looks for
    // --background-sync.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerBackgroundChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    if isBackgroundSync {
      self.orderOut(nil)
    }
  }

  /// Lets Dart turn the bundled launch agent on and off. `set` takes
  /// whether it should be on and returns whether it now is; `status`
  /// returns whether it is.
  private func registerBackgroundChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "dev.laneholloway.geas/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(FlutterError(
          code: "unsupported", message: "Needs macOS 13 or later.", details: nil))
        return
      }
      let agent = SMAppService.agent(plistName: "dev.laneholloway.geas.sync.plist")
      switch call.method {
      case "status":
        result(agent.status == .enabled)
      case "set":
        let on = call.arguments as? Bool ?? false
        do {
          if on {
            if agent.status != .enabled { try agent.register() }
          } else if agent.status == .enabled || agent.status == .requiresApproval {
            try agent.unregister()
          }
          result(agent.status == .enabled)
        } catch {
          result(FlutterError(
            code: "failed", message: error.localizedDescription,
            details: "status \(agent.status.rawValue)"))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = "Cadillac Packager"
    self.minSize = NSSize(width: 1180, height: 760)

    let preferredSize = NSSize(width: 1440, height: 900)
    if let screen = self.screen ?? NSScreen.main {
      let visibleFrame = screen.visibleFrame
      let windowSize = NSSize(
        width: min(preferredSize.width, visibleFrame.width - 48),
        height: min(preferredSize.height, visibleFrame.height - 48)
      )
      let origin = NSPoint(
        x: visibleFrame.midX - windowSize.width / 2,
        y: visibleFrame.midY - windowSize.height / 2
      )
      self.setFrame(NSRect(origin: origin, size: windowSize), display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Comfortable default size; the window can still shrink to phone width.
    self.setContentSize(NSSize(width: 1180, height: 780))
    self.minSize = NSSize(width: 380, height: 560)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var startupCover: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.backgroundColor = NSColor(
      calibratedRed: 0.973,
      green: 0.980,
      blue: 0.988,
      alpha: 1.0
    )
    self.alphaValue = 0.01
    self.isOpaque = true
    self.contentViewController = flutterViewController
    // Configure geometry before the nib makes the window visible.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.animationBehavior = .none
    self.setContentSize(NSSize(width: 1300, height: 720))
    self.minSize = NSSize(width: 800, height: 500)
    self.center()
    self.contentView?.wantsLayer = true
    self.contentView?.layer?.backgroundColor = self.backgroundColor.cgColor

    // Keep the unpainted Flutter surface covered until its first rasterized frame.
    let cover = NSView(frame: flutterViewController.view.bounds)
    cover.wantsLayer = true
    cover.layer?.backgroundColor = self.backgroundColor.cgColor
    cover.autoresizingMask = [.width, .height]
    flutterViewController.view.addSubview(cover)
    startupCover = cover

    let startupChannel = FlutterMethodChannel(
      name: "pdm_viewer/startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    startupChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "prepare", let argb = call.arguments as? NSNumber {
        let value = argb.uint32Value
        let color = NSColor(
          calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
          green: CGFloat((value >> 8) & 0xff) / 255,
          blue: CGFloat(value & 0xff) / 255,
          alpha: 1
        )
        self?.backgroundColor = color
        self?.contentView?.layer?.backgroundColor = color.cgColor
        self?.startupCover?.layer?.backgroundColor = color.cgColor
        result(nil)
        return
      }
      guard call.method == "firstFrameReady" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.startupCover?.removeFromSuperview()
      self?.startupCover = nil
      self?.alphaValue = 1
      self?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    let fontChannel = FlutterMethodChannel(
      name: "pdm_viewer/system_fonts",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    fontChannel.setMethodCallHandler { call, result in
      if call.method == "listFamilies" {
        result(NSFontManager.shared.availableFontFamilies.sorted())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

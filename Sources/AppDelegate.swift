import AppKit
import SpriteKit
import ServiceManagement

/// A transparent, click-through window covering one display.
final class Overlay {
    let window: NSWindow
    let view: SKView
    let scene: SnowScene

    init(screen: NSScreen) {
        let frame = screen.frame
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        view = SKView(frame: NSRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.autoresizingMask = [.width, .height]

        scene = SnowScene(size: frame.size)
        scene.scaleMode = .resizeFill
        scene.screenOrigin = frame.origin
        scene.topInset = frame.maxY - screen.visibleFrame.maxY

        window.contentView = view
        window.setFrame(frame, display: false)
        view.presentScene(scene)
    }

    func apply(_ s: Settings, asleep: Bool) {
        if s.behindWindows {
            window.level = NSWindow.Level(rawValue: -1)
        } else {
            // Above ordinary windows and the Dock, below the menu bar and menus.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        }
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if s.overFullScreen { behavior.insert(.fullScreenAuxiliary) }
        window.collectionBehavior = behavior
        window.sharingType = s.showInScreenshots ? .readOnly : .none

        if s.paused {
            view.isPaused = true
            window.orderOut(nil)
        } else {
            view.isPaused = asleep
            window.orderFrontRegardless()
        }
    }

    func close() {
        view.presentScene(nil)
        window.orderOut(nil)
        window.close()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlays: [Overlay] = []
    private var toggleItems: [NSMenuItem] = []
    private var loginItem: NSMenuItem?
    private var asleep = false
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the animation smooth while the app has no focused window.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Animating snow")

        buildMenu()
        rebuildOverlays()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(settingsChanged),
                       name: Settings.changed, object: nil)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(spaceChanged),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(wentToSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wokeUp),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(wentToSleep),
                       name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(wokeUp),
                       name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        for o in overlays { o.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0) }
        applySettings()
    }

    private func applySettings() {
        for o in overlays { o.apply(Settings.shared, asleep: asleep) }
    }

    @objc private func screensChanged() { rebuildOverlays() }
    @objc private func settingsChanged() { applySettings() }
    @objc private func spaceChanged() { for o in overlays { o.scene.forgetWindows() } }
    @objc private func wentToSleep() { asleep = true; applySettings() }
    @objc private func wokeUp() { asleep = false; applySettings() }

    // MARK: Menu

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Frostfall") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "*"
        }

        let s = Settings.shared
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(sliderItem(title: "Intensity", value: s.double(.intensity), min: 0,
                                action: #selector(intensityChanged(_:))))
        menu.addItem(sliderItem(title: "Flake Size", value: s.double(.flakeSize), min: 0,
                                action: #selector(flakeSizeChanged(_:))))
        menu.addItem(sliderItem(title: "Opacity", value: s.double(.opacity), min: 0.15,
                                action: #selector(opacityChanged(_:))))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggle("Settle on Ground", .settleOnGround))
        menu.addItem(toggle("Settle on Windows", .settleOnWindows))
        menu.addItem(toggle("Melt Snow", .melt))
        menu.addItem(action("Clear Snow", #selector(clearSnow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggle("Snow Behind Windows", .behindWindows))
        menu.addItem(toggle("Show over Full Screen", .overFullScreen))
        menu.addItem(toggle("Show in Screenshots", .showInScreenshots))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggle("Pause Snow", .paused))
        let login = action("Launch at Login", #selector(toggleLogin))
        loginItem = login
        menu.addItem(login)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Quit Frostfall", #selector(quit), key: "q"))

        item.menu = menu
        statusItem = item
        refreshMenu()
    }

    private func sliderItem(title: String, value: Double, min: Double, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 16, y: 26, width: 208, height: 16)
        let slider = NSSlider(value: value, minValue: min, maxValue: 1, target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 16, y: 4, width: 208, height: 20)
        container.addSubview(label)
        container.addSubview(slider)
        item.view = container
        return item
    }

    private func toggle(_ title: String, _ key: Settings.Key) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key.rawValue
        toggleItems.append(item)
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func refreshMenu() {
        let s = Settings.shared
        for item in toggleItems {
            guard let raw = item.representedObject as? String, let key = Settings.Key(rawValue: raw) else { continue }
            item.state = s.bool(key) ? .on : .off
        }
        loginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }

    @objc private func intensityChanged(_ sender: NSSlider) {
        Settings.shared.set(sender.doubleValue, for: .intensity)
    }

    @objc private func flakeSizeChanged(_ sender: NSSlider) {
        Settings.shared.set(sender.doubleValue, for: .flakeSize)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        Settings.shared.set(sender.doubleValue, for: .opacity)
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = Settings.Key(rawValue: raw) else { return }
        Settings.shared.set(!Settings.shared.bool(key), for: key)
        refreshMenu()
    }

    @objc private func clearSnow() {
        for o in overlays { o.scene.clearSnow() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        refreshMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

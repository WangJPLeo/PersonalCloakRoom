import AppKit
import SwiftUI

@main
enum CloakCaptureApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let studio = Studio()
    private let capture = CaptureController()
    private var bubble: NSPanel?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var screenObserver: NSObjectProtocol?
    private var capturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "tshirt", accessibilityDescription: "衣橱快截")
        status.menu = actionsMenu()
        statusItem = status
        studio.captureAction = { [weak self] in self?.takeScreenshot() }
        studio.restartAction = { [weak self] in self?.restartApplication() }
        createBubble()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionBubble() }
        }
        if CommandLine.arguments.contains("--show-studio") { showStudio() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        studio.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A floating panel counts as a visible window. Always show the studio on
        // a Finder/Launch Services reopen instead of trusting hasVisibleWindows.
        resetBubble()
        showStudio()
        return false
    }

    private func actionsMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action, key) in [
            ("截取服装", #selector(takeScreenshot), ""),
            ("打开换装窗口", #selector(showStudio), ""),
            ("查看换装记录", #selector(showHistory), ""),
            ("将悬浮按钮移回右侧", #selector(resetBubble), "")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出衣橱快截", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        appItem.submenu = actionsMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        for (title, action, key) in [
            ("撤销", Selector(("undo:")), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] { edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key)) }
        NSApp.mainMenu = main
    }

    private func createBubble() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 60, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = BubbleView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        view.toolTip = "点击框选服装 · 拖动调整位置 · 右键打开菜单"
        view.clicked = { [weak self] in self?.takeScreenshot() }
        view.menu = actionsMenu()
        panel.contentView = view
        bubble = panel
        positionBubble()
        panel.orderFrontRegardless()
    }

    private func positionBubble() {
        // NSScreen.main follows the key window and can point at a different display.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.screens.first ?? NSScreen.main, let bubble else { return }
        let rect = screen.visibleFrame.isEmpty ? screen.frame : screen.visibleFrame
        bubble.setFrameOrigin(CGPoint(x: rect.maxX - 76, y: rect.midY - 30))
    }

    @objc private func resetBubble() { positionBubble(); bubble?.orderFrontRegardless() }

    @objc func showStudio() {
        guard !capturing else { return }
        if window == nil {
            let availableHeight = (NSScreen.main?.visibleFrame.height ?? 860) - 70
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 950, height: max(650, min(790, availableHeight))),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "衣橱快截"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.085, alpha: 1)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 680)
            window.contentView = NSHostingView(rootView: StudioView(studio: studio))
            window.center()
            self.window = window
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    @objc private func showHistory() {
        showStudio()
        guard !capturing, !studio.busy, !studio.isPresentingSheet else { return }
        studio.showingHistory = true
    }

    private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] application, error in
            Task { @MainActor in
                if application != nil && error == nil {
                    NSApp.terminate(nil)
                } else {
                    self?.studio.showingCapturePermissionHelp = false
                    self?.studio.error = "无法自动重启。请从菜单退出衣橱快截，再手动打开应用。"
                }
            }
        }
    }

    @objc func takeScreenshot() {
        guard !capturing else { return }
        if studio.busy { showStudio(); return }
        // Finish any open sheet before hiding its parent window.
        if studio.isPresentingSheet { showStudio(); return }
        capturing = true
        let wasVisible = window?.isVisible == true
        bubble?.orderOut(nil)
        window?.orderOut(nil)
        Task {
            // Give WindowServer a frame to remove our UI before taking snapshots.
            try? await Task.sleep(for: .milliseconds(180))
            await capture.start { [weak self] result in
                guard let self else { return }
                self.capturing = false
                self.bubble?.orderFrontRegardless()
                switch result {
                case .success(let photo):
                    if let photo {
                        self.studio.garment = photo
                        self.studio.garmentCatalogID = nil
                        self.studio.clearResult()
                        self.studio.status = "已截取服装，请选择人物后开始换装。"
                        self.showStudio()
                    } else if wasVisible { self.showStudio() }
                case .failure(let error):
                    self.showStudio()
                    if case CaptureFailure.permissionDenied = error {
                        self.studio.showingCapturePermissionHelp = true
                    } else {
                        self.studio.error = error.localizedDescription
                    }
                }
            }
        }
    }
}

final class BubbleView: NSView {
    var clicked: (() -> Void)?
    private var mouseOrigin = CGPoint.zero
    private var windowOrigin = CGPoint.zero
    private var dragged = false

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 3, dy: 3)
        NSColor(calibratedRed: 0.1, green: 0.15, blue: 0.16, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: box, xRadius: 19, yRadius: 19).fill()
        NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.66, alpha: 0.8).setStroke()
        let border = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 19, yRadius: 19)
        border.lineWidth = 1
        border.stroke()
        let symbol = NSImage(systemSymbolName: "tshirt.fill", accessibilityDescription: "截取服装")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.init(calibratedRed: 0.57, green: 0.97, blue: 0.77, alpha: 1)])))
        symbol?.draw(in: CGRect(x: 17, y: 18, width: 26, height: 24))
        NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.66, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 41, y: 11, width: 6, height: 6)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        mouseOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - mouseOrigin.x, dy = point.y - mouseOrigin.y
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(CGPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged { clicked?(); return }
        guard let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? window.screen else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(CGPoint(x: min(max(window.frame.minX, frame.minX), frame.maxX - 60),
                                      y: min(max(window.frame.minY, frame.minY), frame.maxY - 60)))
    }
}

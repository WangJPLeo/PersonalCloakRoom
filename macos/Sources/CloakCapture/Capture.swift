import AppKit
import ScreenCaptureKit

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CaptureController {
    private var panels: [NSPanel] = []
    private var escapeMonitor: Any?
    private var completion: ((Result<Photo?, Error>) -> Void)?

    func start(completion: @escaping (Result<Photo?, Error>) -> Void) async {
        self.completion = completion
        do {
            // Let ScreenCaptureKit check/request its own authorization. CoreGraphics
            // preflight can report stale state and must never short-circuit this call.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            var snapshots: [(NSScreen, CGImage)] = []
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.frame.height * screen.backingScaleFactor)
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                snapshots.append((screen, image))
            }
            guard !snapshots.isEmpty else { throw ToolError.message("没有可截图的显示器。") }
            for (screen, image) in snapshots {
                let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.isOpaque = true
                panel.hasShadow = false
                let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screenshot: image)
                view.selected = { [weak self] rect in
                    guard let self else { return }
                    let scaleX = CGFloat(image.width) / screen.frame.width
                    let scaleY = CGFloat(image.height) / screen.frame.height
                    let pixels = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY,
                                        width: rect.width * scaleX, height: rect.height * scaleY).integral
                    do {
                        guard let crop = image.cropping(to: pixels) else { throw ToolError.message("无法截取选区。") }
                        self.finish(.success(try Photo.from(crop, name: "屏幕服装截图")))
                    } catch { self.finish(.failure(error)) }
                }
                panel.contentView = view
                panels.append(panel)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
            }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.finish(.success(nil)); return nil }
                return event
            }
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            finish(.failure(CaptureFailure.classify(error)))
        }
    }

    private func finish(_ result: Result<Photo?, Error>) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class SelectionView: NSView {
    let screenshot: CGImage
    var selected: ((CGRect) -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: CGRect, screenshot: CGImage) {
        self.screenshot = screenshot
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: screenshot, size: bounds.size).draw(in: bounds, from: .zero,
            operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.44).setFill()
        shade.fill()
        if !selection.isEmpty {
            NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.7, alpha: 1).setStroke()
            let path = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 2
            path.stroke()
        }
        let title = selection.isEmpty ? "拖动框选服装 · 松开完成 · Esc 取消" : "\(Int(selection.width)) × \(Int(selection.height)) pt · 松开完成 · Esc 取消"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: title, attributes: attrs)
        let size = text.size()
        let box = CGRect(x: (bounds.width - size.width) / 2 - 18, y: 38, width: size.width + 36, height: 44)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        text.draw(at: CGPoint(x: box.minX + 18, y: box.minY + 12))
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard selection.width >= 4, selection.height >= 4 else { anchor = nil; return }
        selected?(selection)
    }
}

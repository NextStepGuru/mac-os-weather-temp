import AppKit

@MainActor
final class LogViewerWindowController: NSWindowController {
    private static var instance: LogViewerWindowController?

    private let textView = NSTextView()

    static func show() {
        if let instance {
            instance.refresh()
            instance.window?.makeKeyAndOrderFront(nil)
        } else {
            let controller = LogViewerWindowController()
            instance = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeatherBar Logs"
        window.contentView = scrollView
        window.center()
        window.setFrameAutosaveName("WeatherBarLogViewer")

        super.init(window: window)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        textView.string = AppLogger.shared.readAll()
        textView.scrollToEndOfDocument(nil)
    }
}

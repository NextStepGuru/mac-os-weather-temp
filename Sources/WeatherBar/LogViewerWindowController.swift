import AppKit
import UniformTypeIdentifiers

@MainActor
final class LogViewerWindowController: NSWindowController {
    private static var instance: LogViewerWindowController?

    private let textView = NSTextView()
    private let copyButton = NSButton(title: "Copy All", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save As…", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

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

        for button in [copyButton, saveButton, refreshButton] {
            button.bezelStyle = .rounded
        }

        let buttonBarHeight: CGFloat = 36
        let buttonBar = NSStackView(views: [copyButton, saveButton, refreshButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 8
        buttonBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        buttonBar.frame = NSRect(x: 0, y: 0, width: 640, height: buttonBarHeight)
        buttonBar.autoresizingMask = [.width, .maxYMargin]

        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 0, y: buttonBarHeight, width: 640, height: 2)
        separator.autoresizingMask = [.width, .maxYMargin]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        scrollView.frame = NSRect(x: 0, y: buttonBarHeight + 2, width: 640, height: 400 - buttonBarHeight - 2)
        scrollView.autoresizingMask = [.width, .height]
        content.addSubview(scrollView)
        content.addSubview(separator)
        content.addSubview(buttonBar)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeatherBar Logs"
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("WeatherBarLogViewer")

        super.init(window: window)

        copyButton.target = self
        copyButton.action = #selector(copyAll)
        saveButton.target = self
        saveButton.action = #selector(saveAs)
        refreshButton.target = self
        refreshButton.action = #selector(refreshLogs)

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

    @objc private func refreshLogs() {
        refresh()
        AppLogger.shared.log("Log viewer refreshed")
    }

    @objc private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppLogger.shared.readAll(), forType: .string)
        AppLogger.shared.log("Logs copied to clipboard")
    }

    @objc private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogExporter.fileName(date: Date())
        panel.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LogExporter.write(AppLogger.shared.readAll(), to: url)
            AppLogger.shared.log("Logs saved to \(url.path)")
            refresh()
        } catch {
            AppLogger.shared.log("Saving logs failed: \(error.localizedDescription)", level: .error)
            let alert = NSAlert()
            alert.messageText = "Could not save logs"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

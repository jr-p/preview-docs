import AppKit

extension NSToolbarItem.Identifier {
    static let markdownMode = NSToolbarItem.Identifier("markdownMode")
    static let copyPath     = NSToolbarItem.Identifier("copyPath")
    static let copyContents = NSToolbarItem.Identifier("copyContents")
    static let showInFinder = NSToolbarItem.Identifier("showInFinder")
    static let refresh      = NSToolbarItem.Identifier("refresh")
}

class PreviewWindowController: NSWindowController, NSToolbarDelegate {

    let fileURL: URL
    private weak var previewVC: PreviewViewController?
    private var markdownModeControl: NSSegmentedControl?

    init(fileURL: URL) {
        dbg("[WC] init start: \(fileURL.lastPathComponent)")
        self.fileURL = fileURL

        let vc = PreviewViewController(fileURL: fileURL)
        dbg("[WC] vc created")

        dbg("[WC] creating NSWindow")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        dbg("[WC] NSWindow created")
        window.title = fileURL.lastPathComponent
        window.subtitle = fileURL.deletingLastPathComponent().path
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "PreviewDocs"
        window.minSize = NSSize(width: 480, height: 320)
        window.center()

        dbg("[WC] calling super.init")
        super.init(window: window)
        dbg("[WC] super.init done")
        self.previewVC = vc

        // Set contentViewController AFTER super.init to avoid re-entrant WKWebView init
        dbg("[WC] setting contentViewController")
        window.contentViewController = vc
        window.setContentSize(NSSize(width: 960, height: 720))
        window.center()
        dbg("[WC] contentViewController set")

        let toolbar = NSToolbar(identifier: "PreviewToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        dbg("[WC] init complete")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.markdownMode, .copyPath, .copyContents, .showInFinder, .refresh, .flexibleSpace, .space]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if previewVC?.supportsMarkdownModeToggle == true {
            return [.markdownMode, .space, .copyPath, .copyContents, .showInFinder, .flexibleSpace, .refresh]
        }
        return [.copyPath, .copyContents, .showInFinder, .flexibleSpace, .refresh]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .markdownMode:
            let control = NSSegmentedControl(labels: ["Preview", "Source"], trackingMode: .selectOne, target: self, action: #selector(changeMarkdownMode))
            control.selectedSegment = 0
            control.setWidth(76, forSegment: 0)
            control.setWidth(68, forSegment: 1)
            control.frame = NSRect(x: 0, y: 0, width: 152, height: 28)
            control.isEnabled = previewVC?.supportsMarkdownModeToggle == true
            item.label = "Markdown View"
            item.toolTip = "Switch Markdown preview/source"
            item.view = control
            markdownModeControl = control

        case .copyPath:
            item.label = "Copy Path"
            item.toolTip = "Copy file path to clipboard"
            item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy Path")
            item.action = #selector(copyPath)
            item.target = self

        case .copyContents:
            item.label = "Copy Contents"
            item.toolTip = "Copy file contents to clipboard"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Contents")
            item.action = #selector(copyContents)
            item.target = self

        case .showInFinder:
            item.label = "Show in Finder"
            item.toolTip = "Reveal file in Finder"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder")
            item.action = #selector(showInFinder)
            item.target = self

        case .refresh:
            item.label = "Refresh"
            item.toolTip = "Reload file"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.action = #selector(refresh)
            item.target = self

        default:
            return nil
        }

        return item
    }

    // MARK: - Actions

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
        flashFeedback("Path Copied")
    }

    @objc private func copyContents() {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
        flashFeedback("Contents Copied")
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @objc private func refresh() {
        previewVC?.loadFile()
    }

    @objc private func changeMarkdownMode() {
        guard let control = markdownModeControl else { return }
        previewVC?.setMarkdownViewMode(control.selectedSegment == 0 ? .preview : .source)
    }

    private func flashFeedback(_ message: String) {
        let prev = window?.title
        window?.title = "✓ \(message)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.window?.title = prev ?? ""
        }
    }
}

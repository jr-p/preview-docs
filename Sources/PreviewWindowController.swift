import AppKit

extension NSToolbarItem.Identifier {
    static let markdownMode  = NSToolbarItem.Identifier("markdownMode")
    static let copyPath      = NSToolbarItem.Identifier("copyPath")
    static let copyContents  = NSToolbarItem.Identifier("copyContents")
    static let showInFinder  = NSToolbarItem.Identifier("showInFinder")
    static let save          = NSToolbarItem.Identifier("save")
    static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
    static let revealSidebar = NSToolbarItem.Identifier("revealSidebar")
    static let refresh       = NSToolbarItem.Identifier("refresh")
}

class PreviewWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate, PreviewViewControllerDelegate, FileTreeSidebarViewControllerDelegate {

    private(set) var fileURL: URL
    private let previewVC: PreviewViewController
    private let sidebarVC: FileTreeSidebarViewController
    private let splitVC = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem?
    private var markdownModeControl: NSSegmentedControl?
    private var saveToolbarItem: NSToolbarItem?

    init(fileURL: URL, sidebarRootURL: URL? = nil) {
        dbg("[WC] init start: \(fileURL.lastPathComponent)")
        self.fileURL = fileURL
        self.previewVC = PreviewViewController(fileURL: fileURL)
        self.sidebarVC = FileTreeSidebarViewController(rootURL: sidebarRootURL ?? FileManager.default.homeDirectoryForCurrentUser)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.subtitle = fileURL.deletingLastPathComponent().path
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "PreviewDocs"
        window.minSize = NSSize(width: 640, height: 360)
        window.center()

        super.init(window: window)

        previewVC.delegate = self
        sidebarVC.delegate = self
        splitVC.splitView.isVertical = true
        splitVC.addSplitViewItem(NSSplitViewItem(viewController: previewVC))
        let sidebar = NSSplitViewItem(viewController: sidebarVC)
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 420
        sidebar.preferredThicknessFraction = 0.26
        splitVC.addSplitViewItem(sidebar)
        sidebarItem = sidebar

        window.delegate = self
        window.contentViewController = splitVC
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.center()

        let toolbar = NSToolbar(identifier: "PreviewToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        updateWindowMetadata()
        dbg("[WC] init complete")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.markdownMode, .copyPath, .copyContents, .showInFinder, .save, .toggleSidebar, .revealSidebar, .refresh, .flexibleSpace, .space]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.markdownMode, .space, .copyPath, .copyContents, .showInFinder, .save, .toggleSidebar, .revealSidebar, .flexibleSpace, .refresh]
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
            control.isEnabled = previewVC.supportsMarkdownModeToggle
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

        case .save:
            item.label = "Save"
            item.toolTip = "Save file"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.action = #selector(save)
            item.target = self
            item.isEnabled = false
            saveToolbarItem = item

        case .toggleSidebar:
            item.label = "Toggle File Tree"
            item.toolTip = "Show or hide file tree"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Sidebar")
            item.action = #selector(toggleSidebar)
            item.target = self

        case .revealSidebar:
            item.label = "Reveal in Tree"
            item.toolTip = "Reveal current file in tree"
            item.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "Reveal in Tree")
            item.action = #selector(revealInSidebar)
            item.target = self

        case .refresh:
            item.label = "Refresh Preview"
            item.toolTip = "Reload current preview"
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
        guard let contents = previewVC.currentTextContents else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
        flashFeedback("Contents Copied")
    }

    @objc private func showInFinder() {
        revealInFinder(url: fileURL)
    }

    @objc private func save() {
        if previewVC.save() {
            updateWindowMetadata()
            flashFeedback("Saved")
        }
    }

    @objc private func toggleSidebar() {
        sidebarItem?.isCollapsed.toggle()
    }

    @objc private func revealInSidebar() {
        sidebarItem?.isCollapsed = false
        sidebarVC.reveal(url: fileURL)
    }

    @objc private func refresh() {
        guard confirmDiscardOrSaveChanges() else { return }
        previewVC.loadFile()
        updateWindowMetadata()
    }

    @objc private func changeMarkdownMode() {
        guard let control = markdownModeControl else { return }
        if previewVC.hasUnsavedChanges, !confirmDiscardOrSaveChanges() {
            control.selectedSegment = 1
            return
        }
        previewVC.setMarkdownViewMode(control.selectedSegment == 0 ? .preview : .source)
        updateToolbarState()
    }

    // MARK: - PreviewViewControllerDelegate

    func previewViewControllerDidChangeFile(_ controller: PreviewViewController) {
        fileURL = controller.fileURL
        updateWindowMetadata()
        updateToolbarState()
    }

    func previewViewControllerDidChangeDirtyState(_ controller: PreviewViewController) {
        updateWindowMetadata()
        updateToolbarState()
    }

    // MARK: - Sidebar Delegate

    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, open url: URL) {
        openInCurrentWindow(url)
    }

    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, openInNewTab url: URL) {
        (NSApp.delegate as? AppDelegate)?.openFile(at: url, sidebarRootURL: controller.currentRootURL)
    }

    func fileTreeSidebarCurrentFileURL(_ controller: FileTreeSidebarViewController) -> URL? {
        return fileURL
    }

    func fileTreeSidebarCanReplaceCurrentFile(_ controller: FileTreeSidebarViewController) -> Bool {
        return confirmDiscardOrSaveChanges()
    }

    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, didRenameCurrentFileTo url: URL) {
        previewVC.open(url: url)
    }

    func fileTreeSidebarRevealInFinder(_ controller: FileTreeSidebarViewController, url: URL) {
        revealInFinder(url: url)
    }

    func fileTreeSidebarToggleVisibility(_ controller: FileTreeSidebarViewController) {
        toggleSidebar()
    }

    private func openInCurrentWindow(_ url: URL) {
        guard confirmDiscardOrSaveChanges() else { return }
        previewVC.open(url: url)
    }

    // MARK: - Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return confirmDiscardOrSaveChanges()
    }

    // MARK: - Unsaved Changes

    private func confirmDiscardOrSaveChanges() -> Bool {
        guard previewVC.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(fileURL.lastPathComponent)?"
        alert.informativeText = "Your changes will be lost if you do not save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return previewVC.save()
        case .alertSecondButtonReturn:
            previewVC.discardUnsavedChanges()
            return true
        default:
            return false
        }
    }

    // MARK: - Helpers

    private func updateWindowMetadata() {
        let dirtyPrefix = previewVC.hasUnsavedChanges ? "*" : ""
        window?.title = "\(dirtyPrefix)\(fileURL.lastPathComponent)"
        window?.subtitle = fileURL.deletingLastPathComponent().path
    }

    private func updateToolbarState() {
        saveToolbarItem?.isEnabled = previewVC.hasUnsavedChanges && previewVC.isEditableTextLoaded
        markdownModeControl?.isEnabled = previewVC.supportsMarkdownModeToggle
        if !previewVC.supportsMarkdownModeToggle {
            markdownModeControl?.selectedSegment = 0
        }
    }

    private func flashFeedback(_ message: String) {
        let prev = window?.title
        window?.title = "✓ \(message)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.updateWindowMetadata()
            if self?.window?.title.isEmpty == true {
                self?.window?.title = prev ?? ""
            }
        }
    }

    private func revealInFinder(url: URL) {
        let changedFinderSetting = ensureFinderShowsHiddenFiles()
        if changedFinderSetting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func ensureFinderShowsHiddenFiles() -> Bool {
        guard !finderShowsHiddenFiles() else { return false }
        guard setFinderShowsHiddenFiles() else { return false }
        restartFinder()
        return true
    }

    private func finderShowsHiddenFiles() -> Bool {
        guard let output = runProcess(
            executablePath: "/usr/bin/defaults",
            arguments: ["read", "com.apple.finder", "AppleShowAllFiles"]
        ) else {
            return false
        }
        return ["1", "true", "yes"].contains(output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func setFinderShowsHiddenFiles() -> Bool {
        return runProcess(
            executablePath: "/usr/bin/defaults",
            arguments: ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", "true"]
        ) != nil
    }

    private func restartFinder() {
        _ = runProcess(executablePath: "/usr/bin/killall", arguments: ["Finder"])
    }

    private func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

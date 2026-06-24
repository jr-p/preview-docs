import AppKit

protocol FileTreeSidebarViewControllerDelegate: AnyObject {
    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, open url: URL)
    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, openInNewTab url: URL)
    func fileTreeSidebarCurrentFileURL(_ controller: FileTreeSidebarViewController) -> URL?
    func fileTreeSidebarCanReplaceCurrentFile(_ controller: FileTreeSidebarViewController) -> Bool
    func fileTreeSidebar(_ controller: FileTreeSidebarViewController, didRenameCurrentFileTo url: URL)
    func fileTreeSidebarRevealInFinder(_ controller: FileTreeSidebarViewController, url: URL)
    func fileTreeSidebarToggleVisibility(_ controller: FileTreeSidebarViewController)
}

final class FileTreeNode: NSObject {
    let url: URL
    let isDirectory: Bool
    weak var parent: FileTreeNode?
    var children: [FileTreeNode]?

    init(url: URL, isDirectory: Bool, parent: FileTreeNode?) {
        self.url = url
        self.isDirectory = isDirectory
        self.parent = parent
    }

    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

final class PathComponentButton: NSButton {
    var url: URL?
}

final class IgnoreRules {
    private let defaultPatterns = [".git", "node_modules", ".build", "DerivedData", ".DS_Store", "*.app"]
    private(set) var patterns: [String] = []
    private let ignoreURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".previewdocs-ignore")

    init() {
        reload()
    }

    func reload() {
        var next = defaultPatterns
        if let content = try? String(contentsOf: ignoreURL, encoding: .utf8) {
            let userPatterns = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            next.append(contentsOf: userPatterns)
        }
        patterns = next
    }

    func ensureIgnoreFileExists() throws -> URL {
        if !FileManager.default.fileExists(atPath: ignoreURL.path) {
            let initial = """
            # PreviewDocs ignore rules
            # One filename or wildcard per line.

            """
            try initial.write(to: ignoreURL, atomically: true, encoding: .utf8)
        }
        return ignoreURL
    }

    func shouldExclude(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return patterns.contains { pattern in
            wildcardMatches(pattern: pattern, value: name)
        }
    }

    private func wildcardMatches(pattern: String, value: String) -> Bool {
        guard pattern.contains("*") else {
            return pattern == value
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        return value.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

final class FileTreeSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {

    weak var delegate: FileTreeSidebarViewControllerDelegate?

    private var rootURL = FileManager.default.homeDirectoryForCurrentUser
    private let ignoreRules = IgnoreRules()
    private var rootNode: FileTreeNode!

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let pathBarView = NSVisualEffectView()
    private let pathScrollView = NSScrollView()
    private let pathStackView = NSStackView()

    var currentRootURL: URL {
        return rootURL
    }

    convenience init(rootURL: URL) {
        self.init(nibName: nil, bundle: nil)
        self.rootURL = rootURL
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 720))
        rootNode = FileTreeNode(url: rootURL, isDirectory: true, parent: nil)
        buildLayout()
        reloadRoot()
    }

    private func buildLayout() {
        let toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 6, right: 8)

        toolbar.addArrangedSubview(iconButton("arrow.triangle.2.circlepath", tooltip: "Reload File Tree", action: #selector(refreshTree)))
        toolbar.addArrangedSubview(iconButton("doc.badge.plus", tooltip: "New File in Selected Folder", action: #selector(newFile)))
        toolbar.addArrangedSubview(iconButton("folder.badge.plus", tooltip: "New Folder in Selected Folder", action: #selector(newFolder)))
        toolbar.addArrangedSubview(iconButton("line.3.horizontal.decrease.circle", tooltip: "Edit Ignore Rules", action: #selector(editIgnoreRules)))

        pathStackView.orientation = .horizontal
        pathStackView.alignment = .centerY
        pathStackView.spacing = 4
        pathStackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        pathBarView.translatesAutoresizingMaskIntoConstraints = false
        pathBarView.material = .sidebar
        pathBarView.blendingMode = .withinWindow
        pathBarView.state = .active

        pathScrollView.translatesAutoresizingMaskIntoConstraints = false
        pathScrollView.borderType = .noBorder
        pathScrollView.drawsBackground = false
        pathScrollView.hasHorizontalScroller = true
        pathScrollView.hasVerticalScroller = false
        pathScrollView.autohidesScrollers = true
        pathScrollView.scrollerStyle = .overlay
        pathScrollView.documentView = pathStackView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Files"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(openSelectedItem)
        outlineView.doubleAction = #selector(openSelectedItem)
        outlineView.menu = NSMenu()
        outlineView.menu?.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = outlineView

        view.addSubview(toolbar)
        view.addSubview(pathBarView)
        pathBarView.addSubview(pathScrollView)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),

            pathBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pathBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pathBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pathBarView.heightAnchor.constraint(equalToConstant: 42),

            pathScrollView.leadingAnchor.constraint(equalTo: pathBarView.leadingAnchor),
            pathScrollView.trailingAnchor.constraint(equalTo: pathBarView.trailingAnchor),
            pathScrollView.topAnchor.constraint(equalTo: pathBarView.topAnchor, constant: 4),
            pathScrollView.bottomAnchor.constraint(equalTo: pathBarView.bottomAnchor, constant: -4),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pathBarView.topAnchor)
        ])
    }

    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    func reloadRoot() {
        loadViewIfNeeded()
        ignoreRules.reload()
        rootNode = FileTreeNode(url: rootURL, isDirectory: true, parent: nil)
        rootNode.children = nil
        outlineView.reloadData()
        outlineView.expandItem(rootNode)
        rebuildPathBar()
    }

    func reveal(url: URL) {
        loadViewIfNeeded()
        let directoryURL = directoryToReveal(for: url)
        if rootURL != directoryURL {
            rootURL = directoryURL
            reloadRoot()
        }
        var current = rootNode!
        outlineView.expandItem(current)
        let relativePath = url.path == rootURL.path ? [] : url.path.dropFirst(rootURL.path.count).split(separator: "/").map(String.init)
        for component in relativePath {
            ensureChildrenLoaded(for: current)
            guard let next = current.children?.first(where: { $0.url.lastPathComponent == component }) else {
                break
            }
            current = next
            if current.isDirectory {
                outlineView.expandItem(current)
            }
        }
        let row = outlineView.row(forItem: current)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    private func directoryToReveal(for url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func rebuildPathBar() {
        pathStackView.arrangedSubviews.forEach { view in
            pathStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let components = pathComponents(for: rootURL)
        for (index, component) in components.enumerated() {
            if index > 0 {
                let separator = NSTextField(labelWithString: ">")
                separator.textColor = .tertiaryLabelColor
                separator.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
                pathStackView.addArrangedSubview(separator)
            }
            pathStackView.addArrangedSubview(pathButton(title: component.title, symbol: component.symbol, url: component.url))
        }

        pathScrollView.layoutSubtreeIfNeeded()
        let size = pathStackView.fittingSize
        let contentHeight = max(size.height, pathScrollView.contentSize.height)
        pathStackView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(size.width, pathScrollView.contentSize.width),
            height: contentHeight
        )
        pathScrollView.contentView.scroll(to: NSPoint(x: max(0, pathStackView.frame.width - pathScrollView.contentSize.width), y: 0))
        pathScrollView.reflectScrolledClipView(pathScrollView.contentView)
    }

    private func pathComponents(for url: URL) -> [(title: String, symbol: String, url: URL)] {
        var result: [(String, String, URL)] = []
        var current = url.standardizedFileURL
        while current.path != "/" {
            let name = current.lastPathComponent.isEmpty ? current.path : current.lastPathComponent
            result.insert((name, "folder", current), at: 0)
            current.deleteLastPathComponent()
        }
        result.insert(("Macintosh HD", "internaldrive", URL(fileURLWithPath: "/")), at: 0)
        return result
    }

    private func pathButton(title: String, symbol: String, url: URL) -> NSButton {
        let button = PathComponentButton(title: title, target: self, action: #selector(navigatePathComponent(_:)))
        button.url = url
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = url.path
        return button
    }

    // MARK: - Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? FileTreeNode
        if node == nil {
            return 1
        }
        guard node?.isDirectory == true else { return 0 }
        ensureChildrenLoaded(for: node!)
        return node?.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileTreeNode {
            ensureChildrenLoaded(for: node)
            return node.children![index]
        }
        return rootNode!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? FileTreeNode)?.isDirectory == true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("FileCell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let imageView = cell.imageView ?? NSImageView()
        imageView.image = NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc", accessibilityDescription: nil)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.stringValue = node.displayName

        if cell.imageView == nil {
            cell.addSubview(imageView)
            cell.imageView = imageView
        }
        if cell.textField == nil {
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    private func ensureChildrenLoaded(for node: FileTreeNode) {
        guard node.isDirectory, node.children == nil else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: node.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
            node.children = urls.compactMap { url in
                guard !ignoreRules.shouldExclude(url) else { return nil }
                let isDirectory = ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
                return FileTreeNode(url: url, isDirectory: isDirectory, parent: node)
            }.sorted { left, right in
                if left.isDirectory != right.isDirectory {
                    return left.isDirectory && !right.isDirectory
                }
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
        } catch {
            node.children = []
        }
    }

    private func reloadChildren(of node: FileTreeNode) {
        node.children = nil
        ensureChildrenLoaded(for: node)
        outlineView.reloadItem(node, reloadChildren: true)
        outlineView.expandItem(node)
    }

    // MARK: - Actions

    @objc private func openSelectedItem() {
        guard let node = selectedNode() else { return }
        if node.isDirectory {
            if NSApp.currentEvent?.clickCount ?? 0 >= 2 {
                toggleDirectory(node)
            }
            return
        }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            delegate?.fileTreeSidebar(self, openInNewTab: node.url)
        } else {
            delegate?.fileTreeSidebar(self, open: node.url)
        }
    }

    private func toggleDirectory(_ node: FileTreeNode) {
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            ensureChildrenLoaded(for: node)
            outlineView.expandItem(node)
        }
    }

    @objc private func refreshTree() {
        reloadRoot()
    }

    @objc private func navigatePathComponent(_ sender: PathComponentButton) {
        guard let url = sender.url else { return }
        rootURL = url
        reloadRoot()
    }

    @objc private func newFile() {
        createFile(in: targetDirectoryForNewItem())
    }

    @objc private func newFolder() {
        createFolder(in: targetDirectoryForNewItem())
    }

    @objc private func editIgnoreRules() {
        do {
            let url = try ignoreRules.ensureIgnoreFileExists()
            delegate?.fileTreeSidebar(self, open: url)
            reveal(url: url)
        } catch {
            showAlert(title: "Could Not Create Ignore File", message: error.localizedDescription)
        }
    }

    @objc private func contextOpen() {
        guard let node = contextNode(), !node.isDirectory else { return }
        delegate?.fileTreeSidebar(self, open: node.url)
    }

    @objc private func contextOpenInNewTab() {
        guard let node = contextNode(), !node.isDirectory else { return }
        delegate?.fileTreeSidebar(self, openInNewTab: node.url)
    }

    @objc private func contextRename() {
        guard let node = contextNode(), node.parent != nil else { return }
        rename(node)
    }

    @objc private func contextNewFileHere() {
        createFile(in: directoryForContext())
    }

    @objc private func contextNewFolderHere() {
        createFolder(in: directoryForContext())
    }

    @objc private func contextRevealInFinder() {
        guard let node = contextNode() else { return }
        delegate?.fileTreeSidebarRevealInFinder(self, url: node.url)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard contextNode() != nil else { return }
        menu.addItem(withTitle: "Open", action: #selector(contextOpen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open in New Tab", action: #selector(contextOpenInNewTab), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rename", action: #selector(contextRename), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New File Here", action: #selector(contextNewFileHere), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Folder Here", action: #selector(contextNewFolderHere), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(contextRevealInFinder), keyEquivalent: "").target = self
    }

    private func createFile(in directory: URL) {
        guard let name = promptForName(title: "New File", placeholder: "untitled.txt") else { return }
        let url = directory.appendingPathComponent(name)
        guard validateNewItemURL(url) else { return }
        guard FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil) else {
            showAlert(title: "Could Not Create File", message: "The file could not be created.")
            return
        }
        refreshParent(directory)
        delegate?.fileTreeSidebar(self, open: url)
        reveal(url: url)
    }

    private func createFolder(in directory: URL) {
        guard let name = promptForName(title: "New Folder", placeholder: "New Folder") else { return }
        let url = directory.appendingPathComponent(name)
        guard validateNewItemURL(url) else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refreshParent(directory)
            reveal(url: url)
        } catch {
            showAlert(title: "Could Not Create Folder", message: error.localizedDescription)
        }
    }

    private func rename(_ node: FileTreeNode) {
        guard let newName = promptForName(title: "Rename", placeholder: node.displayName, initialValue: node.displayName) else { return }
        let destination = node.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard validateNewItemURL(destination) else { return }
        let oldURL = node.url
        if renameAffectsCurrentFile(oldURL: oldURL, renamedDirectory: node.isDirectory),
           delegate?.fileTreeSidebarCanReplaceCurrentFile(self) == false {
            return
        }
        do {
            try FileManager.default.moveItem(at: oldURL, to: destination)
            let parent = node.parent
            if let parent {
                reloadChildren(of: parent)
            }
            updateCurrentFileAfterRename(from: oldURL, to: destination, renamedDirectory: node.isDirectory)
            reveal(url: destination)
        } catch {
            showAlert(title: "Could Not Rename", message: error.localizedDescription)
        }
    }

    private func updateCurrentFileAfterRename(from oldURL: URL, to newURL: URL, renamedDirectory: Bool) {
        guard let current = delegate?.fileTreeSidebarCurrentFileURL(self) else { return }
        if current == oldURL {
            delegate?.fileTreeSidebar(self, didRenameCurrentFileTo: newURL)
            return
        }
        guard renamedDirectory, isDescendant(current, of: oldURL) else { return }
        let suffix = current.path.dropFirst(oldURL.path.count)
        let updated = URL(fileURLWithPath: newURL.path + suffix)
        delegate?.fileTreeSidebar(self, didRenameCurrentFileTo: updated)
    }

    private func renameAffectsCurrentFile(oldURL: URL, renamedDirectory: Bool) -> Bool {
        guard let current = delegate?.fileTreeSidebarCurrentFileURL(self) else { return false }
        return current == oldURL || (renamedDirectory && isDescendant(current, of: oldURL))
    }

    private func targetDirectoryForNewItem() -> URL {
        if let node = selectedNode() {
            return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }
        return rootURL
    }

    private func directoryForContext() -> URL {
        guard let node = contextNode() else { return rootURL }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    private func refreshParent(_ directory: URL) {
        if let node = findLoadedNode(for: directory, from: rootNode) {
            reloadChildren(of: node)
        }
    }

    private func selectedNode() -> FileTreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeNode
    }

    private func contextNode() -> FileTreeNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeNode
    }

    private func findLoadedNode(for url: URL, from node: FileTreeNode) -> FileTreeNode? {
        if node.url == url { return node }
        guard let children = node.children else { return nil }
        for child in children {
            if let found = findLoadedNode(for: url, from: child) {
                return found
            }
        }
        return nil
    }

    private func validateNewItemURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showAlert(title: "Name Required", message: "Enter a non-empty name.")
            return false
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "Already Exists", message: "An item with that name already exists.")
            return false
        }
        return true
    }

    private func promptForName(title: String, placeholder: String, initialValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = placeholder
        input.stringValue = initialValue
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func isDescendant(_ url: URL, of parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }
}

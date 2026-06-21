import AppKit

func dbg(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/pd_debug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    var openControllers: [PreviewWindowController] = []
    private var pendingURLs: [URL] = []
    private var isLaunched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        dbg("[AppDelegate] applicationDidFinishLaunching, pending=\(pendingURLs.count)")
        setupMainMenu()
        isLaunched = true

        // Open files that arrived before the app was ready
        let toOpen = pendingURLs
        pendingURLs.removeAll()
        toOpen.forEach { openFile(at: $0) }

        // If still no windows, show open dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.openControllers.isEmpty == true {
                self?.openFileDialog(nil)
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        dbg("[AppDelegate] openFile (singular): \(filename)")
        let url = URL(fileURLWithPath: filename)
        if isLaunched {
            openFile(at: url)
        } else {
            pendingURLs.append(url)
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        dbg("[AppDelegate] openFiles: \(filenames)")
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if isLaunched {
            urls.forEach { openFile(at: $0) }
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openFileDialog(nil)
        }
        return true
    }

    func openFile(at url: URL, sidebarRootURL: URL? = nil) {
        // Deduplicate: if already open, just focus that window
        let resolved = url.resolvingSymlinksInPath()
        if let existing = openControllers.first(where: {
            $0.fileURL.resolvingSymlinksInPath() == resolved
        }) {
            showAndActivate(existing)
            return
        }
        dbg("[AppDelegate] openFile(at:) \(url.path)")
        let tabHost = openControllers.first
        let wc = PreviewWindowController(fileURL: url, sidebarRootURL: sidebarRootURL)
        openControllers.append(wc)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: wc.window,
            queue: .main
        ) { [weak self, weak wc] _ in
            self?.openControllers.removeAll { $0 === wc }
        }
        DispatchQueue.main.async {
            dbg("[AppDelegate] async showWindow start")
            self.showAndActivate(wc, tabIn: tabHost)
            dbg("[AppDelegate] async showWindow done, windows=\(NSApp.windows.count)")
        }
    }

    private func showAndActivate(_ wc: PreviewWindowController, tabIn host: PreviewWindowController? = nil) {
        if let hostWindow = host?.window,
           let window = wc.window,
           hostWindow !== window {
            hostWindow.addTabbedWindow(window, ordered: .above)
        }
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        wc.window?.orderFrontRegardless()
    }

    @objc func openFileDialog(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.title = "Open File"
        if panel.runModal() == .OK {
            panel.urls.forEach { openFile(at: $0) }
        }
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About PreviewDocs", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PreviewDocs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open…", action: #selector(openFileDialog(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "}")
        windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "{")

        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
}

import AppKit
import WebKit

enum MarkdownViewMode {
    case preview
    case source
}

protocol PreviewViewControllerDelegate: AnyObject {
    func previewViewControllerDidChangeFile(_ controller: PreviewViewController)
    func previewViewControllerDidChangeDirtyState(_ controller: PreviewViewController)
}

class PreviewViewController: NSViewController, WKNavigationDelegate, NSTextViewDelegate {

    private(set) var fileURL: URL
    weak var delegate: PreviewViewControllerDelegate?

    private var webView: PreviewWebView!
    private var textScrollView: NSScrollView!
    private var textView: NSTextView!
    private var markdownViewMode: MarkdownViewMode = .preview
    private var loadingText = false
    private var editableTextLoaded = false

    private(set) var hasUnsavedChanges = false {
        didSet {
            if oldValue != hasUnsavedChanges {
                delegate?.previewViewControllerDidChangeDirtyState(self)
            }
        }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard webView == nil else { return }
        setupViews()
        loadFile()
    }

    private func setupViews() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let wv = PreviewWebView(frame: view.bounds, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.allowsMagnification = true

        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        let tv = NSTextView(frame: scrollView.bounds)
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        scrollView.documentView = tv

        view.addSubview(wv)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView = wv
        textScrollView = scrollView
        textView = tv
        showWebView()
    }

    func open(url: URL) {
        fileURL = url
        if !supportsMarkdownModeToggle {
            markdownViewMode = .preview
        }
        hasUnsavedChanges = false
        loadFile()
        delegate?.previewViewControllerDidChangeFile(self)
    }

    func loadFile() {
        guard webView != nil else { return }
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            switch markdownViewMode {
            case .preview:
                loadMarkdown()
            case .source:
                loadEditableText()
            }
        case "html", "htm", "pdf":
            showWebView()
            editableTextLoaded = false
            hasUnsavedChanges = false
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        case _ where isImageExtension(ext):
            showWebView()
            editableTextLoaded = false
            hasUnsavedChanges = false
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        default:
            loadEditableText()
        }
    }

    var supportsMarkdownModeToggle: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var isEditableTextLoaded: Bool {
        return editableTextLoaded
    }

    var currentTextContents: String? {
        if editableTextLoaded {
            return textView.string
        }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func setMarkdownViewMode(_ mode: MarkdownViewMode) {
        guard supportsMarkdownModeToggle else { return }
        markdownViewMode = mode
        loadFile()
    }

    func saveIfNeeded() -> Bool {
        guard hasUnsavedChanges else { return true }
        return save()
    }

    func save() -> Bool {
        guard editableTextLoaded else { return false }
        do {
            try textView.string.write(to: fileURL, atomically: true, encoding: .utf8)
            hasUnsavedChanges = false
            return true
        } catch {
            showAlert(title: "Could Not Save", message: error.localizedDescription)
            return false
        }
    }

    func discardUnsavedChanges() {
        hasUnsavedChanges = false
        loadFile()
    }

    func textDidChange(_ notification: Notification) {
        guard !loadingText else { return }
        hasUnsavedChanges = true
    }

    // MARK: - Markdown

    private func loadMarkdown() {
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else {
            loadError("Could not read file.")
            return
        }
        guard let markedJS = loadBundledResource("marked.min.js") else {
            loadEditableText()
            return
        }
        let mermaidJS = loadBundledResource("mermaid.min.js") ?? ""

        let jsonEncoded: String
        if let data = try? JSONEncoder().encode(markdown),
           let str = String(data: data, encoding: .utf8) {
            jsonEncoded = str
        } else {
            jsonEncoded = "\"\""
        }

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>\(sharedCSS)
        body { max-width: 860px; margin: 0 auto; padding: 40px 24px; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>\(markedJS)</script>
        <script>\(mermaidJS)</script>
        <script>
        const raw = \(jsonEncoded);
        const content = document.getElementById('content');
        const renderer = new marked.Renderer();

        function escapeHTML(value) {
            return value.replace(/[&<>"']/g, (character) => ({
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                '"': '&quot;',
                "'": '&#39;'
            })[character]);
        }

        renderer.code = function(code, language) {
            const normalizedLanguage = (language || '').trim().split(/\\s+/)[0].toLowerCase();
            if (normalizedLanguage === 'mermaid') {
                return '<div class="mermaid">' + escapeHTML(code) + '</div>';
            }
            return false;
        };

        marked.use({ renderer });
        content.innerHTML = marked.parse(raw);

        if (window.mermaid) {
            const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
            mermaid.initialize({
                startOnLoad: false,
                theme: prefersDark ? 'dark' : 'default',
                securityLevel: 'strict'
            });
            mermaid.run({ querySelector: '.mermaid' }).catch((error) => {
                console.error('Could not render Mermaid diagram', error);
            });
        }
        </script>
        </body>
        </html>
        """
        showWebView()
        editableTextLoaded = false
        hasUnsavedChanges = false
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }

    private func loadEditableText() {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            loadError("Could not read file as UTF-8 text.")
            return
        }
        showTextView()
        loadingText = true
        textView.string = content
        loadingText = false
        editableTextLoaded = true
        hasUnsavedChanges = false
    }

    // MARK: - Images

    private func isImageExtension(_ ext: String) -> Bool {
        return [
            "png", "jpg", "jpeg", "gif", "webp", "svg",
            "bmp", "tif", "tiff", "heic", "heif", "ico"
        ].contains(ext)
    }

    // MARK: - Error

    private func loadError(_ message: String) {
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;color:#c00;">
        <p>\(message)</p>
        </body></html>
        """
        showWebView()
        editableTextLoaded = false
        hasUnsavedChanges = false
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showWebView() {
        webView?.isHidden = false
        textScrollView?.isHidden = true
    }

    private func showTextView() {
        webView?.isHidden = true
        textScrollView?.isHidden = false
    }

    // MARK: - Helpers

    private func loadBundledResource(_ name: String) -> String? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            return str
        }
        let devURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name)")
        return try? String(contentsOf: devURL, encoding: .utf8)
    }

    // MARK: - Shared CSS

    private var sharedCSS: String {
        return """
        :root {
            --bg:     #ffffff;
            --fg:     #1a1a1a;
            --code-bg:#f5f5f7;
            --border: #e0e0e0;
            --quote:  #d0d0d0;
            --quote-fg:#666;
            --link:   #0066cc;
            --th-bg:  #f0f0f0;
            --tbl-bd: #ddd;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg:     #1c1c1e;
                --fg:     #e0e0e0;
                --code-bg:#2c2c2e;
                --border: #38383a;
                --quote:  #48484a;
                --quote-fg:#aaa;
                --link:   #5ac8fa;
                --th-bg:  #2c2c2e;
                --tbl-bd: #3a3a3c;
            }
        }
        * { box-sizing: border-box; }
        html { background: var(--bg); }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            font-size: 15px;
            line-height: 1.7;
            color: var(--fg);
            background: var(--bg);
        }
        h1, h2, h3, h4, h5, h6 {
            font-weight: 600;
            line-height: 1.3;
            margin-top: 1.6em;
            margin-bottom: 0.4em;
        }
        h1 { font-size: 2em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        code {
            font-family: 'SF Mono', ui-monospace, Menlo, monospace;
            font-size: 0.875em;
            background: var(--code-bg);
            padding: 0.15em 0.4em;
            border-radius: 4px;
        }
        pre {
            background: var(--code-bg);
            border-radius: 8px;
            padding: 16px;
            overflow-x: auto;
            font-size: 0.875em;
            line-height: 1.6;
        }
        pre code { background: none; padding: 0; border-radius: 0; font-size: inherit; }
        blockquote {
            border-left: 4px solid var(--quote);
            margin: 1em 0;
            padding: 4px 16px;
            color: var(--quote-fg);
        }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; border-radius: 4px; }
        .mermaid {
            margin: 1.5em 0;
            overflow-x: auto;
            text-align: center;
        }
        .mermaid svg {
            max-width: 100%;
            height: auto;
        }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid var(--tbl-bd); padding: 8px 12px; text-align: left; }
        th { background: var(--th-bg); font-weight: 600; }
        hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
        """
    }
}

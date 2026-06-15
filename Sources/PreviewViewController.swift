import AppKit
import WebKit

enum MarkdownViewMode {
    case preview
    case source
}

class PreviewViewController: NSViewController, WKNavigationDelegate {

    let fileURL: URL
    private var webView: PreviewWebView!
    private var markdownViewMode: MarkdownViewMode = .preview

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // Use a plain NSView first; WKWebView is created lazily in viewDidAppear
        // to avoid re-entrant run-loop issues during window initialization.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard webView == nil else { return }
        setupWebView()
        loadFile()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let wv = PreviewWebView(frame: view.bounds, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.allowsMagnification = true
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView = wv
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
                loadAsCode(ext: ext)
            }
        case "html", "htm":
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        case "pdf":
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        case _ where isImageExtension(ext):
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        default:
            loadAsCode(ext: ext)
        }
    }

    var supportsMarkdownModeToggle: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    func setMarkdownViewMode(_ mode: MarkdownViewMode) {
        guard supportsMarkdownModeToggle else { return }
        markdownViewMode = mode
        loadFile()
    }

    // MARK: - Markdown

    private func loadMarkdown() {
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else {
            loadError("Could not read file.")
            return
        }
        guard let markedJS = loadBundledResource("marked.min.js") else {
            loadAsCode(ext: "md")
            return
        }

        // Embed markdown safely as a JSON string
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
        <script>
        const raw = \(jsonEncoded);
        document.getElementById('content').innerHTML = marked.parse(raw);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
    }

    // MARK: - Code / Plain text

    private func loadAsCode(ext: String) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            loadError("Could not read file.")
            return
        }
        let escaped = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        \(sharedCSS)
        body { margin: 0; padding: 0; }
        pre {
            margin: 0;
            padding: 24px;
            min-height: 100vh;
            overflow-x: auto;
        }
        code { background: none; padding: 0; border-radius: 0; }
        </style>
        </head>
        <body>
        <pre><code>\(escaped)</code></pre>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
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
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Helpers

    private func loadBundledResource(_ name: String) -> String? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            return str
        }
        // Fallback for dev: look next to the executable
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
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid var(--tbl-bd); padding: 8px 12px; text-align: left; }
        th { background: var(--th-bg); font-weight: 600; }
        hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
        """
    }
}

import AppKit
import WebKit

// WKWebView subclass that accepts file-drop to open files as new tabs
class PreviewWebView: WKWebView {

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard handlesCopyShortcut(event) else {
            super.keyDown(with: event)
            return
        }

        copySelectedText()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard handlesCopyShortcut(event) else {
            return super.performKeyEquivalent(with: event)
        }

        copySelectedText()
        return true
    }

    private func handlesCopyShortcut(_ event: NSEvent) -> Bool {
        guard let character = event.charactersIgnoringModifiers?.lowercased(),
              character == "c" else {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) || flags.contains(.control)
    }

    private func copySelectedText() {
        evaluateJavaScript("window.getSelection ? window.getSelection().toString() : ''") { value, _ in
            guard let selectedText = value as? String, !selectedText.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let hasFiles = sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true])
        return hasFiles ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              let delegate = NSApp.delegate as? AppDelegate else {
            return false
        }
        urls.forEach { delegate.openFile(at: $0) }
        return true
    }
}

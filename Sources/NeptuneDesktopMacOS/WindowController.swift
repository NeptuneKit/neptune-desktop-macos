import AppKit
import WebKit

final class NeptuneMainWindowController: NSWindowController {
    private let webView: WKWebView

    init(webURL: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        let viewController = NSViewController()
        viewController.view = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NeptuneDesktopMacOS"
        window.center()
        window.contentViewController = viewController
        window.minSize = NSSize(width: 960, height: 640)

        super.init(window: window)
        load(webURL: webURL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func load(webURL: URL) {
        let request = URLRequest(url: webURL)
        webView.load(request)
    }
}

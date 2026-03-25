import AppKit
import WebKit

final class NeptuneMainWindowController: NSWindowController, WKNavigationDelegate {
    private static let persistedFrameKey = "NeptuneDesktopMacOS.MainWindow.PersistedFrame"
    private let webView: WKWebView
    private let defaultWindowSize = NSSize(width: 1280, height: 860)
    private var hasDisplayedLoadFailurePage = false

    init(launchTarget: InspectorLaunchTarget) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        let viewController = NSViewController()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860))
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        viewController.view = containerView

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
        window.setFrameAutosaveName("NeptuneDesktopMacOS.MainWindow.Frame")
        Self.restorePersistedFrameIfNeeded(window)

        super.init(window: window)
        configureWindowFramePersistence(window)
        webView.navigationDelegate = self
        load(launchTarget: launchTarget)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func load(launchTarget: InspectorLaunchTarget) {
        hasDisplayedLoadFailurePage = false
        switch launchTarget {
        case let .local(indexURL, readAccessDirectory):
            NSLog("Inspector load target: local %@", indexURL.path)
            webView.loadFileURL(indexURL, allowingReadAccessTo: readAccessDirectory)
        case let .remote(url):
            NSLog("Inspector load target: remote %@", url.absoluteString)
            webView.load(URLRequest(url: url))
        }
    }

    func ensureWindowVisible() {
        guard let window else {
            return
        }

        var visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let mainVisibleFrame = NSScreen.main?.visibleFrame {
            visibleFrames.removeAll(where: { $0.equalTo(mainVisibleFrame) })
            visibleFrames.insert(mainVisibleFrame, at: 0)
        }

        guard !visibleFrames.isEmpty else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let normalizedFrame = WindowFrameNormalizer.normalize(
            frame: window.frame,
            visibleFrames: visibleFrames,
            minSize: window.minSize,
            preferredSize: defaultWindowSize,
            centerOnPrimaryVisibleFrame: false
        )

        if !window.frame.equalTo(normalizedFrame) {
            window.setFrame(normalizedFrame, display: true)
        }

        window.makeKeyAndOrderFront(nil)
        persistWindowFrameIfNeeded()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasDisplayedLoadFailurePage = false
        NSLog("Inspector page finished loading: %@", webView.url?.absoluteString ?? "nil")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Inspector navigation failed: %@", error.localizedDescription)
        displayLoadFailurePageIfNeeded(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Inspector provisional navigation failed: %@", error.localizedDescription)
        displayLoadFailurePageIfNeeded(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("Inspector web content process terminated")
    }

    private func configureWindowFramePersistence(_ window: NSWindow) {
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.willCloseNotification,
        ]

        for name in names {
            center.addObserver(
                self,
                selector: #selector(handleWindowFrameChangeNotification(_:)),
                name: name,
                object: window
            )
        }
    }

    @objc
    private func handleWindowFrameChangeNotification(_ notification: Notification) {
        persistWindowFrameIfNeeded()
    }

    private func persistWindowFrameIfNeeded() {
        guard let window else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.persistedFrameKey)
    }

    private static func restorePersistedFrameIfNeeded(_ window: NSWindow) {
        guard let serializedFrame = UserDefaults.standard.string(forKey: Self.persistedFrameKey) else {
            return
        }
        let restoredFrame = NSRectFromString(serializedFrame)
        guard restoredFrame.width > 0, restoredFrame.height > 0 else {
            return
        }
        window.setFrame(restoredFrame, display: false)
    }

    private func displayLoadFailurePageIfNeeded(_ error: Error) {
        guard !hasDisplayedLoadFailurePage else {
            return
        }
        hasDisplayedLoadFailurePage = true

        let inspectorURL = ProcessInfo.processInfo.environment["NEPTUNE_INSPECTOR_URL"] ?? "http://127.0.0.1:4173"
        let escapedError = escapeForHTML(error.localizedDescription)
        let escapedInspectorURL = escapeForHTML(inspectorURL)
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Neptune Inspector Load Failed</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; color: #111827; background: #f9fafb; }
            .card { max-width: 860px; margin: 24px auto; padding: 20px; background: #ffffff; border: 1px solid #e5e7eb; border-radius: 12px; }
            code { background: #f3f4f6; border-radius: 6px; padding: 2px 6px; }
            .error { color: #b91c1c; word-break: break-word; }
          </style>
        </head>
        <body>
          <div class="card">
            <h2>Inspector page load failed</h2>
            <p>Desktop app did not receive a valid Inspector page.</p>
            <p>Current expected URL: <code>\(escapedInspectorURL)</code></p>
            <p class="error">Error: \(escapedError)</p>
            <p>Check if H5 service is running, then relaunch the app or click refresh.</p>
            <button onclick="location.reload()">Refresh</button>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func escapeForHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

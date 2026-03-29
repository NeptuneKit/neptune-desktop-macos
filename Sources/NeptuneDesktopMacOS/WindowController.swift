import AppKit

@MainActor
final class NeptuneMainWindowController: NSWindowController {
    private let defaultWindowSize = NSSize(width: 1280, height: 860)
    private let statusLabel = NSTextField(labelWithString: "CLI 状态：未运行")
    private let webURLLabel = NSTextField(labelWithString: "")
    private let logTextView = NSTextView()
    private let startButton = NSButton(title: "启动 CLI", target: nil, action: nil)
    private let stopButton = NSButton(title: "停止 CLI", target: nil, action: nil)
    private let openWebButton = NSButton(title: "打开 Web", target: nil, action: nil)
    private let copyWebButton = NSButton(title: "复制 URL", target: nil, action: nil)

    private let webURL: URL
    private let onStartCLI: () -> Void
    private let onStopCLI: () -> Void

    init(
        webURL: URL,
        onStartCLI: @escaping () -> Void,
        onStopCLI: @escaping () -> Void
    ) {
        self.webURL = webURL
        self.onStartCLI = onStartCLI
        self.onStopCLI = onStopCLI

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Neptune Desktop CLI Shell"
        window.center()
        window.minSize = NSSize(width: 960, height: 640)

        super.init(window: window)
        window.contentViewController = makeContentViewController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    }

    func updateCLIStatus(isRunning: Bool) {
        statusLabel.stringValue = isRunning ? "CLI 状态：运行中" : "CLI 状态：未运行"
        startButton.isEnabled = !isRunning
        stopButton.isEnabled = isRunning
    }

    func appendLogLine(_ line: String) {
        let output = line.hasSuffix("\n") ? line : line + "\n"
        let attributedOutput = NSAttributedString(string: output)

        logTextView.textStorage?.append(attributedOutput)
        logTextView.scrollToEndOfDocument(nil)
    }

    private func makeContentViewController() -> NSViewController {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860))

        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        webURLLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        webURLLabel.textColor = NSColor.secondaryLabelColor
        webURLLabel.lineBreakMode = .byTruncatingMiddle
        webURLLabel.stringValue = "Web URL: \(webURL.absoluteString)"

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = NSColor.textBackgroundColor
        logTextView.autoresizingMask = [.width, .height]
        logTextView.textContainerInset = NSSize(width: 8, height: 8)

        let logScrollView = NSScrollView()
        logScrollView.hasVerticalScroller = true
        logScrollView.hasHorizontalScroller = false
        logScrollView.autohidesScrollers = true
        logScrollView.borderType = .bezelBorder
        logScrollView.documentView = logTextView

        startButton.target = self
        startButton.action = #selector(handleStartCLI)

        stopButton.target = self
        stopButton.action = #selector(handleStopCLI)

        openWebButton.target = self
        openWebButton.action = #selector(handleOpenWeb)

        copyWebButton.target = self
        copyWebButton.action = #selector(handleCopyWebURL)

        let buttonRow = NSStackView(views: [startButton, stopButton, openWebButton, copyWebButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let contentStack = NSStackView(views: [statusLabel, webURLLabel, buttonRow, logScrollView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            logScrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            logScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])

        updateCLIStatus(isRunning: false)
        appendLogLine("[desktop] Web URL: \(webURL.absoluteString)")
        appendLogLine("[desktop] 等待 CLI 启动...")

        let viewController = NSViewController()
        viewController.view = container
        return viewController
    }

    @objc
    private func handleStartCLI() {
        onStartCLI()
    }

    @objc
    private func handleStopCLI() {
        onStopCLI()
    }

    @objc
    private func handleOpenWeb() {
        NSWorkspace.shared.open(webURL)
    }

    @objc
    private func handleCopyWebURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(webURL.absoluteString, forType: .string)
        appendLogLine("[desktop] 已复制 Web URL")
    }
}

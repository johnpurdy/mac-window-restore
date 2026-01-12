import AppKit

/// A HUD-style overlay that briefly displays feedback when window positions are saved manually.
/// Similar to macOS volume/brightness indicators.
@MainActor
public final class SaveFeedbackHUD {
    private var window: NSPanel?
    private var fadeOutWorkItem: DispatchWorkItem?

    /// The message displayed in the HUD
    public let message = "Window Positions Saved"

    public init() {}

    /// Shows the HUD with the save confirmation message
    public func show() {
        // Cancel any pending fade out
        fadeOutWorkItem?.cancel()

        // Create window if needed
        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Position in center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Show with fade in
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        // Schedule fade out
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        fadeOutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func fadeOut() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
            }
        })
    }

    private func createWindow() {
        let cornerRadius: CGFloat = 18
        let windowSize = NSSize(width: 220, height: 100)

        // Create HUD-style panel
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        // Create content view with visual effect (blur)
        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: windowSize))
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        // Use maskImage for proper rounded corner clipping (Apple's recommended approach)
        visualEffectView.maskImage = Self.createRoundedRectMaskImage(size: windowSize, cornerRadius: cornerRadius)

        // Create stack view for content
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Checkmark icon
        let checkmarkView = NSImageView()
        if let checkmarkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved") {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
            checkmarkView.image = checkmarkImage.withSymbolConfiguration(config)
            checkmarkView.contentTintColor = .systemGreen
        }

        // Label
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center

        stackView.addArrangedSubview(checkmarkView)
        stackView.addArrangedSubview(label)

        visualEffectView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor)
        ])

        panel.contentView = visualEffectView
        self.window = panel
    }

    /// Creates a mask image for rounded corners using Core Graphics
    /// This is Apple's recommended approach for masking NSVisualEffectView
    private static func createRoundedRectMaskImage(size: NSSize, cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }
}

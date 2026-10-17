import AppKit
import Observation
import SwiftUI

/// Borderless floating panel that never activates FastMoji (the host app stays frontmost).
final class PickerPanel: NSPanel {
    /// True for the hotkey picker (search field takes keys); false for the inline picker.
    var becomesKey = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { becomesKey }
    override var canBecomeMain: Bool { false }
}

enum PickerMode {
    /// Opened by the hotkey: key panel with its own search field.
    case hotkey
    /// Opened by the inline trigger: non-key, the query is typed in the host app.
    case inline
}

/// What `PanelContentView` shows; changing it never rebuilds the hosting view.
@MainActor
@Observable
final class PickerPanelState {
    var mode: PickerMode = .hotkey
    /// Text typed in the host app, trigger included (e.g. "::smi"); inline mode only.
    var inlineQuery = ""
    /// What the Ignore button adds to Settings → Ignored; nil hides the button.
    var ignoreTarget: IgnoreTarget?
    /// Tooltip of the hovered header button.
    var tooltip: String?
}

/// The app or website the panel was opened in.
enum IgnoreTarget: Equatable {
    case app(bundleID: String, name: String)
    case domain(String)
}

/// Takes the first click: the inline panel is never key, so its buttons must act on that click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the single picker panel used by the hotkey and inline triggers.
@MainActor
final class PickerPanelController {
    private static let caretGap: CGFloat = 4
    private static let cornerRadius: CGFloat = 12

    private let model: EmojiPickerModel
    private let state = PickerPanelState()
    private let panel = PickerPanel()
    private let hostingView: FirstMouseHostingView<PanelContentView>
    private var resignKeyObserver: NSObjectProtocol?

    init(model: EmojiPickerModel) {
        self.model = model
        // Esc in hotkey mode: same as `hide()` (never `close()`, the panel is reused).
        hostingView = FirstMouseHostingView(
            rootView: PanelContentView(model: model, state: state) { [weak panel] in panel?.orderOut(nil) }
        )
        panel.contentView = Self.makeBackground(hosting: hostingView)
        panel.setContentSize(hostingView.fittingSize)

        // Hotkey mode: cmd+tab, a Space switch or a click elsewhere takes the key status away.
        // Inline panels never become key; their click-outside goes through the event tap.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.mode == .hotkey else { return }
                self.hide()
            }
        }
    }

    /// Vibrant background that stays active: a SwiftUI material renders flat in a window
    /// that is never key in an app that is never active (the inline panel).
    private static func makeBackground(hosting: NSView) -> NSVisualEffectView {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        return background
    }

    var isVisible: Bool { panel.isVisible }

    /// Panel frame in AppKit screen coordinates.
    var frame: NSRect { panel.frame }

    /// Mode of the visible panel, nil when hidden.
    var mode: PickerMode? { panel.isVisible ? state.mode : nil }

    /// Opens the panel below the caret (above it when there is no room), inside the caret's screen.
    /// `caret` is in AppKit screen coordinates (bottom-left origin).
    func show(at caret: NSRect, mode: PickerMode) {
        model.reset()
        state.mode = mode
        state.inlineQuery = ""
        state.ignoreTarget = nil
        // The panel may have hidden under the pointer: no exit event cleared it.
        state.tooltip = nil

        hostingView.layoutSubtreeIfNeeded()
        let frame = Self.frame(size: hostingView.fittingSize, caret: caret)
        panel.setFrame(frame, display: false)

        switch mode {
        case .hotkey:
            panel.becomesKey = true
            panel.makeKeyAndOrderFront(nil)
        case .inline:
            panel.becomesKey = false
            panel.orderFrontRegardless()
        }
        // Transparent window: recompute the shadow from the rounded content.
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Shows the text typed in the host app (inline mode); the caller also sets `model.query`.
    func setInlineQuery(_ text: String) {
        state.inlineQuery = text
    }

    func setIgnoreTarget(_ target: IgnoreTarget?) {
        state.ignoreTarget = target
    }

    private static func frame(size: NSSize, caret: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(caret.origin, $0.frame, false) }
            ?? NSScreen.main
        var origin = NSPoint(x: caret.minX, y: caret.minY - caretGap - size.height)
        guard let visible = screen?.visibleFrame else { return NSRect(origin: origin, size: size) }

        if origin.y < visible.minY {
            origin.y = caret.maxY + caretGap
        }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        return NSRect(origin: origin, size: size)
    }
}

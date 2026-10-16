import AppKit
import SwiftUI

/// Menubar popover: search field, shared emoji grid, Settings / About / Quit footer.
/// Enter / click runs `AppSettings.menubarAction`.
struct MenuBarContentView: View {
    let model: EmojiPickerModel
    /// Nil while hosting unit tests (picks are copied).
    let coordinator: AppCoordinator?

    private var permission: AccessibilityPermission? { coordinator?.permission }

    @State private var window = WindowBox()
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                // Return/Esc/arrows are handled by the key monitor (no .onSubmit, it would double-fire).
                TextField("Search emoji", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if let permission, !permission.isTrusted {
                accessibilityBanner(permission)
                Divider()
            }
            EmojiGridView(model: model)
            Divider()
            footer
        }
        .frame(width: 400)
        .capsuleButtons()
        .background(WindowAccessor(box: window))
        .pickerKeyMonitor(model, window: window) { close() }
        // First open (the window may become key before the accessor has captured it).
        .onAppear {
            prepareForOpen()
            // The popover window is not key yet when onAppear runs.
            DispatchQueue.main.async { searchFocused = true }
        }
        // Every open, whether or not SwiftUI re-runs onAppear for the popover.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let host = window.window, (note.object as? NSWindow) === host else { return }
            prepareForOpen()
            searchFocused = true
        }
    }

    /// Clears the query, refreshes "Frequently Used", scrolls to the top (via `reset()`) and wires Enter.
    private func prepareForOpen() {
        model.reset()
        model.onConfirm = { [coordinator] emoji in
            close()
            if let coordinator {
                coordinator.deliverMenubarPick(emoji)
            } else {
                EmojiInserter.copy(emoji.emoji)
            }
        }
    }

    /// The only place that asks for Accessibility (user action).
    private func accessibilityBanner(_ permission: AccessibilityPermission) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("FastMoji needs Accessibility to insert emoji")
                .font(.caption)
            Spacer(minLength: 0)
            Button("Grant Accessibility") { permission.request() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Settings") { showSettings() }
            Button("About") { showAbout() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(HoverCapsuleButtonStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Closes the popover first, like `showAbout()`.
    private func showSettings() {
        close()
        SettingsWindowController.shared.show()
    }

    /// Closes the popover first so its key monitor never sees keys meant for the About panel.
    private func showAbout() {
        close()
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func close() {
        window.window?.close()
    }
}

// MARK: - Hosting window

/// Weak reference to the window hosting a picker (read later from callbacks and the key monitor).
@MainActor
final class WindowBox {
    weak var window: NSWindow?
}

struct WindowAccessor: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.box = box
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackingView: NSView {
        var box: WindowBox?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { box?.window = window }
        }
    }
}

// MARK: - Button style

extension View {
    /// The app-wide button look: bordered capsules (menubar popover, panels, Settings).
    func capsuleButtons() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule)
    }
}

/// Capsule with hover and pressed feedback, for the footer buttons (`.bordered` has no hover state).
struct HoverCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverCapsule(configuration: configuration)
    }

    private struct HoverCapsule: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            let fill = configuration.isPressed ? 0.24 : isHovered ? 0.16 : 0.07
            configuration.label
                .font(.callout)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(fill)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isHovered ? 0.22 : 0.1), lineWidth: 1))
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

import AppKit
import SwiftUI

/// Menubar popover: search field, shared emoji grid, About / Quit footer. Enter copies.
struct MenuBarContentView: View {
    let model: EmojiPickerModel

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
                    .font(.title3)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            EmojiGridView(model: model)
            Divider()
            footer
        }
        .frame(width: 400)
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
        model.onConfirm = { emoji in
            copy(emoji)
            close()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("About") { showAbout() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func copy(_ emoji: Emoji) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emoji.emoji, forType: .string)
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

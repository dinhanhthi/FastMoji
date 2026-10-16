import AppKit
import SwiftUI

/// Hotkey / inline picker panel: header (with Settings / Quit buttons) and shared emoji grid.
struct PanelContentView: View {
    let model: EmojiPickerModel
    let state: PickerPanelState
    let onCancel: () -> Void

    @State private var window = WindowBox()
    @FocusState private var searchFocused: Bool

    private static let cornerRadius: CGFloat = 12
    /// Same for both modes so switching mode never changes the panel size.
    private static let headerHeight: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .frame(height: Self.headerHeight)
            Divider()
            EmojiGridView(model: model)
        }
        .capsuleButtons()
        .background(WindowAccessor(box: window))
        // The vibrant background is an `NSVisualEffectView` (see `PickerPanelController`).
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    /// Right of the input in both modes, whether or not the menubar is on.
    private var appButtons: some View {
        HStack(spacing: 6) {
            Button {
                onCancel()
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                confirmQuit()
            } label: {
                Image(systemName: "power")
            }
            .help("Quit FastMoji")
        }
        .buttonStyle(HoverCapsuleButtonStyle())
    }

    /// The panel never activates FastMoji: activate it so the alert is frontmost and takes keys.
    private func confirmQuit() {
        onCancel()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Quit FastMoji?"
        alert.informativeText = "Inline, hotkey and menubar triggers stop working until you open FastMoji again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.title2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var header: some View {
        switch state.mode {
        case .hotkey: searchField
        case .inline: inlineQuery
        }
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            searchIcon
            // Return/Esc/arrows are handled by the key monitor (no .onSubmit, it would double-fire).
            TextField("Search emoji", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
            appButtons
        }
        .pickerKeyMonitor(model, window: window, onCancel: onCancel)
        // The panel is not key yet when onAppear runs; focus lands on the next runloop.
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        // Every hotkey open (the hosting view is reused, onAppear may not run again).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let host = window.window, (note.object as? NSWindow) === host else { return }
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// Read-only: the query is typed in the host app and fed by the event tap.
    private var inlineQuery: some View {
        HStack(spacing: 8) {
            searchIcon
            Text(state.inlineQuery)
                .font(.title3.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            appButtons
        }
    }
}

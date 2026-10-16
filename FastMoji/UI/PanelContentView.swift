import AppKit
import SwiftUI

/// Hotkey / inline picker panel: header, shared emoji grid, optional app buttons footer.
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
            if state.showsAppButtons {
                Divider()
                appButtons
            }
        }
        .background(WindowAccessor(box: window))
        // The vibrant background is an `NSVisualEffectView` (see `PickerPanelController`).
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    /// Shown while the menubar is off: the only way to Settings / Quit besides reopening the app.
    private var appButtons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Settings") {
                onCancel()
                SettingsWindowController.shared.show()
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // Return/Esc/arrows are handled by the key monitor (no .onSubmit, it would double-fire).
            TextField("Search emoji", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(state.inlineQuery)
                .font(.title3.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

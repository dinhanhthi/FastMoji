import AppKit
import SwiftUI

/// Hotkey / inline picker panel: header (with Ignore / Settings / Quit buttons) and shared emoji grid.
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
                // Tooltips hang below the header: draw them over the grid.
                .zIndex(1)
            Divider()
            // The inline picker has no tabs: it always browses emoji.
            EmojiGridView(model: model, showsTabs: state.mode == .hotkey)
        }
        // Hotkey and inline share the model: don't leave the inline panel on another tab (the model
        // clamps to the first enabled tab when Emoji is off). No sliding: `disablesAnimations` also
        // stops the `.animation(_:value:)` modifiers, which `Transaction(animation: nil)` doesn't.
        .onChange(of: state.mode, initial: true) { _, mode in
            guard mode == .inline else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.tab = .emoji }
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
            if let target = state.ignoreTarget {
                Button {
                    ignore(target)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .panelTooltip(Self.ignoreHelp(target), state: state)
            }
            Button {
                onCancel()
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .panelTooltip("Settings", state: state)
            Button {
                confirmQuit()
            } label: {
                Image(systemName: "power")
            }
            .panelTooltip("Quit FastMoji", state: state)
        }
        .buttonStyle(HoverCapsuleButtonStyle(isCircle: true))
    }

    /// Adds the target to Settings → Ignored, where it can be removed again.
    private func ignore(_ target: IgnoreTarget) {
        onCancel()
        switch target {
        case .app(let bundleID, _): AppSettings.ignoredApps.append(bundleID)
        case .domain(let domain): AppSettings.ignoredDomains.append(domain)
        }
    }

    private static func ignoreHelp(_ target: IgnoreTarget) -> String {
        switch target {
        case .app(_, let name): "Ignore \(name)\nNo inline trigger or hotkey in this app"
        case .domain(let domain): "Ignore \(domain)\nNo inline trigger on this website"
        }
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

private extension View {
    func panelTooltip(_ text: String, state: PickerPanelState) -> some View {
        modifier(PanelTooltip(text: text, state: state))
    }
}

/// `.help` waits about a second and never shows here: FastMoji is never the active app while the
/// panel is up, and the inline panel is not even key. This one shows after a short hover.
private struct PanelTooltip: ViewModifier {
    let text: String
    let state: PickerPanelState
    @State private var showTask: Task<Void, Never>?

    private static let delay: Duration = .milliseconds(250)

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                showTask?.cancel()
                guard hovering else {
                    if state.tooltip == text { withAnimation(.easeOut(duration: 0.1)) { state.tooltip = nil } }
                    return
                }
                showTask = Task {
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.1)) { state.tooltip = text }
                }
            }
            // Trailing-aligned: the buttons sit at the panel's right edge, so it grows to the left.
            .overlay(alignment: .topTrailing) {
                if state.tooltip == text {
                    Text(text)
                        .font(.caption)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        // Below the 26 pt button, with a small gap.
                        .offset(y: 32)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }
}

import AppKit
import SwiftUI

/// Menubar popover: search field, shared emoji grid, Update / Pause and Check for Updates / Settings / About / Quit footer.
/// Enter / click runs `AppSettings.menubarAction`.
struct MenuBarContentView: View {
    let model: EmojiPickerModel
    /// Nil while hosting unit tests (picks are copied).
    let coordinator: AppCoordinator?
    let updater: Updater

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
            if let coordinator, coordinator.isPaused, let until = coordinator.pausedUntil {
                pausedBanner(until: until, coordinator)
                Divider()
            }
            if let secureInput = coordinator?.secureInput, secureInput.isOn {
                secureInputBanner
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
                EmojiInserter.copy(emoji.toned(AppSettings.skinTone))
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

    /// The tap receives no keys while Secure Input is on: say why `::` does nothing.
    private var secureInputBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Secure Input is on: typing triggers are paused")
                .font(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Typing triggers and the hotkey are off until `until`; the picker above still works.
    private func pausedBanner(until: Date, _ coordinator: AppCoordinator) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
            Text("Paused until \(until.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
            Spacer(minLength: 0)
            Button("Resume") { coordinator.resume() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if updater.updateAvailable {
                Button {
                    close()
                    updater.checkForUpdates()
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                }
                .foregroundStyle(.green)
            }
            // While paused, the pause row offers Resume instead.
            if let coordinator, !coordinator.isPaused {
                Button {
                    coordinator.pause()
                } label: {
                    Image(systemName: "pause.circle")
                }
                .buttonStyle(HoverCapsuleButtonStyle(isCircle: true))
                .help("Pause FastMoji for 1 hour")
            }
            Spacer()
            if !updater.updateAvailable {
                Button("Check for Updates…") {
                    close()
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheck)
            }
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
        // Plain logo: the app icon gets a gray backdrop on macOS 26+ (legacy icon format).
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSImage(resource: .appLogo),
            .credits: Self.aboutCredits,
        ])
    }

    /// Centered GitHub link shown under the version in the About panel.
    private static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let url = SettingsView.projectURL
        return NSAttributedString(string: url.absoluteString, attributes: [
            .link: url,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph,
        ])
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
    /// Icon-only buttons: a fixed square, which the capsule turns into a circle.
    var isCircle = false

    func makeBody(configuration: Configuration) -> some View {
        HoverCapsule(configuration: configuration, isCircle: isCircle)
    }

    private struct HoverCapsule: View {
        let configuration: ButtonStyleConfiguration
        let isCircle: Bool
        @State private var isHovered = false

        private static let circleSize: CGFloat = 26

        var body: some View {
            let fill = configuration.isPressed ? 0.24 : isHovered ? 0.16 : 0.07
            configuration.label
                .font(.callout)
                .padding(.horizontal, isCircle ? 0 : 11)
                .padding(.vertical, isCircle ? 0 : 4)
                .frame(width: isCircle ? Self.circleSize : nil, height: isCircle ? Self.circleSize : nil)
                .background(Capsule().fill(Color.primary.opacity(fill)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isHovered ? 0.22 : 0.1), lineWidth: 1))
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

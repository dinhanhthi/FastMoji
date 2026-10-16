import AppKit
import ServiceManagement
import SwiftUI

/// Content of the Settings window. Every control writes straight to `UserDefaults`
/// (`AppSettings.Key`); the coordinator picks the changes up on `didChangeNotification`.
struct SettingsView: View {
    let frecency: FrecencyStore
    let permission: AccessibilityPermission

    @AppStorage(AppSettings.Key.inlineEnabled) private var inlineEnabled = true
    @AppStorage(AppSettings.Key.triggerWindowMs) private var triggerWindowMs = 300
    @AppStorage(AppSettings.Key.inlineAction) private var inlineAction = PickAction.insert
    @AppStorage(AppSettings.Key.hotkeyEnabled) private var hotkeyEnabled = true
    /// Only observed so the recorder label refreshes; read and written through `AppSettings.hotkey`.
    @AppStorage(AppSettings.Key.hotkey) private var hotkeyData = Data()
    @AppStorage(AppSettings.Key.hotkeyAction) private var hotkeyAction = PickAction.insert
    @AppStorage(AppSettings.Key.menubarEnabled) private var menubarEnabled = true
    @AppStorage(AppSettings.Key.menubarAction) private var menubarAction = PickAction.copy
    @AppStorage(AppSettings.Key.insertionMethod) private var insertionMethod = InsertionMethod.type

    /// Edited text of the trigger field; committed on Return or blur, never while typing
    /// (editing "::" to ";;" must not save ":" on the way).
    @State private var triggerDraft = AppSettings.triggerSequence
    @FocusState private var triggerFocused: Bool
    @State private var window = WindowBox()
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var confirmingClear = false

    /// Same bounds as the stored value's clamp.
    private static let triggerWindowSlider = Double(AppSettings.triggerWindowRange.lowerBound)...Double(AppSettings.triggerWindowRange.upperBound)

    var body: some View {
        Form {
            Section { about }
            triggers
            insertion
            general
        }
        .formStyle(.grouped)
        .background(WindowAccessor(box: window))
        .onAppear { refreshLoginStatus() }
        // Back from System Settings (e.g. after approving the login item).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        // Closing keeps the field focused (no blur): commit here so the window reappears with the stored value.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let host = window.window, (note.object as? NSWindow) === host else { return }
            commitTrigger()
        }
    }

    // MARK: - About

    private var about: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("FastMoji")
                    .font(.title2.bold())
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: - Triggers

    private var enabledTriggerCount: Int {
        [inlineEnabled, hotkeyEnabled, menubarEnabled].filter { $0 }.count
    }

    /// Lock-out guard: the last enabled trigger cannot be turned off.
    private func isLastTrigger(_ enabled: Bool) -> Bool {
        enabled && enabledTriggerCount == 1
    }

    private var triggers: some View {
        Section("Triggers") {
            Toggle("Inline trigger", isOn: $inlineEnabled)
                .disabled(isLastTrigger(inlineEnabled))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Trigger", text: $triggerDraft)
                    .focused($triggerFocused)
                    .onSubmit { commitTrigger() }
                    .onChange(of: triggerFocused) { _, focused in
                        if !focused { commitTrigger() }
                    }
                if !AppSettings.isValidTriggerSequence(triggerDraft) {
                    Text("1 to 3 symbols, e.g. :: or ;; (no letters, digits, _ - + or spaces). Must be typable without ⌥.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            LabeledContent("Key window") {
                HStack {
                    Slider(value: triggerWindowBinding, in: Self.triggerWindowSlider, step: 50)
                    Text("\(triggerWindowMs) ms")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            actionPicker("Inline action", selection: $inlineAction)
            Text("Paused while an input method such as Vietnamese Telex is active — use the hotkey instead.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Hotkey", isOn: $hotkeyEnabled)
                .disabled(isLastTrigger(hotkeyEnabled))
            LabeledContent("Shortcut") {
                ShortcutRecorderView(shortcut: hotkeyBinding)
            }
            actionPicker("Hotkey action", selection: $hotkeyAction)

            Toggle("Menubar", isOn: $menubarEnabled)
                .disabled(isLastTrigger(menubarEnabled))
            actionPicker("Menubar action", selection: $menubarAction)

            if enabledTriggerCount == 1 {
                Text("At least one trigger must stay on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Saves a valid draft; an invalid one goes back to the stored sequence.
    private func commitTrigger() {
        if AppSettings.isValidTriggerSequence(triggerDraft) {
            AppSettings.triggerSequence = triggerDraft
        } else {
            triggerDraft = AppSettings.triggerSequence
        }
    }

    private func actionPicker(_ title: String, selection: Binding<PickAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(PickAction.allCases) { action in
                Text(action.title).tag(action)
            }
        }
    }

    private var triggerWindowBinding: Binding<Double> {
        Binding(
            get: {
                min(max(Double(triggerWindowMs), Self.triggerWindowSlider.lowerBound), Self.triggerWindowSlider.upperBound)
            },
            set: { triggerWindowMs = Int($0.rounded()) }
        )
    }

    private var hotkeyBinding: Binding<KeyShortcut> {
        Binding(
            get: {
                _ = hotkeyData
                return AppSettings.hotkey
            },
            set: { AppSettings.hotkey = $0 }
        )
    }

    // MARK: - Insertion

    private var insertion: some View {
        Section("Insertion") {
            Picker("Method", selection: $insertionMethod) {
                ForEach(InsertionMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            Text("Paste works in more apps but briefly uses the clipboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var general: some View {
        Section("General") {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            if loginStatus == .requiresApproval {
                Text("Approve FastMoji in System Settings → General → Login Items")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LabeledContent("Accessibility") {
                if permission.isTrusted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Not granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Grant Accessibility") { permission.request() }
                    }
                }
            }

            LabeledContent("History") {
                Button("Clear history…", role: .destructive) { confirmingClear = true }
            }
            .confirmationDialog("Clear the Frequently Used history?", isPresented: $confirmingClear) {
                Button("Clear history", role: .destructive) { frecency.clear() }
            }
        }
    }

    /// Written through `SMAppService`, read back from its status (a failed call leaves it unchanged).
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }
}

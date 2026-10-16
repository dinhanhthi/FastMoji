import AppKit
import ServiceManagement
import SwiftUI

/// Content of the Settings window. Every control writes straight to `UserDefaults`
/// (`AppSettings.Key`); the coordinator picks the changes up on `didChangeNotification`.
struct SettingsView: View {
    let frecency: FrecencyStore
    let permission: AccessibilityPermission
    let updater: Updater

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
    @AppStorage(AppSettings.Key.skinTone) private var skinTone = SkinTone.none

    /// Edited text of the trigger field; committed on Return or blur, never while typing
    /// (editing "::" to ";;" must not save ":" on the way).
    @State private var triggerDraft = AppSettings.triggerSequence
    @FocusState private var triggerFocused: Bool
    @State private var window = WindowBox()
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var confirmingClear = false
    @State private var pane: Pane? = .general

    /// Same bounds as the stored value's clamp.
    private static let triggerWindowSlider = Double(AppSettings.triggerWindowRange.lowerBound)...Double(AppSettings.triggerWindowRange.upperBound)

    enum Pane: String, CaseIterable, Identifiable {
        case general, triggers, insertion

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .triggers: "Triggers"
            case .insertion: "Insertion"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .triggers: "bolt"
            case .insertion: "text.cursor"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Form {
                switch pane ?? .general {
                case .general: general
                case .triggers: triggers
                case .insertion: insertion
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .capsuleButtons()
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $pane) {
            ForEach(Pane.allCases) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
        }
        .listStyle(.sidebar)
        // Outside the List: a section header is indented, which pushed the logo off-centre.
        .safeAreaInset(edge: .top) {
            about
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .navigationSplitViewColumnWidth(190)
        // No toolbar in this window: keep the sidebar from being collapsed out of reach.
        .toolbar(removing: .sidebarToggle)
    }

    private var about: some View {
        VStack(spacing: 6) {
            // Not applicationIconImage: macOS 26+ adds a gray backdrop to legacy icons.
            Image(.appLogo)
                .resizable()
                .frame(width: 56, height: 56)
            Text("FastMoji")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Version \(Self.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private var triggers: some View {
        Section {
            Toggle("Enabled", isOn: $inlineEnabled)
                .disabled(isLastTrigger(inlineEnabled))
            Group {
                inlineOptions
            }
            .disabled(!inlineEnabled)
        } header: {
            sectionHeader("Inline", description: "Type the trigger in any text field, keep typing to search, then press Return or Tab to insert. Paused while an input method such as Vietnamese Telex is active — use the hotkey instead.")
        }

        Section {
            Toggle("Enabled", isOn: $hotkeyEnabled)
                .disabled(isLastTrigger(hotkeyEnabled))
            Group {
                LabeledContent("Shortcut") {
                    ShortcutRecorderView(shortcut: hotkeyBinding)
                }
                actionPicker("Action", selection: $hotkeyAction)
            }
            .disabled(!hotkeyEnabled)
        } header: {
            sectionHeader("Hotkey", description: "Opens a search panel at the text caret in any app.")
        }

        Section {
            Toggle("Enabled", isOn: $menubarEnabled)
                .disabled(isLastTrigger(menubarEnabled))
            actionPicker("Action", selection: $menubarAction)
                .disabled(!menubarEnabled)
        } header: {
            sectionHeader("Menubar", description: menubarDescription)
        }
    }

    private var menubarDescription: String {
        let base = "Click the menubar icon to search. When it is off, reopen FastMoji from Finder or Spotlight to get back here."
        return enabledTriggerCount == 1 ? base + " At least one trigger must stay on." : base
    }

    @ViewBuilder
    private var inlineOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Trigger", text: $triggerDraft, prompt: Text("::"))
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
        actionPicker("Action", selection: $inlineAction)
    }

    /// Saves a valid draft; an invalid one goes back to the stored sequence.
    private func commitTrigger() {
        if AppSettings.isValidTriggerSequence(triggerDraft) {
            AppSettings.triggerSequence = triggerDraft
        } else {
            triggerDraft = AppSettings.triggerSequence
        }
    }

    /// Section title with its description right below it (not in the footer, far from the title).
    private func sectionHeader(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.caption)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        Section {
            Picker("Method", selection: $insertionMethod) {
                ForEach(InsertionMethod.allCases) { method in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.title)
                        Text(Self.explanation(of: method))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 6)
                    .tag(method)
                }
            }
            .pickerStyle(.radioGroup)
        } header: {
            sectionHeader("Method", description: "How FastMoji puts the emoji into the app you are typing in, when a trigger's action is Insert or Insert & Copy.")
        }
    }

    private static func explanation(of method: InsertionMethod) -> String {
        switch method {
        case .type:
            "Types the emoji as if it came from the keyboard. Your clipboard is never touched. Works in almost every app."
        case .paste:
            "Puts the emoji on the clipboard, presses ⌘V, then restores your previous clipboard. Use it if an app (e.g. some terminals or remote desktops) shows the wrong character with Type."
        }
    }

    // MARK: - General

    @ViewBuilder
    private var general: some View {
        Section {
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

            LabeledContent("Updates") {
                HStack {
                    if updater.updateAvailable {
                        Label("Update available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }

            LabeledContent("History") {
                Button("Clear history…", role: .destructive) { confirmingClear = true }
            }
            .confirmationDialog("Clear the Frequently Used history?", isPresented: $confirmingClear) {
                Button("Clear history", role: .destructive) { frecency.clear() }
            }
        }

        Section {
            Picker("Skin tone", selection: $skinTone) {
                ForEach(SkinTone.allCases) { tone in
                    Text(Self.toneSample.toned(tone))
                        .help(tone.title)
                        .tag(tone)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            sectionHeader("Emoji", description: "Applies to people, hands and body parts. Smileys have no skin tone in Unicode and stay yellow.")
        }
    }

    /// 👋 shown in each tone by the skin tone picker.
    private static let toneSample = Emoji(emoji: "👋", description: "", category: "", aliases: [], tags: [], skinTones: true)

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

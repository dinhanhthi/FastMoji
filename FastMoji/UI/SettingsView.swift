import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage(AppSettings.Key.emoticonsEnabled) private var emoticonsEnabled = false
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
    /// Mirrors of the stored lists, re-read after each write so they show the normalized, deduplicated value.
    @State private var ignoredApps = AppSettings.ignoredApps
    @State private var ignoredDomains = AppSettings.ignoredDomains
    @State private var domainDraft = ""
    @State private var customAliases = AppSettings.customAliases
    @State private var aliasDraft = ""
    @State private var aliasTextDraft = ""

    /// Same bounds as the stored value's clamp.
    private static let triggerWindowSlider = Double(AppSettings.triggerWindowRange.lowerBound)...Double(AppSettings.triggerWindowRange.upperBound)

    enum Pane: String, CaseIterable, Identifiable {
        case general, triggers, insertion, aliases, ignored

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .triggers: "Triggers"
            case .insertion: "Insertion"
            case .aliases: "Aliases"
            case .ignored: "Ignored"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .triggers: "bolt"
            case .insertion: "text.cursor"
            case .aliases: "text.badge.plus"
            case .ignored: "nosign"
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
                case .aliases: aliases
                case .ignored: ignored
                }
            }
            .formStyle(.grouped)
            .toggleStyle(LightSwitchToggleStyle())
            .navigationTitle((pane ?? .general).title)
        }
        .capsuleButtons()
        .background(WindowAccessor(box: window))
        .onAppear { refreshLoginStatus() }
        // Back from System Settings (e.g. after approving the login item).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
            // Also changed by the panel's Ignore button while this (reused) view was closed.
            ignoredApps = AppSettings.ignoredApps
            ignoredDomains = AppSettings.ignoredDomains
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
                .padding(.horizontal, 10)
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
            Link("GitHub", destination: Self.projectURL)
                .buttonStyle(.link)
                .font(.caption)
                .help(Self.projectURL.absoluteString)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static let projectURL = URL(string: "https://github.com/dinhanhthi/FastMoji")!

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

        // Not a trigger: it never opens the picker, so the lock-out guard ignores it.
        Section {
            // Verbatim: keeps ":)" out of Markdown and localization.
            Toggle(isOn: $emoticonsEnabled) { Text(verbatim: "Convert emoticons like :) to emoji") }
        } header: {
            sectionHeader("Emoticons", description: "Typed after a space, followed by a space: :) :( :D ;) :P <3 and more. Off by default.")
        }
    }

    private var menubarDescription: String {
        let base = "Click the menubar icon to search. Turning it off also hides the menubar icon: reopen FastMoji from Finder or Spotlight to get back here."
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

    // MARK: - Aliases

    @ViewBuilder
    private var aliases: some View {
        Section {
            if customAliases.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(customAliases) { entry in
                HStack {
                    Text(entry.alias)
                        .monospaced()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    removeButton { setCustomAliases(customAliases.filter { $0.alias != entry.alias }) }
                }
            }
            TextField("Alias", text: $aliasDraft, prompt: Text("shrug"))
                .onSubmit { addAlias() }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Verbatim: as Markdown, the backslash would be dropped.
                    TextField("Text", text: $aliasTextDraft, prompt: Text(verbatim: "¯\\_(ツ)_/¯"))
                        .onSubmit { addAlias() }
                    Button("Add") { addAlias() }
                        .disabled(!canAddAlias)
                }
                if let aliasDraftError {
                    Text(aliasDraftError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            sectionHeader("Custom aliases", description: aliasesDescription)
        }
    }

    /// Uses the current trigger: the closing delimiter is its last character.
    private var aliasesDescription: String {
        let sequence = AppSettings.triggerSequence
        return "Type \(sequence)alias\(sequence.suffix(1)) or search for the alias to insert your own text, such as ¯\\_(ツ)_/¯ for shrug. Custom aliases win over built-in ones."
    }

    /// Alias draft as stored: trimmed and lowercased.
    private var normalizedAliasDraft: String {
        aliasDraft.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var canAddAlias: Bool {
        aliasDraftError == nil && AppSettings.isValidCustomAlias(alias: normalizedAliasDraft, text: aliasTextDraft)
    }

    /// What is wrong with a non-empty draft field (the same checks as `AppSettings.isValidCustomAlias`).
    private var aliasDraftError: String? {
        let alias = normalizedAliasDraft
        if !alias.isEmpty {
            if alias.count > TriggerDetector.maxQueryLength || !alias.allSatisfy(TriggerDetector.isQueryCharacter) {
                return "Alias: 1 to \(TriggerDetector.maxQueryLength) letters (a-z), digits, _ - or +."
            }
            if customAliases.contains(where: { $0.alias == alias }) {
                return "\"\(alias)\" already exists. Remove it first to change its text."
            }
        }
        let text = aliasTextDraft
        if !text.isEmpty {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Text: enter something to insert."
            }
            if text.contains(where: \.isNewline) || text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                return "Text: a single line, without control characters."
            }
            if text.utf16.count > AppSettings.maxCustomAliasTextLength {
                return "Text: at most \(AppSettings.maxCustomAliasTextLength) characters."
            }
        }
        return nil
    }

    private func addAlias() {
        guard canAddAlias else { return }
        setCustomAliases(customAliases + [CustomAlias(alias: normalizedAliasDraft, text: aliasTextDraft)])
        aliasDraft = ""
        aliasTextDraft = ""
    }

    private func setCustomAliases(_ aliases: [CustomAlias]) {
        AppSettings.customAliases = aliases
        customAliases = AppSettings.customAliases
    }

    // MARK: - Ignored

    @ViewBuilder
    private var ignored: some View {
        Section {
            if ignoredApps.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(ignoredApps, id: \.self) { bundleID in
                HStack {
                    appLabel(bundleID)
                    Spacer()
                    removeButton { setIgnoredApps(ignoredApps.filter { $0 != bundleID }) }
                }
            }
            Button("Add App…") { addApps() }
        } header: {
            sectionHeader("Apps", description: "FastMoji ignores the inline trigger and the hotkey in these apps: their keys reach the app untouched. The menubar still works.")
        }

        Section {
            if ignoredDomains.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }
            ForEach(ignoredDomains, id: \.self) { domain in
                HStack {
                    Text(domain)
                    Spacer()
                    removeButton { setIgnoredDomains(ignoredDomains.filter { $0 != domain }) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Domain", text: $domainDraft, prompt: Text("example.com"))
                        .onSubmit { addDomain() }
                    Button("Add") { addDomain() }
                        .disabled(AppSettings.normalizedDomain(domainDraft) == nil)
                }
                if !domainDraft.isEmpty && AppSettings.normalizedDomain(domainDraft) == nil {
                    Text("Enter a domain such as github.com.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            sectionHeader("Websites", description: "The inline trigger is off on these sites and their subdomains, e.g. github.com also covers gist.github.com. The hotkey still works. Works in Safari, Chrome-based browsers and Firefox.")
        }
    }

    /// Icon and name of an installed app; the raw bundle ID when it is not installed.
    @ViewBuilder
    private func appLabel(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(FileManager.default.displayName(atPath: url.path))
            }
            .help(bundleID)
        } else {
            Label(bundleID, systemImage: "app.dashed")
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help("Remove")
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        // FastMoji itself is never ignored: its own panel must keep working.
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .filter { $0 != Bundle.main.bundleIdentifier }
        setIgnoredApps(ignoredApps + added)
    }

    private func addDomain() {
        guard let domain = AppSettings.normalizedDomain(domainDraft) else { return }
        setIgnoredDomains(ignoredDomains + [domain])
        domainDraft = ""
    }

    private func setIgnoredApps(_ apps: [String]) {
        AppSettings.ignoredApps = apps
        ignoredApps = AppSettings.ignoredApps
    }

    private func setIgnoredDomains(_ domains: [String]) {
        AppSettings.ignoredDomains = domains
        ignoredDomains = AppSettings.ignoredDomains
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

            LabeledContent("Welcome") {
                Button("Show Welcome…") { WelcomeWindowController.shared.show() }
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

/// Switch drawn in SwiftUI: the system switch (NSSwitch) allocates ~130 MB on its first render (macOS 27).
private struct LightSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            // A Button, not a tap gesture: keyboard navigation can focus it and Space toggles it.
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 36, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                            .padding(2)
                    }
                    .opacity(isEnabled ? 1 : 0.5)
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

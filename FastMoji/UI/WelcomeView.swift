import SwiftUI

/// Content of the welcome window: the three ways to use FastMoji, the Accessibility state and a
/// live test field. The test field is a real host field: the inline trigger works in it
/// (`AppCoordinator` exempts it from the own-window guard).
struct WelcomeView: View {
    let permission: AccessibilityPermission

    /// Only observed so the labels refresh when Settings changes them; read through `AppSettings`.
    @AppStorage(AppSettings.Key.triggerSequence) private var storedTrigger = AppSettings.defaultTriggerSequence
    @AppStorage(AppSettings.Key.hotkey) private var hotkeyData = Data()

    @State private var testText = ""
    @State private var window = WindowBox()

    var body: some View {
        // Shown verbatim: a custom trigger such as `**` must not be read as Markdown.
        let trigger = AppSettings.triggerSequence
        let hotkey = AppSettings.hotkey.label
        VStack(spacing: 0) {
            Form {
                Section {
                    header
                }

                Section {
                    way("Inline", icon: "text.cursor",
                        detail: "Type \(trigger)smile then Return, or \(trigger)smile: to insert instantly.")
                    way("Hotkey", icon: "keyboard",
                        detail: "Press \(hotkey) in any app to open the picker at the caret.")
                    way("Menu bar", icon: "menubar.rectangle",
                        detail: "Click the FastMoji icon in the menu bar to browse every emoji.")
                } header: {
                    Text("Three ways to insert an emoji")
                }

                Section {
                    LabeledContent("Accessibility") {
                        if permission.isTrusted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            // Prompts only on click: never at launch.
                            Button("Grant Accessibility") { permission.request() }
                        }
                    }
                    Text("Needed to find the caret and type the emoji. FastMoji never records keystrokes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "The \(trigger) trigger pauses while an input method such as Vietnamese Telex is active; use \(hotkey) instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Setup")
                }

                Section {
                    TextField("Test field", text: $testText, prompt: Text(verbatim: "Type \(trigger)smile:"))
                        .labelsHidden()
                } header: {
                    Text("Try it here")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Get Started") { window.window?.close() }
                    .controlSize(.large)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .capsuleButtons()
        .background(WindowAccessor(box: window))
    }

    private var header: some View {
        VStack(spacing: 6) {
            // Not applicationIconImage: macOS 26+ adds a gray backdrop to legacy icons.
            Image(.appLogo)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Welcome to FastMoji")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Emoji, symbols and kaomoji in any text field, from the keyboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func way(_ title: String, icon: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
        }
    }
}

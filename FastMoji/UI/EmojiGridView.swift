import AppKit
import SwiftUI

/// Emoji grid + description footer, driven entirely by `EmojiPickerModel`.
/// ~400x320; the hosting surface adds its search field on top (~360 total).
struct EmojiGridView: View {
    let model: EmojiPickerModel

    private static let cellSize: CGFloat = 36
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: EmojiPickerModel.columns
    )

    var body: some View {
        VStack(spacing: 0) {
            if model.sections.isEmpty {
                emptyState
            } else {
                grid
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 320)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        Section {
                            ForEach(Array(section.emojis.enumerated()), id: \.element.id) { index, emoji in
                                cell(emoji, section: section, sectionIndex: sectionIndex, index: index)
                            }
                        } header: {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onAppear { scrollToSelection(proxy) }
            .onChange(of: model.selection) { _, _ in scrollToSelection(proxy) }
            // Typing often keeps the selection at (0, 0); still jump back to the first result.
            .onChange(of: model.query) { _, _ in scrollToSelection(proxy) }
            // Reopening keeps the selection at (0, 0) too; scroll back to the top on every reset.
            .onChange(of: model.resetCount) { _, _ in scrollToSelection(proxy) }
        }
    }

    private func cell(_ emoji: Emoji, section: PickerSection, sectionIndex: Int, index: Int) -> some View {
        let isSelected = model.selection == PickerSelection(section: sectionIndex, index: index)
        return Text(emoji.emoji)
            .font(.system(size: 24))
            .frame(maxWidth: .infinity, minHeight: Self.cellSize, maxHeight: Self.cellSize)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.select(emoji, in: sectionIndex)
                model.confirm()
            }
            .id(Self.cellID(section, emoji))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
            Text("No emoji found")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        Text(model.selectedEmoji.map { Self.capitalizedFirst($0.description) } ?? "No results")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 28)
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let selection = model.selection else { return }
        let section = model.sections[selection.section]
        proxy.scrollTo(Self.cellID(section, section.emojis[selection.index]), anchor: nil)
    }

    /// Uppercases only the first letter so acronyms ("OK hand", "ZZZ") are kept.
    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Unique across sections (an emoji can be both "Frequently Used" and in its category).
    private static func cellID(_ section: PickerSection, _ emoji: Emoji) -> String {
        "\(section.id)-\(emoji.emoji)"
    }
}

// MARK: - Keyboard

extension View {
    /// Arrows move the selection, Return/Enter confirms, Esc calls `onCancel`.
    /// Local key monitor (hotkey + menubar surfaces); the inline panel is driven by the event tap instead.
    /// Only key events sent to `window` (the hosting window) are handled; every other window is untouched.
    func pickerKeyMonitor(
        _ model: EmojiPickerModel,
        window: WindowBox,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(PickerKeyMonitor(model: model, window: window, onCancel: onCancel))
    }
}

private struct PickerKeyMonitor: ViewModifier {
    let model: EmojiPickerModel
    let window: WindowBox
    let onCancel: () -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: uninstall)
    }

    private func install() {
        uninstall()
        let model = model
        let box = window
        let onCancel = onCancel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors are called on the main thread.
            let handled = MainActor.assumeIsolated {
                Self.handle(event, host: box.window, model: model, onCancel: onCancel)
            }
            return handled ? nil : event
        }
    }

    private func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Returns true when the key was handled (and must be swallowed).
    @MainActor
    private static func handle(
        _ event: NSEvent,
        host: NSWindow?,
        model: EmojiPickerModel,
        onCancel: () -> Void
    ) -> Bool {
        guard let host, event.window === host else { return false }
        // Shortcuts (cmd+A, shift+arrows, ...) keep their text-field meaning.
        // Not "flags are empty": arrow keys always carry .numericPad and .function.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.shift, .option, .command, .control]) else { return false }
        // IME composition (e.g. Vietnamese Telex) owns Return/arrows/Esc until it commits.
        if let editor = host.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        switch event.keyCode {
        case 123: model.move(.left)
        case 124: model.move(.right)
        case 125: model.move(.down)
        case 126: model.move(.up)
        case 36, 76: model.confirm()
        case 53: onCancel()
        default: return false
        }
        return true
    }
}

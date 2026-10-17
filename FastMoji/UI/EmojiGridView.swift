import AppKit
import SwiftUI

/// Navigation row (tabs + section icons), emoji grid and description footer, driven entirely by
/// `EmojiPickerModel`. ~400x320; the hosting surface adds its search field on top (~360 total).
struct EmojiGridView: View {
    let model: EmojiPickerModel
    /// Emoji / Symbols / Kaomoji tabs (hotkey and menubar pickers; the inline picker stays on emoji).
    let showsTabs: Bool

    @AppStorage(AppSettings.Key.skinTone) private var skinTone = SkinTone.none
    /// Cells drawn by the lazy grids; `scrollTo` only reaches those (not observed: no redraws).
    @State private var realizedCells = RealizedCells()

    private static let cellSize: CGFloat = 36
    private static let rowHeight: CGFloat = 28

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
            VStack(spacing: 0) {
                // Browsing only: a search lists one section per kind, whatever the tab.
                if model.query.isEmpty {
                    navigation(proxy)
                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                            sectionView(section, sectionIndex: sectionIndex)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onAppear { scrollToSelection(proxy, toTop: true) }
                .onChange(of: model.selection) { _, _ in scrollToSelection(proxy) }
                // Typing often keeps the selection at (0, 0); still jump back to the first result.
                .onChange(of: model.query) { _, _ in scrollToSelection(proxy, toTop: true) }
                // Same for a tab switch (the selection may stay at (0, 0)).
                .onChange(of: model.tab) { _, _ in scrollToSelection(proxy, toTop: true) }
                // Reopening keeps the selection at (0, 0) too; scroll back to the top on every reset.
                .onChange(of: model.resetCount) { _, _ in scrollToSelection(proxy, toTop: true) }
            }
        }
    }

    /// Header + its own grid (emoji and symbols: 9 columns, kaomoji: 3). The id is the section's,
    /// so `scrollTo` reaches it even before the lazy stack has drawn it.
    private func sectionView(_ section: PickerSection, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 2)
            // Flexible, not fixed: a legacy scroller takes ~15 pt of the width.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: section.columns),
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(Array(section.emojis.enumerated()), id: \.element.id) { index, emoji in
                    cell(emoji, section: section, sectionIndex: sectionIndex, index: index)
                }
            }
        }
        .id(section.id)
    }

    private func cell(_ emoji: Emoji, section: PickerSection, sectionIndex: Int, index: Int) -> some View {
        let isSelected = model.selection == PickerSelection(section: sectionIndex, index: index)
        let id = Self.cellID(section, emoji)
        return cellLabel(emoji)
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
            .onAppear { realizedCells.ids.insert(id) }
            .onDisappear { realizedCells.ids.remove(id) }
            .id(id)
    }

    /// Emoji keep their colors; symbols are text glyphs; kaomoji are short lines of text.
    @ViewBuilder
    private func cellLabel(_ emoji: Emoji) -> some View {
        switch emoji.kind {
        case nil:
            Text(emoji.toned(skinTone))
                .font(.system(size: 24))
        case .symbol:
            Text(emoji.emoji)
                .font(.system(size: 22))
                .foregroundStyle(.primary)
        case .kaomoji:
            Text(emoji.emoji)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Navigation

    /// Tabs (when shown) above one icon button per section of the current tab.
    /// Two rows: the three tabs and up to 11 icons don't fit in 400 pt.
    private func navigation(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if showsTabs {
                tabs
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
            }
            sectionButtons(proxy)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        }
        .padding(.horizontal, 8)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PickerTab.allCases, id: \.self) { tab in
                Button(tab.title) { model.tab = tab }
                    .buttonStyle(HoverCapsuleButtonStyle())
                    .background(highlight(tab == model.tab))
            }
        }
    }

    /// Each button selects the first cell of its section and scrolls its header to the top;
    /// the section holding the selection is highlighted.
    private func sectionButtons(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                Button {
                    model.jump(to: sectionIndex)
                    // Also when its first cell was already selected (no selection change then).
                    proxy.scrollTo(section.id, anchor: .top)
                } label: {
                    sectionIcon(section.title)
                }
                .buttonStyle(HoverCapsuleButtonStyle(isCircle: true))
                .background(highlight(model.selection?.section == sectionIndex))
                .help(section.title)
            }
        }
    }

    /// Same accent as a selected cell.
    @ViewBuilder
    private func highlight(_ isOn: Bool) -> some View {
        if isOn {
            Capsule().fill(Color.accentColor.opacity(0.25))
        }
    }

    /// The SF Symbol of `title`, else its first letter.
    @ViewBuilder
    private func sectionIcon(_ title: String) -> some View {
        if let symbol = Self.sectionSymbols[title] {
            Image(systemName: symbol)
        } else {
            Text(title.prefix(1))
                .font(.caption.weight(.semibold))
        }
    }

    /// Keyed by section title: emoji, symbol and kaomoji categories, plus "Frequently Used".
    private static let sectionSymbols: [String: String] = [
        "Frequently Used": "clock",
        // Emoji
        "Smileys & Emotion": "face.smiling",
        "People & Body": "person",
        "Animals & Nature": "pawprint",
        "Food & Drink": "fork.knife",
        "Travel & Places": "car",
        "Activities": "soccerball",
        "Objects": "lightbulb",
        "Symbols": "heart",
        "Flags": "flag",
        // Symbols
        "Keyboard": "command",
        "Arrows": "arrow.right",
        "Currency": "dollarsign.circle",
        "Math": "plus.forwardslash.minus",
        "Typography": "textformat",
        "Checkboxes": "checkmark.square",
        // Kaomoji
        "Happy": "sun.max",
        "Love": "heart.circle",
        "Sad": "cloud.rain",
        "Angry": "flame",
        "Surprised": "exclamationmark",
        "Shrug": "person.fill.questionmark",
        "Table flip": "table.furniture",
        "Animals": "pawprint.circle",
        "Greeting": "hand.wave",
        "Action": "figure.run",
    ]

    // MARK: Empty state, footer, scrolling

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
            .frame(height: Self.rowHeight)
    }

    /// `scrollTo` can't reach a cell the lazy grids haven't drawn (far away): scroll its section
    /// header to the top first (sections are always reachable), then the cell on the next run loop
    /// turn. `toTop` always does that (first result, tab switch, reopen).
    private func scrollToSelection(_ proxy: ScrollViewProxy, toTop: Bool = false) {
        guard let selection = model.selection else { return }
        let section = model.sections[selection.section]
        let cellID = Self.cellID(section, section.emojis[selection.index])
        if !toTop, realizedCells.ids.contains(cellID) {
            proxy.scrollTo(cellID, anchor: nil)
            return
        }
        proxy.scrollTo(section.id, anchor: .top)
        DispatchQueue.main.async { proxy.scrollTo(cellID, anchor: nil) }
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

/// Ids of the cells the lazy grids have drawn. A plain class: updating it never redraws the grid.
@MainActor
private final class RealizedCells {
    var ids: Set<String> = []
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

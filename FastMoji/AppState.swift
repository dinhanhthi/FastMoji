import Foundation

/// App-wide shared state: one catalog, search index and history, created once at launch.
@MainActor
final class AppState {
    let catalog: [Emoji]
    let search: EmojiSearch
    let frecency: FrecencyStore
    /// Picker shown by the menubar popover.
    let menuBarPicker: EmojiPickerModel

    init() {
        AppSettings.registerDefaults()
        catalog = EmojiCatalog.load()
        search = EmojiSearch(catalog: catalog)
        frecency = FrecencyStore()
        menuBarPicker = EmojiPickerModel(catalog: catalog, search: search, frecency: frecency)
    }
}

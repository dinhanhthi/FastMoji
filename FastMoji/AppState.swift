import Foundation

/// App-wide shared state: one catalog, search index and history, created once at launch.
@MainActor
final class AppState {
    /// Search, glyph lookup and sections shared by every picker (one index in RAM).
    let pickerCatalog: PickerCatalog
    let frecency: FrecencyStore
    /// Picker shown by the menubar popover.
    let menuBarPicker: EmojiPickerModel

    init() {
        AppSettings.registerDefaults()
        // The decoded rows (with keywords) are only needed to build the index, then freed.
        pickerCatalog = PickerCatalog(search: EmojiSearch(index: CatalogIndex(catalog: EmojiCatalog.load())))
        frecency = FrecencyStore()
        menuBarPicker = EmojiPickerModel(catalog: pickerCatalog, frecency: frecency)
    }
}

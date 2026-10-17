import Foundation

/// App-wide shared state: one catalog, search index and history, created once at launch.
@MainActor
final class AppState {
    /// Glyph lookup and sections shared by every picker (one index in RAM).
    let pickerCatalog: PickerCatalog
    /// Catalog index plus the user's custom aliases; replaced by `setCustomAliases(_:)`.
    private(set) var search: EmojiSearch
    let frecency: FrecencyStore
    /// Kinds shown by every picker; replaced by `setEnabledKinds(_:)`.
    private(set) var enabledKinds: ContentKinds
    /// Picker shown by the menubar popover.
    let menuBarPicker: EmojiPickerModel
    /// Every picker, so a new `search` reaches all of them. All live as long as the app.
    private var pickers: [EmojiPickerModel]

    init() {
        AppSettings.registerDefaults()
        // The decoded rows (with keywords) are only needed to build the index, then freed.
        let index = CatalogIndex(catalog: EmojiCatalog.load())
        pickerCatalog = PickerCatalog(index: index)
        search = EmojiSearch(index: index, customAliases: AppSettings.customAliases)
        frecency = FrecencyStore()
        enabledKinds = AppSettings.enabledKinds
        menuBarPicker = EmojiPickerModel(
            catalog: pickerCatalog, search: search, frecency: frecency, enabledKinds: enabledKinds
        )
        pickers = [menuBarPicker]
    }

    /// A picker sharing the catalog, search and history, kept current by `setCustomAliases(_:)`
    /// and `setEnabledKinds(_:)`.
    func makePicker() -> EmojiPickerModel {
        let picker = EmojiPickerModel(
            catalog: pickerCatalog, search: search, frecency: frecency, enabledKinds: enabledKinds
        )
        pickers.append(picker)
        return picker
    }

    /// Rebuilds only the custom layer over the shared index and pushes it to every picker.
    func setCustomAliases(_ aliases: [CustomAlias]) {
        search = EmojiSearch(index: search.index, customAliases: aliases)
        for picker in pickers {
            picker.replaceSearch(search)
        }
    }

    /// Pushes the kinds to every picker (no index rebuild: the search filters at query time).
    func setEnabledKinds(_ kinds: ContentKinds) {
        enabledKinds = kinds
        for picker in pickers {
            picker.enabledKinds = kinds
        }
    }
}

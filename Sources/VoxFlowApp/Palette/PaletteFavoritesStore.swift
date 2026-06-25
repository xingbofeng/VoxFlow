import Foundation

protocol PaletteFavoritesStoring: AnyObject {
    func favoriteIDs() -> [PaletteRootItemID]
    func isFavorite(_ id: PaletteRootItemID) -> Bool
    func addFavorite(_ id: PaletteRootItemID)
    func removeFavorite(_ id: PaletteRootItemID)
}

final class UserDefaultsPaletteFavoritesStore: PaletteFavoritesStoring {
    static let favoritesKey = "Palette.RootSearch.Favorites"
    static let customizedKey = "Palette.RootSearch.Favorites.Customized"

    private let defaults: UserDefaults
    private let seed: [PaletteRootItemID]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        seed: [PaletteRootItemID] = [.command(.recentAssets)]
    ) {
        self.defaults = defaults
        self.seed = seed
    }

    func favoriteIDs() -> [PaletteRootItemID] {
        guard let data = defaults.data(forKey: Self.favoritesKey) else {
            return defaults.bool(forKey: Self.customizedKey) ? [] : seed
        }
        return (try? decoder.decode([PaletteRootItemID].self, from: data))
            ?? (defaults.bool(forKey: Self.customizedKey) ? [] : seed)
    }

    func isFavorite(_ id: PaletteRootItemID) -> Bool {
        favoriteIDs().contains(id)
    }

    func addFavorite(_ id: PaletteRootItemID) {
        var ids = favoriteIDs()
        guard !ids.contains(id) else {
            markCustomized()
            persist(ids)
            return
        }
        ids.append(id)
        markCustomized()
        persist(ids)
    }

    func removeFavorite(_ id: PaletteRootItemID) {
        let ids = favoriteIDs().filter { $0 != id }
        markCustomized()
        persist(ids)
    }

    private func markCustomized() {
        defaults.set(true, forKey: Self.customizedKey)
    }

    private func persist(_ ids: [PaletteRootItemID]) {
        guard let data = try? encoder.encode(ids) else { return }
        defaults.set(data, forKey: Self.favoritesKey)
    }
}

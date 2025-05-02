//
//  FavoritesManager.swift
//  CryptoSage
//
//  Created by DM on 6/3/25.
//

import Foundation
import Combine

final class FavoritesManager: ObservableObject {
    // The single UserDefaults key under which we store the Set of IDs
    private let defaultsKey = "favoriteCoinIDs"

    // Published set of IDs. Whenever this changes, SwiftUI views bound to it will update.
    @Published private(set) var favoriteIDs: Set<String> = []
    /// Expose a read-only alias named `favorites` so views can bind to `favoriteIDs`.
    var favorites: Set<String> { favoriteIDs }

    // Make it a shared singleton
    static let shared = FavoritesManager()

    private var cancellables = Set<AnyCancellable>()

    /// Emits the set of favoriteIDs only after a 0.5s pause, and only when it changes.
    var debouncedFavoriteIDs: AnyPublisher<Set<String>, Never> {
        $favoriteIDs
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private init() {
        loadFromDefaults()

        // Whenever favoriteIDs changes, write it back to UserDefaults
        $favoriteIDs
            .sink { [weak self] newSet in
                self?.saveToDefaults(newSet)
            }
            .store(in: &cancellables)

        debouncedFavoriteIDs
            .sink { ids in
                let idsArray = Array(ids)
                Task {
                    do {
                        _ = try await CryptoAPIService.shared.fetchWatchlistMarkets(ids: idsArray)
                    } catch {
                        print("Watchlist fetch failed: \(error.localizedDescription)")
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func loadFromDefaults() {
        if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            favoriteIDs = Set(saved)
        }
    }

    private func saveToDefaults(_ set: Set<String>) {
        let array = Array(set)
        UserDefaults.standard.set(array, forKey: defaultsKey)
    }

    // MARK: - Public API

    func isFavorite(coinID: String) -> Bool {
        favoriteIDs.contains(coinID)
    }

    func addToFavorites(coinID: String) {
        favoriteIDs.insert(coinID)
    }

    func removeFromFavorites(coinID: String) {
        favoriteIDs.remove(coinID)
    }

    func toggle(coinID: String) {
        print("FavoritesManager.toggle called for \(coinID). Currently favoriteIDs = \(favoriteIDs)")
        if isFavorite(coinID: coinID) {
            removeFromFavorites(coinID: coinID)
        } else {
            addToFavorites(coinID: coinID)
        }
    }

    /// Alias for `removeFromFavorites(_:)` so callers can use `remove(coinID:)`
    func remove(coinID: String) {
        removeFromFavorites(coinID: coinID)
    }

    /// Return all favorite IDs as a Set<String>.
    func getAllIDs() -> Set<String> {
        return favoriteIDs
    }
}

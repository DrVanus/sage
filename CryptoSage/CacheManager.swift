//
//  CacheManager.swift
//  CryptoSage
//
//  Created by <you> on <today’s date>.
//

import Foundation

/// A simple “load/write JSON to Documents” helper.
/// Usage in your ViewModels/Services:
///    let cachedCoins = CacheManager.shared.load([Coin].self, from: "coins_cache.json")
///    CacheManager.shared.save(coinsArray, to: "coins_cache.json")
///
final class CacheManager {
    static let shared = CacheManager()
    private init() { }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Load a Decodable array/object from a JSON file in Documents.
    func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("CacheManager: failed to load \(filename): \(error)")
            #endif
            return nil
        }
    }

    /// Save an Encodable object/array to a JSON file in Documents.
    func save<T: Encodable>(_ object: T, to filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(object)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("CacheManager: failed to save \(filename): \(error)")
            #endif
        }
    }

    /// Optional: Delete a cache file
    func delete(_ filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

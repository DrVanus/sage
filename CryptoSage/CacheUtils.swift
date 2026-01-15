import Foundation

public func loadCache<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let decoder = JSONDecoder()
    let fileManager = FileManager.default

    // 1. Attempt to load from Documents directory
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let fileURL = documentsURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try decoder.decode(T.self, from: data)
                return decoded
            } catch {
                print("[CacheUtils] Failed to load or decode \(fileName) from Documents directory: \(error)")
            }
        }
    }

    // 2. Fallback: Attempt to load from main bundle
    if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
        do {
            let data = try Data(contentsOf: bundleURL)
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            print("[CacheUtils] Failed to load or decode \(fileName) from main bundle: \(error)")
        }
    }

    print("[CacheUtils] Cache file \(fileName) not found in Documents directory or main bundle")
    return nil
}

public func saveCache<T: Encodable>(_ value: T, to fileName: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let fileManager = FileManager.default

    do {
        let data = try encoder.encode(value)
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: [.atomic])
        } else {
            print("[CacheUtils] Failed to locate Documents directory to save \(fileName)")
        }
    } catch {
        print("[CacheUtils] Failed to encode or save \(fileName): \(error)")
    }
}

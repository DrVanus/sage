import Foundation

/// DEPRECATED: Static seed articles are disabled to ensure only live news is shown.
/// Previously used as a fallback when API/RSS failed, but this caused stale placeholder
/// content to appear indefinitely. Now returns empty array so proper error states are shown.
enum StaticNewsSeed {
    static func sampleArticles() -> [CryptoNewsArticle] {
        // Return empty - do not use static placeholder articles
        // This forces the app to show proper error states when feeds fail
        return []
    }
}

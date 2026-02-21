//
//  CryptoNewsArticle.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//

//
// CryptoNewsArticle.swift
// CryptoSage
//

import Foundation

/// Represents a single news article in the CryptoSage app.
struct CryptoNewsArticle: Codable, Identifiable, Equatable {
    
    /// Headline of the article
    let title: String
    
    /// Optional subtitle or summary
    let description: String?
    
    /// Link to the full article
    let url: URL
    
    /// Optional URL to an image
    let urlToImage: URL?

    /// Name of the news source
    let sourceName: String
    
    /// Publication date
    let publishedAt: Date

    /// Use the article’s URL as a unique identifier
    var id: String { url.absoluteString }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case url
        case urlToImage
        case publishedAt
        case sourceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.url = try container.decode(URL.self, forKey: .url)
        self.urlToImage = try container.decodeIfPresent(URL.self, forKey: .urlToImage)
        self.sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "Unknown Source"

        var parsed: Date? = nil

        // 1) String-based timestamps (ISO8601 or RFC822/RFC1123 or numeric strings)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
            // ISO8601 with fractional seconds
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds, .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
            parsed = isoFrac.date(from: dateString)
            if parsed == nil {
                // ISO8601 common internet format
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
                parsed = iso.date(from: dateString)
            }
            if parsed == nil {
                // RFC822 / RFC1123 patterns frequently used by RSS
                let rfc = DateFormatter()
                rfc.locale = Locale(identifier: "en_US_POSIX")
                rfc.timeZone = TimeZone(secondsFromGMT: 0)
                let patterns = [
                    "EEE, dd MMM yyyy HH:mm:ss zzz", // RFC1123
                    "EEE, dd MMM yyyy HH:mm zzz",    // RFC1123 (no seconds)
                    "dd MMM yyyy HH:mm:ss zzz",      // RFC822 variant
                    "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                    "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
                    "yyyy-MM-dd'T'HH:mm:ssZ"
                ]
                for p in patterns {
                    rfc.dateFormat = p
                    if let d = rfc.date(from: dateString) { parsed = d; break }
                }
            }
            if parsed == nil {
                // Numeric string (seconds or milliseconds)
                if let rawNum = Double(dateString) {
                    if rawNum > 10_000_000_000 { // milliseconds
                        parsed = Date(timeIntervalSince1970: rawNum / 1000.0)
                    } else {
                        parsed = Date(timeIntervalSince1970: rawNum)
                    }
                }
            }
        }

        // 2) Numeric timestamps (seconds or milliseconds)
        if parsed == nil, let tsDouble = try container.decodeIfPresent(Double.self, forKey: .publishedAt) {
            parsed = tsDouble > 10_000_000_000 ? Date(timeIntervalSince1970: tsDouble / 1000.0) : Date(timeIntervalSince1970: tsDouble)
        }
        if parsed == nil, let tsInt = try container.decodeIfPresent(Int.self, forKey: .publishedAt) {
            let v = Double(tsInt)
            parsed = v > 10_000_000_000 ? Date(timeIntervalSince1970: v / 1000.0) : Date(timeIntervalSince1970: v)
        }

        // 3) Fallback
        self.publishedAt = NewsDate.clampIfUnrealistic(parsed ?? Date())
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(urlToImage, forKey: .urlToImage)
        try container.encode(sourceName, forKey: .sourceName)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [
            .withFullDate,
            .withFullTime,
            .withColonSeparatorInTime,
            .withColonSeparatorInTimeZone,
            .withFractionalSeconds
        ]
        let dateString = iso.string(from: publishedAt)
        try container.encode(dateString, forKey: .publishedAt)
    }
    
    /// Provides a default UUID when decoding or initializing
    init(
        title: String,
        description: String? = nil,
        url: URL,
        urlToImage: URL? = nil,
        sourceName: String = "Unknown Source",
        publishedAt: Date
    ) {
        self.title = title
        self.description = description
        self.url = url
        self.urlToImage = urlToImage
        self.sourceName = sourceName
        self.publishedAt = publishedAt
    }

    /// Human-friendly “time ago” formatting (e.g. "5h ago", "30m ago", "Yesterday")
    var relativeTime: String {
        NewsDate.relative(for: publishedAt)
    }
}


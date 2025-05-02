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
        let dateString = try container.decode(String.self, forKey: .publishedAt)
        // Debug: log the raw timestamp string
        print("PublishedAt raw string: \(dateString)")
        
        var parsedDate: Date?
        
        // 1) Try ISO8601 with fractional seconds, full date/time, and colon separators
        let isoFormatter1 = ISO8601DateFormatter()
        isoFormatter1.formatOptions = [
            .withFullDate,
            .withFullTime,
            .withFractionalSeconds,
            .withColonSeparatorInTime,
            .withColonSeparatorInTimeZone
        ]
        parsedDate = isoFormatter1.date(from: dateString)
        
        // 2) If still nil, try ISO8601 without fractional seconds
        if parsedDate == nil {
            let isoFormatter2 = ISO8601DateFormatter()
            isoFormatter2.formatOptions = [
                .withInternetDateTime,
                .withColonSeparatorInTimeZone
            ]
            parsedDate = isoFormatter2.date(from: dateString)
        }
        
        // 3) If still nil, try multiple fallback formats
        if parsedDate == nil {
            let fallbackPatterns = [
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
                "yyyy-MM-dd'T'HH:mm:ssZ"
            ]
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            for pattern in fallbackPatterns {
                df.dateFormat = pattern
                if let d = df.date(from: dateString) {
                    parsedDate = d
                    break
                }
            }
        }
        
        // 4) Assign final parsed date or default to now
        if let date = parsedDate {
            self.publishedAt = date
        } else {
            self.publishedAt = Date()
            print("Warning: Failed to parse publishedAt ('\(dateString)'), defaulting to now.")
        }
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
        let interval = Date().timeIntervalSince(publishedAt)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if Calendar.current.isDateInYesterday(publishedAt) {
            return "Yesterday"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

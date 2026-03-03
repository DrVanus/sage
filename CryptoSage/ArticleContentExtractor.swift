//
//  ArticleContentExtractor.swift
//  CryptoSage
//
//  Extracts readable text content from news article URLs for AI analysis.
//

import Foundation
import os.log

private let extractorLog = OSLog(subsystem: "com.cryptosage.news", category: "extractor")

/// Result of article content extraction
struct ArticleContent {
    let title: String
    let source: String
    let content: String
    let url: URL
    
    /// Whether we got actual content or just metadata
    var hasFullContent: Bool {
        content.count > 100
    }
    
    /// Build a prompt string for AI analysis
    func buildPrompt() -> String {
        var prompt = "Summarize this article and explain its impact on the crypto market. Focus on actionable insights.\n\n"
        prompt += "Title: \(title)\n"
        prompt += "Source: \(source)\n"
        prompt += "URL: \(url.absoluteString)\n\n"
        
        if hasFullContent {
            prompt += "Article Content:\n\(content)"
        } else if !content.isEmpty {
            prompt += "Summary: \(content)"
        }
        
        return prompt
    }
}

/// Service to extract readable content from news article URLs
final class ArticleContentExtractor {
    static let shared = ArticleContentExtractor()
    
    /// Maximum characters to extract (to manage token costs)
    private let maxContentLength = 4000
    
    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 10
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Extract content from an article URL
    /// - Parameters:
    ///   - url: The article URL
    ///   - article: Optional article metadata to use as fallback
    /// - Returns: ArticleContent with extracted text or fallback metadata
    func extract(from url: URL, article: CryptoNewsArticle? = nil) async -> ArticleContent {
        let cleanURL = sanitizeURL(url)
        
        // Try to fetch and parse HTML content
        if let htmlContent = await fetchHTML(from: cleanURL) {
            let extractedText = parseContent(from: htmlContent)
            
            if !extractedText.isEmpty {
                os_log("Extracted %d chars from %{public}@", log: extractorLog, type: .debug, extractedText.count, cleanURL.host ?? "unknown")
                
                return ArticleContent(
                    title: article?.title ?? parseTitle(from: htmlContent) ?? "News Article",
                    source: article?.sourceName ?? cleanURL.host ?? "Unknown Source",
                    content: extractedText,
                    url: cleanURL
                )
            }
        }
        
        // Fallback to article metadata if extraction failed
        os_log("Extraction failed, using metadata for %{public}@", log: extractorLog, type: .info, cleanURL.host ?? "unknown")
        
        return ArticleContent(
            title: article?.title ?? "News Article",
            source: article?.sourceName ?? cleanURL.host ?? "Unknown Source",
            content: article?.description ?? "",
            url: cleanURL
        )
    }
    
    // MARK: - Private Methods
    
    /// Fetch HTML content from URL
    private func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            // Try UTF-8 first, then other common encodings
            if let html = String(data: data, encoding: .utf8) {
                return html
            }
            if let html = String(data: data, encoding: .isoLatin1) {
                return html
            }
            if let html = String(data: data, encoding: .windowsCP1252) {
                return html
            }
            
            return nil
        } catch {
            os_log("Failed to fetch HTML: %{private}@", log: extractorLog, type: .error, error.localizedDescription)
            return nil
        }
    }
    
    /// Parse readable content from HTML
    private func parseContent(from html: String) -> String {
        var content = ""
        
        // Try to find main article content first
        if let articleContent = extractSection(from: html, startTag: "<article", endTag: "</article>") {
            content = extractText(from: articleContent)
        }
        
        // If article tag didn't yield much, try common content containers
        if content.count < 200 {
            // Try main tag
            if let mainContent = extractSection(from: html, startTag: "<main", endTag: "</main>") {
                let mainText = extractText(from: mainContent)
                if mainText.count > content.count {
                    content = mainText
                }
            }
        }
        
        // Try content div patterns
        if content.count < 200 {
            let contentPatterns = [
                "class=\"article-content\"",
                "class=\"post-content\"",
                "class=\"entry-content\"",
                "class=\"content\"",
                "id=\"article-body\"",
                "class=\"article-body\""
            ]
            
            for pattern in contentPatterns {
                if let divContent = extractDivWithClass(from: html, pattern: pattern) {
                    let divText = extractText(from: divContent)
                    if divText.count > content.count {
                        content = divText
                    }
                }
            }
        }
        
        // Final fallback: extract all paragraphs
        if content.count < 200 {
            content = extractAllParagraphs(from: html)
        }
        
        // Clean up and limit length
        content = cleanText(content)
        
        if content.count > maxContentLength {
            // Truncate at a sentence boundary if possible
            let truncated = String(content.prefix(maxContentLength))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                content = String(truncated[...lastPeriod])
            } else {
                content = truncated + "..."
            }
        }
        
        return content
    }
    
    /// Extract a section between start and end tags
    private func extractSection(from html: String, startTag: String, endTag: String) -> String? {
        guard let startRange = html.range(of: startTag, options: .caseInsensitive) else {
            return nil
        }
        
        let afterStart = html[startRange.lowerBound...]
        guard let endRange = afterStart.range(of: endTag, options: .caseInsensitive) else {
            return nil
        }
        
        return String(afterStart[..<endRange.upperBound])
    }
    
    /// Extract a div with a specific class pattern
    private func extractDivWithClass(from html: String, pattern: String) -> String? {
        guard let patternRange = html.range(of: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        // Find the opening div tag
        let beforePattern = html[..<patternRange.lowerBound]
        guard let divStart = beforePattern.range(of: "<div", options: [.backwards, .caseInsensitive]) else {
            return nil
        }
        
        // Find matching closing div (simplified - finds next </div>)
        let afterPattern = html[patternRange.upperBound...]
        
        // Count nested divs to find the right closing tag
        var depth = 1
        var searchStart = afterPattern.startIndex
        
        while depth > 0 && searchStart < afterPattern.endIndex {
            let remaining = afterPattern[searchStart...]
            
            let nextOpen = remaining.range(of: "<div", options: .caseInsensitive)
            let nextClose = remaining.range(of: "</div>", options: .caseInsensitive)
            
            if let closeRange = nextClose {
                if let openRange = nextOpen, openRange.lowerBound < closeRange.lowerBound {
                    depth += 1
                    searchStart = openRange.upperBound
                } else {
                    depth -= 1
                    if depth == 0 {
                        // SAFETY: Use half-open range to prevent String index out of bounds crash
                        return String(html[divStart.lowerBound..<closeRange.upperBound])
                    }
                    searchStart = closeRange.upperBound
                }
            } else {
                break
            }
        }
        
        return nil
    }
    
    /// Extract text from HTML, removing tags
    private func extractText(from html: String) -> String {
        var text = html
        
        // Remove script and style tags with content
        text = removeTagWithContent(from: text, tag: "script")
        text = removeTagWithContent(from: text, tag: "style")
        text = removeTagWithContent(from: text, tag: "nav")
        text = removeTagWithContent(from: text, tag: "header")
        text = removeTagWithContent(from: text, tag: "footer")
        text = removeTagWithContent(from: text, tag: "aside")
        text = removeTagWithContent(from: text, tag: "noscript")
        
        // Convert line breaks and paragraphs to newlines
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h1>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h2>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h3>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        
        // Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode HTML entities
        text = decodeHTMLEntities(text)
        
        return text
    }
    
    /// Remove a tag and its content from HTML
    private func removeTagWithContent(from html: String, tag: String) -> String {
        var result = html
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        return result
    }
    
    /// Extract all paragraph content from HTML
    private func extractAllParagraphs(from html: String) -> String {
        var paragraphs: [String] = []
        var searchStart = html.startIndex
        
        while searchStart < html.endIndex {
            let remaining = html[searchStart...]
            
            guard let pStart = remaining.range(of: "<p", options: .caseInsensitive),
                  let tagEnd = remaining[pStart.upperBound...].range(of: ">") else {
                break
            }
            
            let contentStart = tagEnd.upperBound
            guard let pEnd = remaining[contentStart...].range(of: "</p>", options: .caseInsensitive) else {
                break
            }
            
            let content = String(remaining[contentStart..<pEnd.lowerBound])
            let cleanContent = extractText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Only include paragraphs with substantial content
            if cleanContent.count > 30 {
                paragraphs.append(cleanContent)
            }
            
            searchStart = pEnd.upperBound
        }
        
        return paragraphs.joined(separator: "\n\n")
    }
    
    /// Parse title from HTML
    private func parseTitle(from html: String) -> String? {
        // Try og:title first
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return ogTitle
        }
        
        // Try title tag
        if let titleStart = html.range(of: "<title", options: .caseInsensitive),
           let tagEnd = html[titleStart.upperBound...].range(of: ">"),
           let titleEnd = html[tagEnd.upperBound...].range(of: "</title>", options: .caseInsensitive) {
            let title = String(html[tagEnd.upperBound..<titleEnd.lowerBound])
            return decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Extract meta content by property
    private func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "property=\"\(property)\"[^>]*content=\"([^\"]*)\"",
            "content=\"([^\"]*)\"[^>]*property=\"\(property)\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let contentRange = Range(match.range(at: 1), in: html) {
                return decodeHTMLEntities(String(html[contentRange]))
            }
        }
        
        return nil
    }
    
    /// Clean extracted text
    private func cleanText(_ text: String) -> String {
        var cleaned = text
        
        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n ", with: "\n", options: .literal)
        cleaned = cleaned.replacingOccurrences(of: " \n", with: "\n", options: .literal)
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Remove common noise phrases
        let noisePatterns = [
            "cookie", "subscribe", "newsletter", "sign up", "log in",
            "advertisement", "sponsored", "read more", "share this",
            "follow us", "related articles", "comments"
        ]
        
        // Split into lines and filter out noisy ones
        var lines = cleaned.components(separatedBy: "\n")
        lines = lines.filter { line in
            let lower = line.lowercased()
            // Keep lines that don't start with noise and have reasonable length
            return line.count > 20 && !noisePatterns.contains { lower.hasPrefix($0) }
        }
        
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Decode common HTML entities
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "..."),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&bull;", "•"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™")
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        
        // Handle numeric entities
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let numRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }
        
        return result
    }
    
    /// Sanitize URL (upgrade to HTTPS, remove tracking params)
    private func sanitizeURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        // Upgrade to HTTPS
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
        }
        
        // Remove tracking parameters
        let trackingParams = Set(["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
                                   "fbclid", "gclid", "ref", "ref_src", "si", "s"])
        if let items = components?.queryItems {
            components?.queryItems = items.filter { !trackingParams.contains($0.name.lowercased()) }
            if components?.queryItems?.isEmpty == true {
                components?.queryItems = nil
            }
        }
        
        return components?.url ?? url
    }
}

// MARK: - UIShims.swift
// Lightweight shims to satisfy missing symbols referenced across the app.
// These are intentionally minimal and can be replaced with real implementations later.

import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Fallback async image with simple caching disabled (placeholder only)
public struct CachingAsyncImage: View {
    public let url: URL?
    public var referer: URL? = nil
    public var maxPixel: Int? = nil

    @StateObject private var loader = ImageLoader()

    public init(url: URL?, referer: URL? = nil, maxPixel: Int? = nil) {
        self.url = CachingAsyncImage.upgradeToHTTPS(url)
        self.referer = referer
        self.maxPixel = maxPixel
    }

    public var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                ZStack { Color.white.opacity(0.06); ProgressView().tint(.yellow) }
            case .failed:
                ZStack { Color.white.opacity(0.06); Image(systemName: "photo").foregroundStyle(.secondary) }
            case .loaded(let image):
                image.resizable().scaledToFill()
            }
        }
        .onAppear { loader.load(from: url, referer: referer, maxPixel: maxPixel) }
        .onChange(of: url) { _ in loader.load(from: url, referer: referer, maxPixel: maxPixel) }
        .onDisappear { loader.cancel() }
    }

    private static func upgradeToHTTPS(_ url: URL?) -> URL? {
        guard let url else { return nil }
        if url.scheme == nil, url.absoluteString.hasPrefix("//") { return URL(string: "https:" + url.absoluteString) }
        if url.scheme?.lowercased() == "http" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            return comps?.url ?? url
        }
        return url
    }

    private final class ImageLoader: ObservableObject {
        enum State { case idle, loading, loaded(Image), failed }
        @Published var state: State = .idle
        private var task: Task<Void, Never>? = nil
        #if os(iOS)
        private static let cache = NSCache<NSURL, UIImage>()
        #else
        private static let cache = NSCache<NSURL, NSImage>()
        #endif
        private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        func cancel() { task?.cancel(); task = nil }

        func load(from url: URL?, referer: URL?, maxPixel: Int?) {
            cancel()
            guard let url = url else { state = .failed; return }
            if let cached = Self.cache.object(forKey: url as NSURL) {
                state = .loaded(Image(uiImage: cached))
                return
            }
            state = .loading
            task = Task { [weak self] in
                guard let self = self else { return }
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 6
                    req.cachePolicy = .returnCacheDataElseLoad
                    req.setValue(ua, forHTTPHeaderField: "User-Agent")
                    req.setValue("image/webp,image/*;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
                    if let r = referer { req.setValue(r.absoluteString, forHTTPHeaderField: "Referer") }
                    let (data, response) = try await URLSession.shared.data(for: req)
                    guard !Task.isCancelled else { return }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        await MainActor.run { self.state = .failed }
                        return
                    }
                    #if os(iOS)
                    let img = UIImage(data: data)
                    #else
                    let img = NSImage(data: data)
                    #endif
                    guard let baseImage = img else {
                        await MainActor.run { self.state = .failed }
                        return
                    }
                    #if os(iOS)
                    let finalImage: UIImage
                    if let maxPixel, maxPixel > 0 {
                        let maxSide = CGFloat(maxPixel)
                        let size = baseImage.size
                        let scale = min(1.0, maxSide / max(size.width, size.height))
                        if scale < 0.999 {
                            let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
                            let renderer = UIGraphicsImageRenderer(size: newSize)
                            finalImage = renderer.image { _ in baseImage.draw(in: CGRect(origin: .zero, size: newSize)) }
                        } else {
                            finalImage = baseImage
                        }
                    } else {
                        finalImage = baseImage
                    }
                    Self.cache.setObject(finalImage, forKey: url as NSURL)
                    await MainActor.run { self.state = .loaded(Image(uiImage: finalImage)) }
                    #else
                    // macOS simple wrap
                    Self.cache.setObject(baseImage, forKey: url as NSURL)
                    await MainActor.run { self.state = .loaded(Image(nsImage: baseImage)) }
                    #endif
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.state = .failed }
                }
            }
        }
    }
}

// Simple relative time text (e.g., "5m ago")
public struct RelativeTimeText: View {
    public let date: Date
    public init(date: Date) { self.date = date }
    public var body: some View {
        Text(Self.format(date))
    }
    private static func format(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

// Basic error view placeholder for news-related errors
public struct CryptoNewsErrorView: View {
    public let message: String
    public var onRetry: (() -> Void)?

    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

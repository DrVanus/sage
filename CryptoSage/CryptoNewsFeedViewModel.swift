import SwiftUI
import Foundation

/// News categories for filtering the feed
enum NewsCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    // Add more categories as needed

    var id: String { rawValue }

    /// Query parameter to use when fetching from the News API
    var query: String {
        switch self {
        case .all: return "crypto"
        case .bitcoin: return "bitcoin"
        case .ethereum: return "ethereum"
        }
    }
}

@MainActor
final class CryptoNewsFeedViewModel: ObservableObject {
    @Published var articles: [CryptoNewsArticle] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingPage: Bool = false
    private var currentPage: Int = 1
    @Published var errorMessage: String?

    /// Indicates if the last error was retryable
    @Published var isRetryableError: Bool = false

    /// Track in-flight tasks so we can cancel when needed
    private var loadAllTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    /// Currently selected news category; will reload feed when changed
    @Published var selectedCategory: NewsCategory = .all {
        didSet {
            loadAllNews()
        }
    }

    private let newsService = CryptoNewsService()

    init() {
        loadAllNews()
        // Load any saved bookmarks from UserDefaults
        loadBookmarks()
    }

    func loadAllNews() {
        // Cancel any in-flight all-news load
        loadAllTask?.cancel()

        loadAllTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.errorMessage = nil
            self.isRetryableError = false
            self.isLoading = true
            defer { self.isLoading = false }

            do {
                let fetched = try await self.newsService.fetchNews(query: self.selectedCategory.query, page: 1)
                self.articles = fetched
                self.currentPage = 1
                self.isRetryableError = false
                if fetched.isEmpty {
                    self.errorMessage = "No news available"
                }
            } catch is CancellationError {
                return
            } catch let error as CryptoNewsError {
                // Retryable classification
                switch error {
                case .timeout, .networkError:
                    self.isRetryableError = true
                default:
                    self.isRetryableError = false
                }
                self.articles = []
                self.errorMessage = error.localizedDescription
            } catch {
                self.isRetryableError = false
                self.articles = []
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreNews() {
        // Avoid double-fetch
        guard !isLoadingPage else { return }
        // Cancel any in-flight paging load
        loadMoreTask?.cancel()

        loadMoreTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.errorMessage = nil
            self.isRetryableError = false
            self.isLoadingPage = true
            defer { self.isLoadingPage = false }

            self.currentPage += 1
            do {
                let fetched = try await self.newsService.fetchNews(query: self.selectedCategory.query, page: self.currentPage)
                self.articles.append(contentsOf: fetched)
                self.isRetryableError = false
            } catch is CancellationError {
                return
            } catch let error as CryptoNewsError {
                switch error {
                case .timeout, .networkError:
                    self.isRetryableError = true
                default:
                    self.isRetryableError = false
                }
                self.errorMessage = error.localizedDescription
            } catch {
                self.isRetryableError = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func loadLatestNews() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await newsService.fetchNews(query: selectedCategory.query, page: 1)
            articles = Array(fetched.prefix(5))
            if fetched.isEmpty {
                errorMessage = "No news available"
            }
        }
        catch is CancellationError {
            return
        }
        catch let urlError as URLError where urlError.code == .cancelled {
            return
        }
        catch {
            articles = []
            errorMessage = error.localizedDescription
        }
    }

    // Track read/bookmarked articles
    @Published private var readArticleIDs: Set<String> = []
    @Published private var bookmarkedArticleIDs: Set<String> = []

    /// Persistence key for saved bookmarks
    private let bookmarksKey = "bookmarkedArticleIDs"

    // MARK: - Read / Bookmark Actions

    func toggleRead(_ article: CryptoNewsArticle) {
        if isRead(article) {
            readArticleIDs.remove(article.id)
        } else {
            readArticleIDs.insert(article.id)
        }
    }

    func isRead(_ article: CryptoNewsArticle) -> Bool {
        readArticleIDs.contains(article.id)
    }

    func toggleBookmark(_ article: CryptoNewsArticle) {
        if isBookmarked(article) {
            bookmarkedArticleIDs.remove(article.id)
        } else {
            bookmarkedArticleIDs.insert(article.id)
        }
        // Persist the change
        saveBookmarks()
    }

    func isBookmarked(_ article: CryptoNewsArticle) -> Bool {
        bookmarkedArticleIDs.contains(article.id)
    }

    /// Load bookmarked IDs from UserDefaults
    private func loadBookmarks() {
        if let saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [String] {
            bookmarkedArticleIDs = Set(saved)
        }
    }

    /// Save current bookmarked IDs to UserDefaults
    private func saveBookmarks() {
        let ids = Array(bookmarkedArticleIDs)
        UserDefaults.standard.set(ids, forKey: bookmarksKey)
    }
}

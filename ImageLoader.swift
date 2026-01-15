import SwiftUI
import Combine

final class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    private static var inFlightRequests = [NSURL: [((UIImage?) -> Void)]]()

    private var cancellable: AnyCancellable?

    func load(url: URL) {
        let httpsURL = Self.enforceHTTPS(url: url)
        let nsURL = httpsURL as NSURL

        if let cachedImage = Self.cache.object(forKey: nsURL) {
            self.image = cachedImage
            return
        }

        if Self.inFlightRequests[nsURL] != nil {
            // Append completion to existing request
            Self.inFlightRequests[nsURL]?.append { [weak self] image in
                DispatchQueue.main.async {
                    self?.image = image
                }
            }
            return
        } else {
            // Start new request
            Self.inFlightRequests[nsURL] = [ { [weak self] image in
                DispatchQueue.main.async {
                    self?.image = image
                }
            } ]
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Use default config to respect URLCache

        let session = URLSession(configuration: config)

        cancellable = session.dataTaskPublisher(for: httpsURL)
            .map { UIImage(data: $0.data) }
            .handleEvents(receiveOutput: { image in
                if let image = image {
                    Self.cache.setObject(image, forKey: nsURL)
                }
            })
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in
                Self.inFlightRequests[nsURL]?.forEach { $0(nil) }
                Self.inFlightRequests[nsURL] = nil
            }, receiveValue: { image in
                Self.inFlightRequests[nsURL]?.forEach { $0(image) }
                Self.inFlightRequests[nsURL] = nil
            })
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }

    private static func enforceHTTPS(url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
            if let httpsURL = components?.url {
                return httpsURL
            }
        }
        return url
    }
}

public struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    @StateObject private var loader = ImageLoader()
    private let url: URL?
    private let placeholder: Placeholder
    private let failure: Failure
    private let imageTransform: (Image) -> Image

    public init(
        url: URL?,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder failure: () -> Failure,
        imageTransform: @escaping (Image) -> Image = { $0 }
    ) {
        self.url = url
        self.placeholder = placeholder()
        self.failure = failure()
        self.imageTransform = imageTransform
    }

    public var body: some View {
        content
            .onAppear {
                guard let url = url else { return }
                loader.load(url: url)
            }
            .onChange(of: url) { newURL in
                guard let newURL = newURL else { return }
                loader.load(url: newURL)
            }
            .onDisappear {
                loader.cancel()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let uiImage = loader.image {
            imageTransform(Image(uiImage: uiImage).resizable())
                .transition(.opacity)
        } else {
            placeholder
        }
    }
}

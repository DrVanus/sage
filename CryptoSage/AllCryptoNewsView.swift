import SwiftUI


struct AllCryptoNewsView: View {
    @EnvironmentObject var vm: CryptoNewsFeedViewModel

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.articles.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage {
            VStack(spacing: 16) {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    vm.loadAllNews()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(vm.articles) { article in
                NavigationLink(destination: NewsWebView(url: article.url)) {
                    HStack(alignment: .center, spacing: 12) {
                        PlaceholderImage {
                            AsyncImage(url: article.urlToImage) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.gray)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(article.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text(article.sourceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(article.relativeTime)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .id(article.id)
                }
                .buttonStyle(PlainButtonStyle())
                .onAppear {
                    if article.id == vm.articles.last?.id {
                        vm.loadMoreNews()
                    }
                }
                // bottom loading indicator for pagination
                if article.id == vm.articles.last?.id && vm.isLoadingPage {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .refreshable {
                vm.loadAllNews()
            }
            .listStyle(PlainListStyle())
            .task {
                if vm.articles.isEmpty {
                    vm.loadAllNews()
                }
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Crypto News")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: BookmarksView()
                        .environmentObject(vm)) {
                        Image(systemName: "bookmark")
                            .foregroundColor(.yellow)
                    }
                }
            }
            // Removed always-onAppear: now handled in List's onAppear
            .accentColor(.white)
    }
}

struct AllCryptoNewsView_Previews: PreviewProvider {
    static var previews: some View {
        AllCryptoNewsView()
            .environmentObject(CryptoNewsFeedViewModel())
    }
}

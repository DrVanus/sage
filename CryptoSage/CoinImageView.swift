import SwiftUI

struct CoinImageView: View {
    let symbol: String
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Circle()
                    .fill(Color.gray.opacity(0.3))
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(symbol.lowercased())
                    .resizable()
                    .scaledToFit()
            @unknown default:
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct CoinImageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CoinImageView(symbol: "BTC", url: URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png"), size: 32)
            CoinImageView(symbol: "ETH", url: URL(string: "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png"), size: 32)
            CoinImageView(symbol: "XRP", url: nil, size: 32)
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}

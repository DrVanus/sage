import SwiftUI

struct ContentView: View {
    @StateObject var wsManager = WebSocketManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Portfolio Dashboard")
                    .font(.title)
                
                // Display real-time updates from the WebSocket
                Text("Real-time Update: \(wsManager.lastMessage)")
                    .padding()
                    .multilineTextAlignment(.center)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
                // Control buttons for testing the WebSocket connection
                HStack(spacing: 40) {
                    Button(action: {
                        wsManager.connect()
                    }) {
                        Text("Connect")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        wsManager.disconnect()
                    }) {
                        Text("Disconnect")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Portfolio Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

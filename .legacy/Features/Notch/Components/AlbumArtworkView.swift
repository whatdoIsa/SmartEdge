import SwiftUI
import AppKit

struct AlbumArtworkView: View {
    let artwork: NSImage?
    
    @State private var isLoaded = false
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.2)) {
                            isLoaded = true
                        }
                    }
                    .opacity(isLoaded ? 1.0 : 0.0)
                    .scaleEffect(isLoaded ? 1.0 : 0.8)
            } else {
                placeholderArtwork
            }
        }
        .onChange(of: artwork) { _, _ in
            isLoaded = false
            withAnimation(.easeIn(duration: 0.2)) {
                isLoaded = true
            }
        }
    }
    
    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}

#Preview {
    HStack(spacing: 16) {
        AlbumArtworkView(artwork: nil)
            .frame(width: 24, height: 24)
        
        AlbumArtworkView(artwork: nil)
            .frame(width: 40, height: 40)
    }
    .padding()
    .background(Color.black)
}
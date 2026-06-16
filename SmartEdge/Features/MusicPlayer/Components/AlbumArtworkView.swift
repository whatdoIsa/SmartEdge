import SwiftUI

@MainActor
struct AlbumArtworkView: View {
    let artwork: NSImage?
    let size: CGFloat
    
    @State private var imageScale: CGFloat = 1.0
    @State private var shadowRadius: CGFloat = 4.0
    @State private var isLoaded = false
    
    init(artwork: NSImage?, size: CGFloat = 60) {
        self.artwork = artwork
        self.size = size
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                    }
            } else {
                placeholderArtwork
            }
        }
        .scaleEffect(imageScale)
        .shadow(
            color: .black.opacity(0.3),
            radius: shadowRadius,
            x: 0,
            y: 2
        )
        .opacity(isLoaded ? 1.0 : 0.0)
        .onAppear {
            animateAppearance()
        }
        .onChange(of: artwork) { newArtwork in
            animateArtworkChange(hasNewArtwork: newArtwork != nil)
        }
    }
    
    // MARK: - Private Views
    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        .gray.opacity(0.3),
                        .gray.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.1), lineWidth: 0.5)
            }
    }
    
    // MARK: - Private Methods
    private func animateAppearance() {
        withAnimation(.easeOut(duration: 0.3)) {
            isLoaded = true
            imageScale = 1.0
        }
    }
    
    private func animateArtworkChange(hasNewArtwork: Bool) {
        if hasNewArtwork {
            // Scale down slightly then back up for subtle change indication
            withAnimation(.easeInOut(duration: 0.2)) {
                imageScale = 0.95
                shadowRadius = 6.0
            }
            
            // Return to normal after brief moment
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        imageScale = 1.0
                        shadowRadius = 4.0
                    }
                }
            }
        } else {
            // Fade out effect for no artwork
            withAnimation(.easeOut(duration: 0.3)) {
                imageScale = 0.98
                shadowRadius = 2.0
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        AlbumArtworkView(artwork: nil, size: 60)
        
        AlbumArtworkView(artwork: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), size: 80)
        
        HStack(spacing: 12) {
            AlbumArtworkView(artwork: nil, size: 40)
            AlbumArtworkView(artwork: nil, size: 50)
            AlbumArtworkView(artwork: nil, size: 60)
        }
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(16)
}
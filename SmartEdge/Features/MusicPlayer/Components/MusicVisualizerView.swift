import SwiftUI

@MainActor
struct MusicVisualizerView: View {
    let isPlaying: Bool
    let isVisible: Bool
    
    @State private var barHeights: [CGFloat] = Array(repeating: 0.2, count: 12)
    @State private var animationTimer: Timer?
    
    private let barCount = 12
    private let maxHeight: CGFloat = 24
    private let minHeight: CGFloat = 2
    private let animationInterval: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                visualizerBar(at: index)
            }
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: isPlaying) { newValue in
            updateAnimation(isPlaying: newValue)
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    // MARK: - Private Views
    private func visualizerBar(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(
                LinearGradient(
                    colors: [
                        .blue.opacity(0.8),
                        .cyan.opacity(0.6),
                        .blue.opacity(0.4)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: barHeights[safe: index] ?? 0.2)
            .animation(
                .easeInOut(duration: 0.1 + Double(index) * 0.02),
                value: barHeights[safe: index] ?? 0.2
            )
    }
    
    // MARK: - Private Methods
    private func updateAnimation(isPlaying: Bool) {
        if isPlaying {
            startAnimation()
        } else {
            stopAnimation()
            resetBarsToMinimum()
        }
    }
    
    private func startAnimation() {
        stopAnimation() // Stop any existing timer
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: animationInterval, repeats: true) { _ in
            Task { @MainActor in
                updateBarHeights()
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func updateBarHeights() {
        for i in 0..<barCount {
            // Create different frequency bands with more realistic behavior
            let baseFrequency = Double(i + 1) * 0.5
            let randomVariation = Double.random(in: 0.3...1.0)
            let timeOffset = Date().timeIntervalSince1970 * baseFrequency
            
            // Use sine wave with random variations for more natural movement
            let sineValue = sin(timeOffset) * randomVariation
            let normalizedValue = (sineValue + 1.0) / 2.0 // Convert to 0-1 range
            
            // Apply frequency-based scaling (higher frequencies typically have less energy)
            let frequencyScaling = 1.0 - (Double(i) * 0.05)
            let finalValue = normalizedValue * frequencyScaling
            
            let newHeight = minHeight + (maxHeight - minHeight) * finalValue
            barHeights[safe: i] = newHeight
        }
    }
    
    private func resetBarsToMinimum() {
        withAnimation(.easeOut(duration: 0.5)) {
            for i in 0..<barCount {
                barHeights[safe: i] = minHeight
            }
        }
    }
}

// MARK: - Array Safety Extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        get {
            return indices.contains(index) ? self[index] : nil
        }
        set {
            if let newValue = newValue, indices.contains(index) {
                self[index] = newValue
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        MusicVisualizerView(isPlaying: true, isVisible: true)
        MusicVisualizerView(isPlaying: false, isVisible: true)
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(12)
    .frame(width: 200, height: 100)
}
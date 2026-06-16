import SwiftUI

struct MusicVisualizerView: View {
    let isPlaying: Bool
    let amplitudes: [Double]
    
    @State private var animationTimer: Timer?
    @State private var animatedAmplitudes: [Double] = Array(repeating: 0.1, count: 5)
    
    private let barCount = 5
    private let maxBarHeight: CGFloat = 16
    private let minBarHeight: CGFloat = 2
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    
    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(barColor(for: index))
                    .frame(
                        width: barWidth,
                        height: barHeight(for: index)
                    )
                    .animation(
                        .easeInOut(duration: 0.3)
                        .delay(Double(index) * 0.05),
                        value: animatedAmplitudes[index]
                    )
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onChange(of: amplitudes) { _, newAmplitudes in
            updateAmplitudes(newAmplitudes)
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        guard index < animatedAmplitudes.count else { return minBarHeight }
        
        let amplitude = animatedAmplitudes[index]
        let normalizedAmplitude = max(0.1, min(1.0, amplitude))
        
        return minBarHeight + (maxBarHeight - minBarHeight) * normalizedAmplitude
    }
    
    private func barColor(for index: Int) -> Color {
        if !isPlaying {
            return .white.opacity(0.3)
        }
        
        let amplitude = index < animatedAmplitudes.count ? animatedAmplitudes[index] : 0.1
        let opacity = 0.5 + (amplitude * 0.5)
        
        switch index {
        case 0, 4:
            return Color.blue.opacity(opacity)
        case 1, 3:
            return Color.white.opacity(opacity)
        case 2:
            return Color.blue.opacity(opacity + 0.2)
        default:
            return Color.white.opacity(opacity)
        }
    }
    
    private func startAnimation() {
        guard isPlaying else { return }
        
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                for i in 0..<barCount {
                    if amplitudes.indices.contains(i) && !amplitudes[i].isNaN {
                        animatedAmplitudes[i] = amplitudes[i]
                    } else {
                        animatedAmplitudes[i] = Double.random(in: 0.2...0.8)
                    }
                }
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        withAnimation(.easeOut(duration: 0.5)) {
            for i in 0..<barCount {
                animatedAmplitudes[i] = 0.1
            }
        }
    }
    
    private func updateAmplitudes(_ newAmplitudes: [Double]) {
        guard isPlaying else { return }
        
        for i in 0..<min(barCount, newAmplitudes.count) {
            if !newAmplitudes[i].isNaN {
                animatedAmplitudes[i] = newAmplitudes[i]
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MusicVisualizerView(
            isPlaying: true,
            amplitudes: [0.3, 0.7, 0.5, 0.9, 0.4]
        )
        .frame(width: 60, height: 20)
        
        MusicVisualizerView(
            isPlaying: false,
            amplitudes: [0.0, 0.0, 0.0, 0.0, 0.0]
        )
        .frame(width: 60, height: 20)
    }
    .padding()
    .background(Color.black)
}
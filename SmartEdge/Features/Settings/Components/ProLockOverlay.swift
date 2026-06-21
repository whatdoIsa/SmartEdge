import SwiftUI

/// Wraps a Pro-gated settings panel: when the user doesn't own Pro, the
/// real panel is shown dimmed/non-interactive behind a centered unlock
/// card that routes to the Pro panel. Once purchased, the wrapper is a
/// transparent pass-through.
struct ProLockGate<Content: View>: View {
    let featureName: String
    let onUnlock: () -> Void
    @ViewBuilder let content: () -> Content

    @ObservedObject private var store = ServiceContainer.shared.storeService

    var body: some View {
        if store.isPro {
            content()
        } else {
            ZStack {
                content()
                    .disabled(true)
                    .blur(radius: 3)
                    .opacity(0.4)
                    .accessibilityHidden(true)

                unlockCard
            }
        }
    }

    private var unlockCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)

            Text("\(featureName)은(는) Pro 기능입니다")
                .font(.headline)

            Text("SmartEdge Pro로 선반·캘린더·뽀모도로를\n한 번의 구매로 잠금 해제하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onUnlock()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Pro 보기")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }
}

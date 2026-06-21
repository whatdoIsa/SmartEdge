import SwiftUI

/// "SmartEdge Pro" settings panel — the in-app purchase surface.
///
/// Freemium model: free tier = music + clock + basic notch; Pro unlocks
/// Shelf, Calendar, Pomodoro. One-time non-consumable purchase via
/// StoreKit 2 (`StoreService`).
struct ProSettingsPanel: View {
    @ObservedObject private var store = ServiceContainer.shared.storeService

    private let proFeatures: [(icon: String, title: String, detail: String)] = [
        ("tray.full", "선반 (Shelf)", "파일을 노치에 임시 보관하고 AirDrop·공유"),
        ("calendar", "캘린더", "다가오는 일정을 노치에서 미리 알림"),
        ("timer", "뽀모도로", "집중 타이머와 세션 통계")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                featureCard

                purchaseSection

                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                footnote
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(NotchTheme.brandCoral)
                    .frame(width: 30, height: 30)
                    .background(NotchTheme.brandCoral.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text("SmartEdge Pro")
                    .font(.system(size: 24, weight: .bold))

                if store.isPro {
                    Text("활성화됨")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Text(store.isPro
                 ? "모든 Pro 기능이 잠금 해제되었습니다. 감사합니다."
                 : "한 번 구매로 모든 Pro 기능을 영구적으로 사용하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var featureCard: some View {
        SettingsCard("Pro 기능") {
            ForEach(Array(proFeatures.enumerated()), id: \.element.title) { index, feature in
                if index > 0 { SettingsRowDivider() }
                SettingRow(title: feature.title, description: feature.detail) {
                    if store.isPro {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: feature.icon)
                            .font(.system(size: 15))
                            .foregroundColor(NotchTheme.brandCoral)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if store.isPro {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        Task { await store.purchasePro() }
                    } label: {
                        HStack(spacing: 6) {
                            if store.purchaseInFlight {
                                ProgressView().controlSize(.small)
                            }
                            Text(store.purchaseInFlight
                                 ? "처리 중…"
                                 : "Pro 구매 — \(store.proPriceText)")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.purchaseInFlight || store.proProduct == nil)

                    Button("구매 복원") {
                        Task { await store.restore() }
                    }
                    .controlSize(.large)
                    .disabled(store.purchaseInFlight)
                }
                if store.proProduct == nil {
                    Text("상품 정보를 불러오는 중입니다…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footnote: some View {
        Text("결제는 Apple 계정으로 청구됩니다. 일회성 구매이며 자동 갱신되지 않습니다.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    ProSettingsPanel()
        .frame(width: 600, height: 700)
}

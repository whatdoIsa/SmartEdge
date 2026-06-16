import SwiftUI

/// Notch content shown while a file transfer / AirDrop receive is in progress.
@MainActor
struct ShelfTransferContentView: View {
    let operation: ShelfOperation

    private var iconName: String {
        switch operation.type {
        case .dragHover: return "tray.and.arrow.down.fill"
        case .fileTransfer: return "arrow.down.doc.fill"
        case .airdropReceiving: return "antenna.radiowaves.left.and.right"
        }
    }

    private var titleText: String {
        switch operation.type {
        case .dragHover: return "Drop to Shelf"
        case .fileTransfer: return "Transferring"
        case .airdropReceiving: return "Receiving"
        }
    }

    private var subtitle: String {
        if let fileName = operation.fileName, !fileName.isEmpty {
            return fileName
        }
        return operation.isActive ? "In progress…" : "Done"
    }

    var body: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressBar
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText). \(subtitle)")
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(0.15))
                .frame(width: 36, height: 36)
            iconImage
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconImage: some View {
        let base = Image(systemName: iconName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.tint)
        if #available(macOS 14.0, *) {
            base.symbolEffect(.pulse, options: .repeating, isActive: operation.isActive)
        } else {
            base
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = operation.progress {
            ProgressView(value: max(0, min(1, progress)))
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .frame(height: 4)
                .frame(maxWidth: 220)
        } else if operation.isActive {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .frame(height: 4)
                .frame(maxWidth: 220)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ShelfTransferContentView(operation: ShelfOperation(
            type: .airdropReceiving,
            fileName: "Vacation Photos.zip",
            progress: 0.42,
            isActive: true
        ))
        ShelfTransferContentView(operation: ShelfOperation(
            type: .fileTransfer,
            fileName: nil,
            progress: nil,
            isActive: true
        ))
    }
    .frame(width: 380)
    .background(.ultraThinMaterial)
}

import SwiftUI

struct ShelfView: View {
    @StateObject private var viewModel: ShelfViewModel
    private let onClose: (() -> Void)?

    init(viewModel: ShelfViewModel, onClose: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    init() {
        // Default initializer for preview and testing
        self._viewModel = StateObject(wrappedValue: ShelfViewModel(
            shelfService: PreviewMockShelfService(),
            fileSharingService: PreviewMockFileSharingService()
        ))
        self.onClose = nil
    }

    var body: some View {
        VStack(spacing: 12) {
            shelfHeader
            shelfContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(dropZoneBackground)
    }
    
    // MARK: - Private Views
    private var shelfHeader: some View {
        HStack {
            Image(systemName: "tray.2.fill")
                .font(.title2)
                .foregroundStyle(.primary)
            
            Text("Quick Shelf")
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Spacer()
            
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            Button(action: viewModel.clearAllItems) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.shelfItems.isEmpty)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("선반 닫기")
            }
        }
    }
    
    private var shelfContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                if viewModel.shelfItems.isEmpty {
                    emptyShelfView
                } else {
                    ForEach(viewModel.shelfItems) { item in
                        shelfItemView(item)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 80)
    }
    
    private var emptyShelfView: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Drop files here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 60)
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
    
    private func shelfItemView(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            // File icon
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.systemIcon)
                        .font(.title)
                        .foregroundStyle(item.iconColor)
                }
            }
            .frame(width: 40, height: 40)
            .background(.quaternary)
            .cornerRadius(6)
            
            // File name
            Text(item.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(width: 60)
        }
        .frame(width: 64, height: 70)
        .background(item.isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .overlay {
            if item.isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .onTapGesture {
            viewModel.selectItem(item)
        }
        .onDrag {
            viewModel.createDragItem(for: item)
        }
        .contextMenu {
            contextMenuForItem(item)
        }
        .animation(.easeInOut(duration: 0.2), value: item.isSelected)
        // Accessibility: bundle the thumbnail + name into a single
        // announcement instead of letting VoiceOver read "image" +
        // "filename" separately. Selection state is exposed so a
        // VoiceOver user can audit what's currently selected without
        // having to swipe through each item.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.isSelected ? "Selected" : "")
        .accessibilityHint("Double-tap to select. Drag to move. Use the context menu to share or remove.")
    }
    
    private func contextMenuForItem(_ item: ShelfItem) -> some View {
        Group {
            Button("Open") {
                viewModel.openItem(item)
            }

            Button("Show in Finder") {
                viewModel.showInFinder(item)
            }

            if item.fileType == .document || item.fileType == .image {
                Button("Quick Look") {
                    viewModel.quickLookItem(item)
                }
            }

            Divider()

            // Share submenu — AirDrop is the user's most common path on
            // macOS for "send this file to my phone / a nearby Mac" so it
            // sits at the top. The other entries route through the same
            // FileSharingService façade so adding/removing options here is
            // a one-line change.
            //
            // AirDrop is gated on `enableAirDropIntegration` from settings
            // — read straight from UserDefaults (default true) instead of
            // routing through SettingsViewModel because this menu doesn't
            // otherwise depend on the settings VM and adding it would
            // bloat the EnvironmentObject chain for every shelf view.
            Menu("Share") {
                if UserDefaults.standard.object(forKey: SettingsKeys.enableAirDropIntegration) as? Bool ?? true {
                    Button {
                        viewModel.shareViaAirDrop(item)
                    } label: {
                        Label("AirDrop", systemImage: "airplayaudio")
                    }
                }
                Button {
                    viewModel.shareViaMessages(item)
                } label: {
                    Label("Messages", systemImage: "message")
                }
                Button {
                    viewModel.copyToClipboard(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button("Remove from Shelf") {
                viewModel.removeItem(item)
            }
        }
    }
    
    private var dropZoneBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay {
                if viewModel.isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.blue, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue.opacity(0.1))
                        )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isDropTargeted)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Empty shelf
        ShelfView(viewModel: ShelfViewModel(
            shelfService: PreviewMockShelfService(),
            fileSharingService: PreviewMockFileSharingService()
        ))
        
        // Shelf with items  
        ShelfView(viewModel: ShelfViewModel(
            shelfService: PreviewMockShelfService(),
            fileSharingService: PreviewMockFileSharingService()
        ))
    }
    .frame(width: 500, height: 300)
    .background(.ultraThinMaterial)
    .cornerRadius(16)
}


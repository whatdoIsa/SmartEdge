import SwiftUI

struct ShelfView: View {
    @StateObject private var viewModel: ShelfViewModel
    @State private var hoveredItemID: ShelfItem.ID?
    @State private var isDropTargeted = false

    private let accent = NotchTheme.brandCoral

    init(viewModel: ShelfViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    init() {
        // Default initializer for preview and testing
        self._viewModel = StateObject(wrappedValue: ShelfViewModel(
            shelfService: PreviewMockShelfService(),
            fileSharingService: PreviewMockFileSharingService()
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            shelfHeader
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accent, lineWidth: 2)
                    .padding(2)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    // MARK: - Header

    private var shelfHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)

            Text("Quick Shelf")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            if !viewModel.shelfItems.isEmpty {
                Text("\(viewModel.shelfItems.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)

            if viewModel.isProcessing {
                ProgressView().scaleEffect(0.6)
            }

            Button(action: viewModel.clearAllItems) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.shelfItems.isEmpty)
            .help("Clear all")
            .accessibilityLabel("Clear all")
        }
        .padding(.horizontal, 16)
        // Small top inset so the header sits just below the overlaid
        // traffic-light controls (full-size content view runs under the
        // transparent title bar) without a large gap.
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.shelfItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.shelfItems) { item in
                        shelfTile(item)
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.7))
            Text("Drop files here")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Text("Keep files handy, then drag them out anywhere.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Tile

    private func shelfTile(_ item: ShelfItem) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = item.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: item.systemIcon)
                            .font(.system(size: 26))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 84, height: 64)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(item.isSelected ? accent : Color.clear, lineWidth: 2)
                }

                if hoveredItemID == item.id {
                    Button {
                        viewModel.removeItem(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Remove \(item.name)")
                }
            }

            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
                .frame(width: 84)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
        .onTapGesture(count: 2) { viewModel.openItem(item) }
        .onTapGesture { viewModel.selectItem(item) }
        .onDrag { viewModel.createDragItem(for: item) }
        .contextMenu { contextMenuForItem(item) }
        .animation(.easeInOut(duration: 0.15), value: hoveredItemID)
        .animation(.easeInOut(duration: 0.15), value: item.isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.isSelected ? "Selected" : "")
        .accessibilityHint("Double-tap to open. Drag to move. Use the context menu to share or remove.")
    }

    private func contextMenuForItem(_ item: ShelfItem) -> some View {
        Group {
            Button("Open") { viewModel.openItem(item) }
            Button("Show in Finder") { viewModel.showInFinder(item) }

            if item.fileType == .document || item.fileType == .image {
                Button("Quick Look") { viewModel.quickLookItem(item) }
            }

            Divider()

            // AirDrop is the most common "send to my phone / nearby Mac" path on
            // macOS, so it leads. Gated on the settings toggle (default true),
            // read straight from UserDefaults to avoid pulling SettingsViewModel
            // into every shelf view.
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

            Button("Remove from Shelf", role: .destructive) {
                viewModel.removeItem(item)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ShelfView(viewModel: ShelfViewModel(
        shelfService: PreviewMockShelfService(),
        fileSharingService: PreviewMockFileSharingService()
    ))
    .frame(width: 380, height: 460)
}

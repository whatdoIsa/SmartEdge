import SwiftUI
import AppKit

@MainActor
struct ClipboardContentView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    /// We always cap visible items so a giant clipboard history doesn't blow
    /// up the notch overlay. When searching, the cap relaxes to "all matches"
    /// — but matches are usually few, and the user explicitly asked to find
    /// something.
    private let maxVisibleWhenIdle = 5
    private let maxVisibleWhenSearching = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            searchField
            if displayedItems.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
        .background(keyboardShortcuts)
        .onChange(of: searchText) { _ in
            // Reset selection any time the result set could have shifted.
            // Otherwise the highlight would land on the wrong row after a
            // filter narrows the list.
            selectedIndex = 0
        }
        .onChange(of: viewModel.history) { _ in
            selectedIndex = 0
        }
    }

    /// Hidden buttons that wire up keyboard shortcuts. Stacked so SwiftUI
    /// can route each modifier+key separately without one shortcut
    /// swallowing another's chord.
    ///
    /// - ⌘F: focus the search field
    /// - ↓ / ↑: move highlight through results
    /// - ⏎: copy the highlighted item
    /// - Esc: clear search + drop focus
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Search") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("Next") { moveSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Previous") { moveSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Copy selected") { copySelected() }
                .keyboardShortcut(.return, modifiers: [])
            Button("Clear search") { dismissSearch() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Keyboard actions

    private func moveSelection(by delta: Int) {
        guard !displayedItems.isEmpty else { return }
        // Clamp rather than wrap — wrapping in a 5-12 item list usually
        // feels jumpier than helpful, and there's no off-screen content
        // a wrap would reveal.
        let newIndex = max(0, min(displayedItems.count - 1, selectedIndex + delta))
        selectedIndex = newIndex
    }

    private func copySelected() {
        guard displayedItems.indices.contains(selectedIndex) else { return }
        viewModel.copy(displayedItems[selectedIndex])
    }

    private func dismissSearch() {
        if !searchText.isEmpty {
            searchText = ""
        }
        searchFocused = false
    }

    // MARK: - Filter logic

    /// Items to render after applying the search filter and visible-cap.
    /// Returning a slice rather than a fully materialized array keeps the
    /// per-frame cost minimal for large histories.
    private var displayedItems: [ClipboardItem] {
        let source = viewModel.history
        let filtered: [ClipboardItem]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = source
        } else {
            let query = searchText.lowercased()
            filtered = source.filter { matches($0, query: query) }
        }
        let cap = searchText.isEmpty ? maxVisibleWhenIdle : maxVisibleWhenSearching
        return Array(filtered.prefix(cap))
    }

    /// Case-insensitive substring match against every text-bearing surface
    /// of the clipboard item. URLs match on host + path + last component;
    /// files match on filename + parent directory. Images / unknown never
    /// match — search them by visual scrolling instead.
    private func matches(_ item: ClipboardItem, query: String) -> Bool {
        switch item.content {
        case .text(let text):
            return text.lowercased().contains(query)
        case .url(let url):
            return url.absoluteString.lowercased().contains(query)
        case .file(let url):
            return url.path.lowercased().contains(query)
        case .fileURLs(let urls):
            return urls.contains(where: { $0.path.lowercased().contains(query) })
        case .image, .unknown:
            return false
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(countLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    /// Always-visible search field. Subtle background so it doesn't dominate
    /// the compact notch layout; ⌘F focuses it for keyboard users.
    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            TextField("Search clipboard", text: $searchText)
                .font(.system(size: 10))
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private var countLabel: String {
        if searchText.isEmpty {
            return "\(viewModel.history.count) items"
        }
        let matchCount = displayedItems.count
        return "\(matchCount) of \(viewModel.history.count)"
    }

    private var emptyState: some View {
        // Different wording for "history empty" vs "no search match" — the
        // former is informative, the latter is actionable.
        let message = searchText.isEmpty
            ? "No recent items"
            : "No matches for \"\(searchText)\""
        return Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                row(for: item, displayIndex: index + 1, isSelected: index == selectedIndex)
                    .onTapGesture {
                        // Sync selection to mouse interactions so keyboard
                        // navigation picks up from wherever the user
                        // clicked last.
                        selectedIndex = index
                        viewModel.copy(item)
                    }
            }
        }
    }

    private func row(for item: ClipboardItem, displayIndex: Int, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(displayIndex)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .frame(width: 12, height: 12)
                .background(.quaternary, in: Circle())
                .foregroundStyle(.secondary)
            Image(systemName: iconName(for: item.content))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(previewLabel(for: item))
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        // Accent tint at low alpha for the keyboard-highlighted row. Kept
        // subtle so the colored chip + icons stay legible against it.
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityLabel("\(displayIndex). \(previewLabel(for: item))")
        .accessibilityHint("Click or press Return to re-copy")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconName(for content: ClipboardItem.ClipboardContent) -> String {
        switch content {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .file, .fileURLs: return "doc"
        case .image: return "photo"
        case .unknown: return "questionmark.circle"
        }
    }

    private func previewLabel(for item: ClipboardItem) -> String {
        switch item.content {
        case .text(let text):
            let trimmed = text.replacingOccurrences(of: "\n", with: " ")
            return trimmed.count > 50 ? String(trimmed.prefix(47)) + "…" : trimmed
        case .url(let url):
            return url.host ?? url.absoluteString
        case .file(let url):
            return url.lastPathComponent
        case .fileURLs(let urls):
            return "\(urls.count) files"
        case .image:
            return "Image"
        case .unknown:
            return "Unknown"
        }
    }
}

#Preview {
    ClipboardContentView(viewModel: ClipboardViewModel(service: ClipboardMonitorService()))
        .frame(width: 380, height: 200)
        .background(.ultraThinMaterial)
}

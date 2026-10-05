import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    var onPaste: (ClipItem) -> Void
    var onCopy: (ClipItem) -> Void
    var onClose: () -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", text = "Text", images = "Images", files = "Files"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let list = store.items.filter { item in
            switch filter {
            case .all: return true
            case .text: return item.kind == .text
            case .images: return item.kind == .image
            case .files: return item.kind == .files
            }
        }.filter { q.isEmpty || $0.searchText.contains(q) }
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    var body: some View {
        let items = filtered
        let selected = items.first { $0.id == selectedID } ?? items.first

        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    list(items, selected: selected)
                        .frame(width: 360)
                    Divider()
                    PreviewPane(item: selected, store: store,
                                onPaste: onPaste, onCopy: onCopy,
                                onPin: { store.togglePin($0) },
                                onDelete: { store.delete($0) })
                }
                Divider()
                footer
            }
            .onKeyPress(.downArrow) { move(1, in: items, proxy: proxy); return .handled }
            .onKeyPress(.upArrow) { move(-1, in: items, proxy: proxy); return .handled }
            .onKeyPress(keys: [.delete], phases: .down) { press in
                guard press.modifiers.contains(.command), let s = selected else { return .ignored }
                store.delete(s)
                return .handled
            }
        }
        .frame(width: 860, height: 540)
        .background(.regularMaterial)
        .onAppear {
            selectedID = items.first?.id
            searchFocused = true
        }
        .onChange(of: query) { selectedID = filtered.first?.id }
        .onChange(of: filter) { selectedID = filtered.first?.id }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search everything you've copied", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit {
                        if let s = filtered.first(where: { $0.id == selectedID }) ?? filtered.first { onPaste(s) }
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            Picker("Type", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(12)
    }

    @ViewBuilder
    private func list(_ items: [ClipItem], selected: ClipItem?) -> some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text(store.items.isEmpty ? "Copy something and it will show up here." : "Nothing matches your search.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        ClipRow(item: item, store: store, isSelected: item.id == selected?.id)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onPaste(item) }
                            .onTapGesture { selectedID = item.id }
                            .contextMenu {
                                Button("Paste") { onPaste(item) }
                                Button("Copy") { onCopy(item) }
                                Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(item) }
                            }
                    }
                }
                .padding(8)
            }
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "laptopcomputer")
            Text("Saved on this Mac · \(store.items.count) items · \(ByteCountFormatter.string(fromByteCount: store.diskUsage(), countStyle: .file))")
            Spacer()
            Text("↑↓ move   ↩ paste   double-click paste   ⌘⌫ delete   esc close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func move(_ delta: Int, in items: [ClipItem], proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
        proxy.scrollTo(items[next].id)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let store: HistoryStore
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Thumb(item: item, store: store, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10))
            }
        }
        .padding(8)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor : .clear))
    }
}

struct Thumb: View {
    let item: ClipItem
    let store: HistoryStore
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor))
            switch item.kind {
            case .image:
                if let img = store.thumbnail(for: item) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            case .text:
                Text("Aa").font(.system(size: 14, weight: .semibold, design: .serif)).foregroundStyle(.secondary)
            case .files:
                if let first = item.filePaths?.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable().scaledToFit().padding(4)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct PreviewPane: View {
    let item: ClipItem?
    let store: HistoryStore
    var onPaste: (ClipItem) -> Void
    var onCopy: (ClipItem) -> Void
    var onPin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.kindLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(details(item), id: \.0) { row in
                        GridRow {
                            Text(row.0).foregroundStyle(.secondary)
                            Text(row.1).textSelection(.enabled).lineLimit(2)
                        }
                    }
                }
                .font(.system(size: 12))

                HStack {
                    Button("Paste") { onPaste(item) }
                        .buttonStyle(.borderedProminent)
                    Button("Copy") { onCopy(item) }
                    Spacer()
                    Button(item.pinned ? "Unpin" : "Pin") { onPin(item) }
                    Button("Delete", role: .destructive) { onDelete(item) }
                }
                .controlSize(.large)
            }
            .padding(16)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let img = store.fullImage(for: item) {
                Image(nsImage: img).resizable().scaledToFit().padding(8)
            } else {
                Text("Image file is missing.").foregroundStyle(.secondary)
            }
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
                            Text(path).font(.system(size: 12)).lineLimit(2).truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private func details(_ item: ClipItem) -> [(String, String)] {
        var rows: [(String, String)] = []
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { rows.append(("Dimensions", "\(w) × \(h)")) }
            if let url = store.imageURL(for: item),
               let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 {
                rows.append(("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
            }
        case .text:
            rows.append(("Length", "\((item.text ?? "").count) characters"))
        case .files:
            rows.append(("Items", "\(item.filePaths?.count ?? 0)"))
        }
        rows.append(("Copied", "\(ClipItem.absolute.string(from: item.date)) · \(item.ago)"))
        if let app = item.sourceApp { rows.append(("From", app)) }
        return rows
    }
}

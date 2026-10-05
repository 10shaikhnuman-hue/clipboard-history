import AppKit
import CryptoKit
import ImageIO

enum ClipKind: String, Codable {
    case text, image, files
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: ClipKind
    var text: String?
    var imageFile: String?      // file name inside images/
    var imageWidth: Int?
    var imageHeight: Int?
    var filePaths: [String]?
    var hash: String
    var date: Date
    var sourceApp: String?
    var pinned: Bool = false
}

extension ClipItem {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var title: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let first = t.components(separatedBy: .newlines).first ?? t
            return first.isEmpty ? "(blank text)" : String(first.prefix(200))
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image \(w) × \(h)" }
            return "Image"
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count <= 1 { return names.first ?? "File" }
            return "\(names[0]) + \(names.count - 1) more"
        }
    }

    var kindLabel: String {
        switch kind {
        case .text: return "Text"
        case .image: return "Image"
        case .files: return (filePaths?.count ?? 0) > 1 ? "Files" : "File"
        }
    }

    var ago: String { Self.relative.localizedString(for: date, relativeTo: Date()) }

    var subtitle: String {
        [kindLabel, sourceApp, ago].compactMap { $0 }.joined(separator: " · ")
    }

    var searchText: String {
        [text, filePaths?.joined(separator: " "), sourceApp, kindLabel]
            .compactMap { $0 }.joined(separator: " ").lowercased()
    }
}

/// Keeps the history on disk in ~/Library/Application Support/ClipHistory.
/// Nothing expires: items stay until you delete them.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let baseURL: URL
    let imagesURL: URL
    let thumbsURL: URL
    private let indexURL: URL
    private let imageCache = NSCache<NSString, NSImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = support.appendingPathComponent("ClipHistory", isDirectory: true)
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        thumbsURL = baseURL.appendingPathComponent("thumbs", isDirectory: true)
        indexURL = baseURL.appendingPathComponent("history.json")
        for dir in [baseURL, imagesURL, thumbsURL] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipItem].self, from: data) {
            items = decoded
        } else {
            // Keep a copy of an unreadable file instead of overwriting it.
            let backup = baseURL.appendingPathComponent("history-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Adding

    func addText(_ s: String, source: String?) {
        let h = Self.hash(Data(s.utf8), prefix: "t")
        if bumpExisting(hash: h) { return }
        insert(ClipItem(id: UUID(), kind: .text, text: s, hash: h, date: Date(), sourceApp: source))
    }

    func addFiles(_ urls: [URL], source: String?) {
        let paths = urls.map(\.path)
        let h = Self.hash(Data(paths.joined(separator: "\n").utf8), prefix: "f")
        if bumpExisting(hash: h) { return }
        insert(ClipItem(id: UUID(), kind: .files, filePaths: paths, hash: h, date: Date(), sourceApp: source))
    }

    func addImage(png: Data, width: Int, height: Int, source: String?) {
        let h = Self.hash(png, prefix: "i")
        if bumpExisting(hash: h) { return }
        let id = UUID()
        let name = id.uuidString + ".png"
        do {
            try png.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("ClipHistory: could not save image: \(error)")
            return
        }
        if let thumb = Self.makeThumbnail(png) {
            try? thumb.write(to: thumbsURL.appendingPathComponent(name), options: .atomic)
        }
        insert(ClipItem(id: id, kind: .image, imageFile: name, imageWidth: width, imageHeight: height,
                        hash: h, date: Date(), sourceApp: source))
    }

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        save()
    }

    /// Copying something already in history moves it back to the top instead of duplicating it.
    private func bumpExisting(hash: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.hash == hash }) else { return false }
        var item = items.remove(at: i)
        item.date = Date()
        items.insert(item, at: 0)
        save()
        return true
    }

    // MARK: Editing

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        removeFiles(of: item)
        save()
    }

    func clearUnpinned() {
        for item in items where !item.pinned { removeFiles(of: item) }
        items.removeAll { !$0.pinned }
        save()
    }

    private func removeFiles(of item: ClipItem) {
        guard let name = item.imageFile else { return }
        try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        try? FileManager.default.removeItem(at: thumbsURL.appendingPathComponent(name))
        imageCache.removeObject(forKey: ("full-" + name) as NSString)
        imageCache.removeObject(forKey: ("thumb-" + name) as NSString)
    }

    // MARK: Images

    func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesURL.appendingPathComponent($0) }
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let name = item.imageFile else { return nil }
        let key = ("thumb-" + name) as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let url = thumbsURL.appendingPathComponent(name)
        let img = NSImage(contentsOf: url) ?? NSImage(contentsOf: imagesURL.appendingPathComponent(name))
        if let img { imageCache.setObject(img, forKey: key) }
        return img
    }

    func fullImage(for item: ClipItem) -> NSImage? {
        guard let name = item.imageFile else { return nil }
        let key = ("full-" + name) as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let img = NSImage(contentsOf: imagesURL.appendingPathComponent(name))
        if let img { imageCache.setObject(img, forKey: key) }
        return img
    }

    func diskUsage() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for dir in [imagesURL, thumbsURL] {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
                total += (attrs?[.size] as? Int64) ?? 0
            }
        }
        let indexSize = (try? fm.attributesOfItem(atPath: indexURL.path))?[.size] as? Int64
        return total + (indexSize ?? 0)
    }

    // MARK: Helpers

    static func hash(_ data: Data, prefix: String) -> String {
        prefix + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func makeThumbnail(_ data: Data, maxSide: Int = 240) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

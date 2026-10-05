import AppKit
import ApplicationServices

@MainActor
enum Paster {
    /// Puts a history item back on the clipboard, ready for ⌘V.
    static func copy(_ item: ClipItem, store: HistoryStore) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            pb.clearContents()
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            guard let url = store.imageURL(for: item), let png = try? Data(contentsOf: url) else { return }
            pb.clearContents()
            pb.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pb.setData(tiff, forType: .tiff) // some apps only accept TIFF
            }
        case .files:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.clearContents()
            pb.writeObjects(urls)
        }
    }

    static var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// Opens the Accessibility prompt so the app may press ⌘V for you.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Presses ⌘V in whatever app is in front.
    static func pressCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

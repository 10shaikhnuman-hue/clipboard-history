// Writes the app icon at every size macOS needs into an .iconset folder.
// Built together with Sources/ClipHistory/IconRenderer.swift (see build.sh).
// Usage: make_icon <output.iconset> [preview-frames-folder]
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! png(IconRenderer.image(size: base)).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(IconRenderer.image(size: base * 2)).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

// Optional: a few animation frames, for previewing the Dock animations.
if CommandLine.arguments.count > 2 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[2])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let frames: [(String, IconRenderer.State)] = [
        ("copy-1", .init(drop: 0.25, check: 0, glow: 0, fan: 0)),
        ("copy-2", .init(drop: 0.7, check: 0, glow: 0, fan: 0)),
        ("copy-3", .init(drop: 1, check: 0.5, glow: 0.4, fan: 0)),
        ("copy-4", .init(drop: 1, check: 1, glow: 1, fan: 0)),
        ("fanned", .init(drop: 1, check: 1, glow: 0, fan: 1)),
    ]
    for (name, state) in frames {
        try! png(IconRenderer.image(size: 512, state: state)).write(to: dir.appendingPathComponent("\(name).png"))
    }
}

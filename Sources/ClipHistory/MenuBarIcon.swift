import AppKit

/// The menu bar version of the app icon: the same three stacked cards and checkmark,
/// drawn in one color (a "template" image) so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    private static let size: CGFloat = 18
    /// Maps the cards area of the 1024 icon (x 238…786, y 222…770) onto 2…16 pt.
    private static let k: CGFloat = 14 / 548
    private static let toMenuBar = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: 2 - 238 * k, ty: 2 - 222 * k)

    static func image(_ state: IconRenderer.State = .resting) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipboard History"
        return image
    }

    private static func draw(_ ctx: CGContext, _ state: IconRenderer.State) {
        let shapes = IconRenderer.cards(for: state)
        var t = toMenuBar
        guard let cream = shapes.cream.copy(using: &t),
              let lavender = shapes.lavender.copy(using: &t),
              let navy = shapes.navy.copy(using: &t) else { return }

        ctx.addRect(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.clip()

        // Back to front, each card a bit more solid, with a thin gap cut around it.
        layer(ctx, cream, alpha: 0.38, gap: false)
        layer(ctx, lavender, alpha: 0.66, gap: true)
        layer(ctx, navy, alpha: 1, gap: true)

        // Checkmark cut out of the front card
        guard state.check > 0.02,
              let check = IconRenderer.checkPath(offsetY: shapes.dropOffset).copy(using: &t) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(check)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [IconRenderer.checkLength * k * min(state.check, 1), 100])
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func layer(_ ctx: CGContext, _ path: CGPath, alpha: CGFloat, gap: Bool) {
        ctx.saveGState()
        if gap {
            ctx.setBlendMode(.clear)
            ctx.addPath(path)
            ctx.setLineWidth(1.8)
            ctx.strokePath()
        }
        ctx.setBlendMode(.copy)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
        ctx.fillPath()
        ctx.restoreGState()
    }
}

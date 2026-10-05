import AppKit
import CoreImage

/// Draws the app icon: a glossy blue tile with three frosted-glass cards and a checkmark.
/// Used both to build the .icns file and to animate the Dock icon while the app runs.
enum IconRenderer {
    struct State {
        /// 0 = front card below the tile, 1 = in place
        var drop: CGFloat = 1
        /// How much of the checkmark is drawn, 0…1
        var check: CGFloat = 1
        /// Extra glow on the checkmark, 0…1
        var glow: CGFloat = 0
        /// 0 = stacked, 1 = fanned out (history window open)
        var fan: CGFloat = 0

        static let resting = State()
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let space = CGColorSpaceCreateDeviceRGB()

    // Layout in a 1024 × 1024 space, y pointing down (Apple's icon grid: tile inset 100).
    private static let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let left: CGFloat = 238, right: CGFloat = 786, bottom: CGFloat = 770

    static func image(size px: Int, state: State = .resting) -> CGImage {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let s = CGFloat(px) / 1024
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: s, y: -s)
        ctx.interpolationQuality = .high

        let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
        drawTile(ctx, tile, scale: s)

        // Cards stay inside the tile, so the front card can slide in from the bottom edge.
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()

        let (cream, lavender, navy, dropOffset) = cards(for: state)

        glassCard(ctx, cream, scale: s, px: px, tintTop: rgb(0xFFE9A6, 0.86), tintBottom: rgb(0xFFD674, 0.82), shadow: 0.18)
        glassCard(ctx, lavender, scale: s, px: px, tintTop: rgb(0xC3AEFF, 0.82), tintBottom: rgb(0x8E6CF6, 0.80), shadow: 0.26)
        glassCard(ctx, navy, scale: s, px: px, tintTop: rgb(0x384070, 0.84), tintBottom: rgb(0x0A0D22, 0.93), shadow: 0.40, darkGlass: true)

        drawCheck(ctx, offsetY: dropOffset, progress: state.check, glow: state.glow, scale: s)
        ctx.restoreGState()

        drawTileGloss(ctx, tile, scale: s)
        return ctx.makeImage()!
    }

    // MARK: Tile

    private static func drawTile(_ ctx: CGContext, _ tile: CGPath, scale s: CGFloat) {
        // Drop shadow under the tile
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: rgb(0x0A1A55, 0.30))
        ctx.addPath(tile)
        ctx.setFillColor(rgb(0x2F63E0))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        linear(ctx, [rgb(0x72A6FF), rgb(0x2F68F0), rgb(0x2148CC)], [0, 0.55, 1], from: CGPoint(x: 300, y: 100), to: CGPoint(x: 700, y: 924))
        // Soft colored light behind the glass, so the frosted cards have something to blur.
        blob(ctx, at: CGPoint(x: 240, y: 240), radius: 340, rgb(0x86E6FF, 0.60))
        blob(ctx, at: CGPoint(x: 850, y: 420), radius: 320, rgb(0xB07CFF, 0.55))
        blob(ctx, at: CGPoint(x: 300, y: 860), radius: 300, rgb(0x5A7DFF, 0.45))
        ctx.restoreGState()
    }

    private static func drawTileGloss(_ ctx: CGContext, _ tile: CGPath, scale s: CGFloat) {
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        // Curved sheen across the top
        let sheen = CGMutablePath()
        sheen.move(to: CGPoint(x: 100, y: 100))
        sheen.addLine(to: CGPoint(x: 924, y: 100))
        sheen.addLine(to: CGPoint(x: 924, y: 300))
        sheen.addQuadCurve(to: CGPoint(x: 100, y: 420), control: CGPoint(x: 520, y: 230))
        sheen.closeSubpath()
        ctx.addPath(sheen)
        ctx.clip()
        linear(ctx, [rgb(0xFFFFFF, 0.20), rgb(0xFFFFFF, 0.0)], [0, 1], from: CGPoint(x: 0, y: 100), to: CGPoint(x: 0, y: 420))
        ctx.restoreGState()

        innerRim(ctx, tile, width: 5, top: rgb(0xFFFFFF, 0.75), bottom: rgb(0xFFFFFF, 0.12), from: 100, to: 924)
    }

    // MARK: Glass cards

    /// The three card shapes for a given animation state (shared with the menu bar icon).
    static func cards(for state: State) -> (cream: CGPath, lavender: CGPath, navy: CGPath, dropOffset: CGFloat) {
        let fan = ease(state.fan)
        let cream = card(topLeft: 222 - 46 * fan, topRight: 222 - 46 * fan, radii: [128, 128, 132, 132])
        let lavender = card(topLeft: 333 - 22 * fan, topRight: 363 - 22 * fan, radii: [96, 108, 132, 132])
        let dropOffset = (1 - easeOutBack(state.drop)) * 340 + 14 * fan
        let navy = card(topLeft: 520, topRight: 492, radii: [100, 104, 132, 132])
            .copy(using: [CGAffineTransform(translationX: 0, y: dropOffset)])!
        return (cream, lavender, navy, dropOffset)
    }

    static func checkPath(offsetY: CGFloat) -> CGPath {
        let check = CGMutablePath()
        check.move(to: CGPoint(x: 323, y: 652 + offsetY))
        check.addLine(to: CGPoint(x: 369, y: 698 + offsetY))
        check.addLine(to: CGPoint(x: 461, y: 602 + offsetY))
        return check
    }

    static let checkLength: CGFloat = 65 + 133

    private static func card(topLeft: CGFloat, topRight: CGFloat, radii: [CGFloat]) -> CGPath {
        roundedShape([CGPoint(x: left, y: topLeft), CGPoint(x: right, y: topRight),
                      CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)], radii)
    }

    /// Frosted glass: blurs whatever is already drawn behind the card, tints it,
    /// then adds a soft shadow, a top sheen and a bright rim.
    private static func glassCard(_ ctx: CGContext, _ path: CGPath, scale s: CGFloat, px: Int,
                                  tintTop: CGColor, tintBottom: CGColor, shadow: CGFloat, darkGlass: Bool = false) {
        let box = path.boundingBoxOfPath
        guard box.minY < 924 else { return } // fully below the tile

        // Shadow only outside the card, so it doesn't show through the glass
        ctx.saveGState()
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -200, y: -200, width: 1424, height: 1424))
        outside.addPath(path)
        ctx.addPath(outside)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: 10 * s), blur: 34 * s, color: rgb(0x120A45, shadow))
        ctx.addPath(path)
        ctx.setFillColor(rgb(0x000000))
        ctx.fillPath()
        ctx.restoreGState()

        // Blurred copy of everything behind the card
        if let behind = ctx.makeImage() {
            let blurred = blur(behind, sigma: 26 * s)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.translateBy(x: 0, y: 1024)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        linear(ctx, [tintTop, tintBottom], [0, 1], from: CGPoint(x: 0, y: box.minY), to: CGPoint(x: 0, y: bottom))
        // Light catching the upper part of the glass
        linear(ctx, [rgb(0xFFFFFF, darkGlass ? 0.20 : 0.42), rgb(0xFFFFFF, 0)], [0, 1],
               from: CGPoint(x: 0, y: box.minY), to: CGPoint(x: 0, y: box.minY + 170))
        // Faint diagonal reflection
        linear(ctx, [rgb(0xFFFFFF, 0), rgb(0xFFFFFF, darkGlass ? 0.05 : 0.10), rgb(0xFFFFFF, 0)], [0, 0.5, 1],
               from: CGPoint(x: left + 60, y: box.minY), to: CGPoint(x: left + 360, y: box.minY + 300))
        ctx.restoreGState()

        innerRim(ctx, path, width: 5,
                 top: rgb(0xFFFFFF, darkGlass ? 0.55 : 0.90), bottom: rgb(0xFFFFFF, darkGlass ? 0.08 : 0.25),
                 from: box.minY, to: bottom)
    }

    // MARK: Checkmark

    private static func drawCheck(_ ctx: CGContext, offsetY: CGFloat, progress: CGFloat, glow: CGFloat, scale s: CGFloat) {
        guard progress > 0.02 else { return }
        let check = checkPath(offsetY: offsetY)
        let length = checkLength

        func stroke(width: CGFloat, color: CGColor) {
            ctx.addPath(check)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(color)
            ctx.setLineDash(phase: 0, lengths: [length * min(progress, 1), 2000])
            ctx.strokePath()
        }

        // Soft glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: (22 + 40 * glow) * s, color: rgb(0x9FC0FF, 0.75 + 0.25 * glow))
        stroke(width: 36, color: rgb(0xF4F3FF))
        ctx.restoreGState()
        // Crisp stroke with a little shine along the top
        ctx.saveGState()
        stroke(width: 36, color: rgb(0xF4F3FF))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -6)
        stroke(width: 12, color: rgb(0xFFFFFF, 0.9))
        ctx.restoreGState()
    }

    // MARK: Helpers

    private static func blur(_ image: CGImage, sigma: CGFloat) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent) ?? image
    }

    private static func innerRim(_ ctx: CGContext, _ path: CGPath, width: CGFloat,
                                 top: CGColor, bottom: CGColor, from y0: CGFloat, to y1: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.addPath(path)
        ctx.setLineWidth(width * 2)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        linear(ctx, [top, bottom], [0, 1], from: CGPoint(x: 0, y: y0), to: CGPoint(x: 0, y: y1))
        ctx.restoreGState()
    }

    private static func blob(_ ctx: CGContext, at c: CGPoint, radius: CGFloat, _ color: CGColor) {
        let clear = color.copy(alpha: 0)!
        let g = CGGradient(colorsSpace: space, colors: [color, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
    }

    private static func linear(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat], from a: CGPoint, to b: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A four-sided shape with its own corner radius at each corner.
    private static func roundedShape(_ pts: [CGPoint], _ radii: [CGFloat]) -> CGPath {
        let p = CGMutablePath()
        let n = pts.count
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for i in 0..<n {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radii[i])
        }
        p.closeSubpath()
        return p
    }

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static func ease(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func easeOutBack(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        let c1: CGFloat = 1.1, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

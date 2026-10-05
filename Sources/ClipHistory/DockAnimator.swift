import AppKit

/// Animates the Dock icon and the menu bar icon together:
/// - when something is copied, a new glass card slides into the stack and the checkmark draws itself;
/// - while the history window is open, the cards fan out.
@MainActor
final class DockAnimator {
    private let imageView = NSImageView()
    /// The menu bar icon, animated along with the Dock icon.
    weak var statusButton: NSStatusBarButton?
    private var timer: Timer?
    private var copyProgress: CGFloat?   // nil when no copy animation is running
    private var fan: CGFloat = 0
    private var fanTarget: CGFloat = 0

    private let fps: Double = 30
    private let copyDuration: Double = 0.9
    private let pixelSize = 256

    init() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
    }

    /// Something new was saved.
    func playCopy() {
        guard !reduceMotion else { return }
        copyProgress = 0
        start()
    }

    /// The history window opened (true) or closed (false).
    func setFanned(_ open: Bool) {
        fanTarget = open ? 1 : 0
        if reduceMotion { fan = fanTarget }
        start()
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func start() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        tick()
    }

    private func tick() {
        let dt = CGFloat(1 / fps)

        if let p = copyProgress {
            let next = p + dt / CGFloat(copyDuration)
            copyProgress = next >= 1 ? nil : next
        }
        let diff = fanTarget - fan
        fan = abs(diff) < 0.01 ? fanTarget : fan + diff * 0.28

        render()

        let idle = copyProgress == nil && fan == fanTarget
        if idle {
            timer?.invalidate()
            timer = nil
            if fan == 0 {
                // Back to the normal icon from the app bundle.
                NSApp.dockTile.contentView = nil
                NSApp.dockTile.display()
            }
        }
    }

    private func render() {
        var state = IconRenderer.State.resting
        state.fan = fan
        if let t = copyProgress {
            // 0–0.55: card slides in · 0.4–0.8: checkmark draws · 0.7–1: glow fades
            state.drop = t / 0.55
            state.check = (t - 0.4) / 0.4
            state.glow = t < 0.7 ? max(0, (t - 0.5) / 0.2) : 1 - (t - 0.7) / 0.3
        }
        statusButton?.image = MenuBarIcon.image(state)

        let cg = IconRenderer.image(size: pixelSize, state: state)
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: 128, height: 128))
        if NSApp.dockTile.contentView !== imageView {
            NSApp.dockTile.contentView = imageView
        }
        NSApp.dockTile.display()
    }
}

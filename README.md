# Clipboard History

A small macOS app that keeps everything you copy (text, images and files) so you can paste it again later, even days afterwards. Everything stays on your Mac. Nothing is sent to the internet.

Needs macOS 14 (Sonoma) or newer. Works on Apple Silicon and Intel Macs.

## Install

**Easiest:** open the Terminal app, paste this line and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/10shaikhnuman-hue/clipboard-history/main/install.sh | bash
```

**Or download it:** get `Clipboard-History.dmg` from the [latest release](https://github.com/10shaikhnuman-hue/clipboard-history/releases/latest), open it and drag **Clipboard History** onto **Applications**.

The app isn't from the App Store, so the first time you open it macOS may say it "can't be opened". To allow it, go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run this in Terminal:

```bash
xattr -cr "/Applications/Clipboard History.app"
```

## Use

- Copy anything as usual (⌘C, screenshots, "Copy Image" in a browser…).
- Press **⌘⇧V** anywhere to open your history.
- Search, filter by Text / Images / Files, and press **Return** (or double-click) to paste.
- **↑↓** move · **⌘⌫** delete · **Esc** close. Pin items you want to keep at the top.
- The menu bar icon has your recent items, **Pause Recording**, **Open at Login** and **Clear History**.

**Paste for you:** the first time you pick an item, macOS asks for Accessibility permission. Allow it and the app pastes for you. Without it, the item is copied and you press ⌘V yourself.

Passwords copied from password managers are skipped. History is saved in `~/Library/Application Support/ClipHistory`.

## Build from source

Needs Xcode or the Xcode Command Line Tools.

```bash
./build.sh            # builds build/Clipboard History.app and .dmg
./build.sh install    # also installs it into /Applications and opens it
```

### Project layout

| File | What it does |
| --- | --- |
| `Sources/ClipHistory/AppDelegate.swift` | History window, ⌘⇧V shortcut, menu bar and Dock menus |
| `Sources/ClipHistory/ClipboardWatcher.swift` | Watches the clipboard for new copies |
| `Sources/ClipHistory/HistoryStore.swift` | Saves the history to disk |
| `Sources/ClipHistory/HistoryView.swift` | The history window (SwiftUI) |
| `Sources/ClipHistory/Paster.swift` | Puts items back on the clipboard and pastes them |
| `Sources/ClipHistory/IconRenderer.swift` | Draws the app icon and its animations |
| `build.sh` | Builds the universal app and the .dmg |
| `install.sh` | One-line installer that downloads the latest release |

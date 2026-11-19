# Relabel

A personal macOS menu bar app that gives screenshots and PDFs descriptive names using Apple's on-device model.
All 100% privately on your Mac: no network calls, no accounts, no analytics, no third-party dependencies.

## Build

Only the Command Line Tools are required.

```bash
./build.sh   # swift build -c release, assemble Relabel.app, ad-hoc codesign, copy to ~/Applications
```

## Layout

- `Sources/RelabelCore` – library (bookmarks, watcher, queue, extraction, naming, history, learning)
- `Sources/RelabelApp` – SwiftUI/AppKit menu bar app
- `Resources/Info.plist`, `Tools/make-icon.swift` – bundle metadata and icon generation

## Roadmap

1. Package, build script, menu bar shell (done)
2. Folder selection and bookmarks
3. Naming spike
4. Watcher, queue, rename, history, pill, undo
5. Recent renames list
6. Tidy Up and drag and drop
7. Settings
8. Learning
9. Polish

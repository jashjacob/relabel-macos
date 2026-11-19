# Relabel: automatic screenshot and PDF renamer for macOS

Relabel is a macOS menu bar app that gives your screenshots and PDFs readable names, like
"Quarterly budget forecast 2027" instead of "Screenshot 2026-11-19 at 2.03.04 PM.png".
It uses Apple's on-device model (Apple Intelligence) together with Vision OCR, so it understands what a file
actually shows.

**All 100% privately on your Mac.** No network calls, no accounts, no analytics, no API keys, no third-party
dependencies. It works with Wi-Fi off.

## Features

- Watches the folders you choose and renames new screenshots and PDFs as they arrive
- Drag files or folders onto it, or tidy up a whole folder in one go (preview before anything changes)
- Every rename can be undone and redone, and only the filename changes, so dates stay the same
- Short, standard or detailed names, optional date and app name, and a custom instruction for PDFs
- Learns from your own corrections
- Built with Swift, SwiftUI, Vision, FoundationModels, PDFKit and NaturalLanguage. Apple silicon, macOS 27

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

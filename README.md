<p align="center">
  <img src="docs/icon-512.png" width="128" alt="Relabel app icon">
</p>

<h1 align="center">Relabel</h1>

<p align="center">
  <b>Your screenshots and PDFs, named after what they show.</b><br>
  A macOS menu bar app that renames files with Apple's on-device model.<br>
  <i>All 100% privately on your Mac.</i>
</p>

<p align="center">
  <a href="https://jashjacob.github.io/relabel-macos/">Website</a> ·
  <a href="https://github.com/jashjacob/relabel-macos/releases/latest">Download</a> ·
  <a href="#install">Install</a> ·
  <a href="#how-it-works">How it works</a>
</p>

<p align="center">
  <img alt="macOS 27" src="https://img.shields.io/badge/macOS-27-black">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-black">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="No network" src="https://img.shields.io/badge/network%20calls-0-brightgreen">
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-0-brightgreen">
</p>

---

## Before and after

| Before | After |
| --- | --- |
| `Screenshot 2026-11-19 at 2.03.04 PM.png` | `IndiGo flights Nashik to Chennai from ₹10,487.png` |
| `Scan_20261014_0031.pdf` | `Northwind Cleaning invoice 4471 for $320.pdf` |
| `Screenshot 2026-11-20 at 9.12.41 AM.png` | `Chat with Priya about Friday dinner.png` |

Examples are illustrations of the idea.

## Install

Paste into Terminal. It downloads Relabel, puts it in `~/Applications` and opens it. Because it comes through
Terminal, macOS does not show an unidentified developer warning. (The app is not notarized yet.)

```bash
curl -L https://github.com/jashjacob/relabel-macos/releases/latest/download/Relabel-arm64.zip -o /tmp/Relabel.zip && \
mkdir -p ~/Applications && ditto -x -k /tmp/Relabel.zip ~/Applications && \
open ~/Applications/Relabel.app
```

Or build it yourself. Only the Command Line Tools are required, not Xcode.

```bash
git clone https://github.com/jashjacob/relabel-macos.git
cd relabel-macos && ./build.sh      # swift build, assemble Relabel.app, ad-hoc codesign, copy to ~/Applications
```

Needs an Apple silicon Mac on macOS 27. With Apple Intelligence on you get the best names. Without it Relabel still
works, using basic naming from the text on the file, and says so.

## How it works

1. **Watch.** You pick the folders. Relabel only touches new files in them.
2. **Read.** Apple's Vision reads the text, and the on-device model also looks at the picture.
3. **Name.** Only the file name changes, so dates stay the same, and every rename can be undone.

## Features

- Renames new screenshots and PDFs as they arrive
- Drop files or folders on the menu bar icon, the panel or the app icon, or tidy up a whole folder with a preview first
- Undo and redo for every rename, and edit a name right in the recent list
- Short, standard or detailed names, optional date and app name, and a custom instruction for PDFs
- Learns from your own corrections, stored only on your Mac (Forget Everything wipes it)
- Pauses in Low Power Mode and when your Mac runs hot
- A `relabel` command line tool that uses the same engine

## Privacy

No network calls, no accounts, no analytics, no API keys, no third-party dependencies, no downloaded models.
Only Apple frameworks are used: SwiftUI, AppKit, Vision, FoundationModels, NaturalLanguage, PDFKit,
UserNotifications and ServiceManagement. It works with Wi-Fi off, which was checked by running the naming pipeline
with all network access denied. You can check the source yourself:

```bash
grep -rE "URLSession|NWConnection|CFNetwork" Sources   # no output
```

## Command line

```bash
swift build -c release
.build/release/relabel spike <file>             # names at all three lengths, with and without the model
.build/release/relabel tidy <folder> --dry-run  # preview a whole folder
.build/release/relabel history                  # recent renames (also: relabel undo)
swift run -c release RelabelChecks              # the test suite (the Command Line Tools have no XCTest)
```

## Project layout

- `Sources/RelabelCore` – library: bookmarks, watcher, queue, extraction, naming, history, learning
- `Sources/RelabelApp` – SwiftUI/AppKit menu bar app
- `Sources/relabel` – command line tool
- `Sources/RelabelChecks` – test runner
- `Resources/Info.plist`, `Tools/make-icon.swift` – bundle metadata and icon generation
- `docs/` – the website (GitHub Pages)

## Remove it

```bash
pkill -x Relabel; rm -rf ~/Applications/Relabel.app ~/Library/Application\ Support/Relabel
```

import AppKit
import RelabelCore

OCRHelper.runIfRequested()   // OCR runs in a short-lived helper copy of this program

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

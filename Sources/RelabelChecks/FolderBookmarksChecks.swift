import Foundation
import RelabelCore

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("relabel-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

enum FolderBookmarksChecks {
    static func screenshotsReplacePDFsAppend() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let fb = FolderBookmarks(storeURL: root.appendingPathComponent("f.json"))
        try fb.add(a, kind: .screenshots); try fb.add(b, kind: .screenshots)
        try fb.add(a, kind: .pdf); try fb.add(b, kind: .pdf); try fb.add(a, kind: .pdf)
        check(fb.entries(of: .screenshots).count == 1)
        check(fb.entries(of: .pdf).count == 2)
    }

    static func persistsAcrossInstances() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("f.json")
        try FolderBookmarks(storeURL: store).add(dir, kind: .screenshots)
        let reloaded = FolderBookmarks(storeURL: store).resolveAll(.screenshots)
        check(reloaded.count == 1 && reloaded[0].isReachable)
    }

    static func deletedFolderIsReportedLost() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fb = FolderBookmarks(storeURL: root.appendingPathComponent("f.json"))
        try fb.add(dir, kind: .screenshots)
        try FileManager.default.removeItem(at: dir)
        let r = fb.resolveAll(.screenshots)[0]
        check(!r.isReachable, "deleted folder should be lost")
    }

    static func movedFolderIsFollowed() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("old"), moved = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fb = FolderBookmarks(storeURL: root.appendingPathComponent("f.json"))
        try fb.add(dir, kind: .pdf)
        try FileManager.default.moveItem(at: dir, to: moved)
        let r = fb.resolveAll(.pdf)[0]
        check(r.isReachable)
        check(r.url?.resolvingSymlinksInPath().lastPathComponent == "new")
    }

    static func rejectsFiles() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("x.txt"); try Data().write(to: file)
        let fb = FolderBookmarks(storeURL: root.appendingPathComponent("f.json"))
        do { _ = try fb.add(file, kind: .pdf); check(false, "should throw") } catch { check((error as? FolderBookmarksError) == FolderBookmarksError.notADirectory, "wrong error") }
    }

    static func suggestedLocationFallsBackToDesktop() {
        let home = URL(fileURLWithPath: "/tmp/nohome")
        let defaults = UserDefaults(suiteName: "relabel.test.\(UUID().uuidString)")!
        check(SuggestedFolders.screenshotLocation(defaults: defaults, home: home).path == "/tmp/nohome/Desktop")
        defaults.set("/nonexistent/place", forKey: "location")
        check(SuggestedFolders.screenshotLocation(defaults: defaults, home: home).path == "/tmp/nohome/Desktop")
        defaults.set(NSTemporaryDirectory(), forKey: "location")
        check(SuggestedFolders.screenshotLocation(defaults: defaults, home: home).path != "/tmp/nohome/Desktop")
    }
}


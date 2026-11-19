import Foundation

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ msg: String = "check failed", line: Int = #line) {
    if !ok { failures += 1; print("  FAIL line \(line): \(msg)") }
}
func run(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch { failures += 1; print("  ERROR \(error)") }
    print(failures == before ? "ok   \(name)" : "FAIL \(name)")
}

run("screenshots replace, PDFs append") { try FolderBookmarksChecks.screenshotsReplacePDFsAppend() }
run("persists across instances") { try FolderBookmarksChecks.persistsAcrossInstances() }
run("deleted folder is lost") { try FolderBookmarksChecks.deletedFolderIsReportedLost() }
run("moved folder is followed") { try FolderBookmarksChecks.movedFolderIsFollowed() }
run("rejects files") { try FolderBookmarksChecks.rejectsFiles() }
run("suggested location fallback") { FolderBookmarksChecks.suggestedLocationFallsBackToDesktop() }
run("sanitizing") { RenameChecks.sanitizing() }
run("collision handling") { RenameChecks.collisions() }
run("date handling") { RenameChecks.dates() }
run("screenshot name matching") { RenameChecks.screenshotNames() }
run("undo / redo / never overwrite") { try RenameChecks.undoRedo() }
run("inline edit (user rename)") { try RenameChecks.userRename() }
run("name quality") { TidyChecks.nameQuality() }
run("date tokens") { TidyChecks.dateTokens() }
run("learning store") { try LearningChecks.store() }
run("learning similarity (embeddings)") { LearningChecks.similarity() }
run("style profile") { LearningChecks.style() }
run("detect renames in Finder") { try LearningChecks.detection() }
run("prompt includes learning") { LearningChecks.promptHelp() }
run("processed markers") { try RenameChecks.markers() }
do { try await RenameChecks.hold(); print(failures == 0 ? "ok   hold / release" : "see failures above") } catch { failures += 1; print("ERROR hold \(error)") }
do { try await RenameChecks.endToEnd(); do { try await TidyChecks.planner(); print(failures == 0 ? "ok   tidy planner" : "see failures above") } catch { failures += 1; print("ERROR tidy \(error)") }
print(failures == 0 ? "ok   watcher + queue + rename end to end" : "see failures above") } catch { failures += 1; print("ERROR e2e \(error)") }
print(failures == 0 ? "All checks passed" : "\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

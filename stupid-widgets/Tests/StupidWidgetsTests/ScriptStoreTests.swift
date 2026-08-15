import Foundation
import XCTest

@testable import StupidWidgetsCore

@MainActor
final class ScriptStoreTests: XCTestCase {
  func testCreateEditReloadAndDelete() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ScriptStore(directory: directory)
    let script = try XCTUnwrap(store.create(name: "Persistent"))
    store.updateSource(id: script.id, source: "console.log('saved')")

    let reloaded = ScriptStore(directory: directory)
    let saved = try XCTUnwrap(reloaded.scripts.first { $0.name == "Persistent" })
    XCTAssertEqual(saved.source, "console.log('saved')")
    reloaded.delete(id: saved.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: saved.fileURL.path))
  }
}

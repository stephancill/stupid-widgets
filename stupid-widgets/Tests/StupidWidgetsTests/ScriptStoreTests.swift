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

  func testWidgetsAreOrderedByMostRecentEdit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ScriptStore(directory: directory)
    let first = try XCTUnwrap(store.create(name: "First"))
    let second = try XCTUnwrap(store.create(name: "Second"))
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: first.fileURL.path)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: second.fileURL.path)

    store.reload()
    XCTAssertEqual(store.scripts.map(\.name), ["Second", "First"])

    let firstID = try XCTUnwrap(store.scripts.first { $0.name == "First" }?.id)
    store.updateSource(id: firstID, source: "console.log('latest')")
    XCTAssertEqual(store.scripts.first?.name, "First")
  }

  func testRenameUpdatesListAndPersists() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ScriptStore(directory: directory)
    let script = try XCTUnwrap(store.create(name: "Original"))
    store.rename(id: script.id, to: "Renamed")

    let renamed = try XCTUnwrap(store.scripts.first)
    XCTAssertEqual(renamed.name, "Renamed")
    XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.fileURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: script.fileURL.path))

    let reloaded = ScriptStore(directory: directory)
    XCTAssertEqual(reloaded.scripts.first?.name, "Renamed")
  }

  func testRenameThenRecreateSameNameDoesNotDuplicateIDs() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ScriptStore(directory: directory)
    let original = try XCTUnwrap(store.create(name: "Untitled"))
    store.rename(id: original.id, to: "Untitled 2")
    let recreated = try XCTUnwrap(store.create(name: "Untitled"))

    XCTAssertNotEqual(original.id, recreated.id)
    XCTAssertEqual(Set(store.scripts.map(\.id)).count, store.scripts.count)

    let reloaded = ScriptStore(directory: directory)
    XCTAssertEqual(Set(reloaded.scripts.map(\.id)).count, reloaded.scripts.count)
  }

  func testReloadDeduplicatesCollidingIDs() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ScriptStore(directory: directory)
    let collidingID = UUID().uuidString
    func writeColliding(_ name: String) throws {
      let value: [String: Any] = [
        "name": name, "id": collidingID,
        "icon": ["color": "deep-blue", "glyph": "doc.text"],
        "script": "// \(name)\n", "always_run_in_app": false, "share_sheet_inputs": [],
      ]
      let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted])
      try data.write(
        to: directory.appendingPathComponent(name).appendingPathExtension("widget"))
    }
    try writeColliding("Widget A")
    try writeColliding("Widget B")

    let reloaded = ScriptStore(directory: directory)
    XCTAssertEqual(reloaded.scripts.count, 2)
    XCTAssertEqual(Set(reloaded.scripts.map(\.id)).count, 2)
  }
}

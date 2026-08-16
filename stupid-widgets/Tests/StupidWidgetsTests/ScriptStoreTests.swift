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
}

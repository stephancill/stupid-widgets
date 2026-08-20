import Foundation
import XCTest

@testable import StupidWidgetsCore

@MainActor
final class ModuleTests: XCTestCase {
  func testModuleExportsRelativeResolutionDependenciesAndCaching() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("nested"),
      withIntermediateDirectories: true
    )
    try
      "globalThis.__valueLoads = (globalThis.__valueLoads || 0) + 1; module.exports = { value: 41, loads: globalThis.__valueLoads };"
      .write(
        to: directory.appendingPathComponent("value.js"), atomically: true, encoding: .utf8)
    try
      "const value = importModule('../value'); module.exports.answer = value.value + 1; module.exports.loads = value.loads; module.exports.dependencies = module.dependencies;"
      .write(
        to: directory.appendingPathComponent("nested/index.js"),
        atomically: true,
        encoding: .utf8
      )

    let runtime = JSRuntime(moduleSearchDirectories: [directory])
    runtime.installScriptableAPI(scriptName: "Test")

    XCTAssertEqual(
      runtime.context.evaluateScript("importModule('nested').answer")?.toInt32(), 42)
    XCTAssertEqual(runtime.context.evaluateScript("importModule('nested').loads")?.toInt32(), 1)
    XCTAssertEqual(runtime.context.evaluateScript("importModule('value').loads")?.toInt32(), 1)
    XCTAssertEqual(runtime.context.evaluateScript("module.dependencies.length")?.toInt32(), 3)
    XCTAssertEqual(
      runtime.context.evaluateScript("importModule('nested').dependencies.length")?.toInt32(),
      1)
  }

  func testCircularModulesReceivePartialCachedExports() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "module.exports.name = 'a'; const b = importModule('b'); module.exports.seen = b.seen;"
      .write(to: directory.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
    try "const a = importModule('a'); module.exports.seen = a.name;"
      .write(to: directory.appendingPathComponent("b.js"), atomically: true, encoding: .utf8)

    let runtime = JSRuntime(moduleSearchDirectories: [directory])
    runtime.installScriptableAPI(scriptName: "Test")

    XCTAssertEqual(runtime.context.evaluateScript("importModule('a').seen")?.toString(), "a")
  }

  func testScriptableModulesAndMissingModuleErrors() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fixture.widget")
    let script = Script(
      id: UUID(),
      name: "fixture",
      iconColor: "blue",
      iconGlyph: "doc.text",
      source: "module.exports = 7;",
      alwaysRunInApp: false,
      previewFamily: "medium",
      shareSheetInputs: [],
      fileURL: url
    )
    try script.encoded().write(to: url)

    let runtime = JSRuntime(moduleSearchDirectories: [directory])
    runtime.installScriptableAPI(scriptName: "Test")

    XCTAssertEqual(runtime.context.evaluateScript("importModule('fixture')")?.toInt32(), 7)
    XCTAssertTrue(
      runtime.context.evaluateScript("importModule('missing')")?.isUndefined == true)
    XCTAssertTrue(runtime.consoleLines.contains { $0.contains("Cannot find module 'missing'") })

    let failingURL = directory.appendingPathComponent("failing.js")
    try "throw new Error('MODULE_BOOM');".write(
      to: failingURL,
      atomically: true,
      encoding: .utf8
    )
    XCTAssertTrue(
      runtime.context.evaluateScript("importModule('failing')")?.isUndefined == true)
    XCTAssertTrue(runtime.consoleLines.contains { $0.contains("MODULE_BOOM") })
    try "module.exports = 9;".write(to: failingURL, atomically: true, encoding: .utf8)
    XCTAssertEqual(runtime.context.evaluateScript("importModule('failing')")?.toInt32(), 9)
  }
}

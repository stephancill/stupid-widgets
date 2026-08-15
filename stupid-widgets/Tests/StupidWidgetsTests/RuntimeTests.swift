import UIKit
import XCTest

@testable import StupidWidgetsCore

@MainActor
final class RuntimeTests: XCTestCase {
  func testRegisteredClassesInstallWithoutExceptions() {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")

    XCTAssertTrue(runtime.consoleLines.isEmpty)
    XCTAssertTrue(runtime.context.evaluateScript("new Color('#ffffff').hex")?.isString == true)
    let keys = runtime.context.evaluateScript("new ListWidget()._scriptable_keys()")?.toString()
    XCTAssertTrue(keys?.contains("addText") == true)
  }

  func testTopLevelAwaitCompletes() async throws {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    runtime.evaluate("await Promise.resolve(); console.log('ASYNC_OK')")

    for _ in 0..<50 where !runtime.completed {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(runtime.completed)
    XCTAssertEqual(runtime.consoleLines, ["ASYNC_OK"])
  }

  func testFreshRuntimesIsolateLexicalDeclarations() {
    let first = JSRuntime()
    first.installScriptableAPI(scriptName: "Test")
    first.evaluate("let value = 1")

    let second = JSRuntime()
    second.installScriptableAPI(scriptName: "Test")
    second.evaluate("let value = 2; console.log(value)")

    XCTAssertFalse(second.consoleLines.contains { $0.contains("already been declared") })
  }

  func testNamedColorAppliesToWidgetText() {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    runtime.evaluate(
      """
      let widget = new ListWidget()
      let text = widget.addText("Blue")
      text.textColor = Color.blue()
      Script.setWidget(widget)
      Script.complete()
      """)

    let text = runtime.scriptWidget?.children.first as? WidgetTextModel
    XCTAssertEqual(text?.textColor?.red, 0)
    XCTAssertEqual(text?.textColor?.green, 0.478)
    XCTAssertEqual(text?.textColor?.blue, 1)
  }

  func testSystemFontMetadataIsPreservedForWidgetExtension() {
    let source = FontModel(
      font: UIFont.boldSystemFont(ofSize: 16), systemWeight: .bold)
    let snapshot = ScriptWidgetFont(
      font: source.font,
      systemWeight: source.systemWeight.map { Double($0.rawValue) },
      isMonospaced: source.isMonospaced,
      isItalic: source.isItalic
    )

    XCTAssertTrue(snapshot.system)
    XCTAssertEqual(snapshot.size, 16)
    XCTAssertEqual(snapshot.weight, Double(UIFont.Weight.bold.rawValue))
  }
}

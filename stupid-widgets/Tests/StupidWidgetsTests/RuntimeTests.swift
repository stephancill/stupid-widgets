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

  func testCompilationCheckSupportsTopLevelAwaitAndReportsSyntaxErrors() {
    let runtime = JSRuntime()

    XCTAssertNil(runtime.compilationError(source: "await Promise.resolve()"))
    XCTAssertNotNil(runtime.compilationError(source: "const value ="))
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

  func testDetailExecutionUsesWidgetContext() {
    let execution = ScriptExecution(scriptName: "Test")
    let runtime = execution.run(
      source: """
        if (config.runsInWidget && !config.runsInApp) {
          let widget = new ListWidget()
          Script.setWidget(widget)
        } else {
          QuickLook.present("App result")
        }
        Script.complete()
        """,
      scriptName: "Test"
    )

    XCTAssertNotNil(runtime.scriptWidget)
    XCTAssertNil(runtime.activeTable)
  }

  func testDetailRerunUsesFreshRuntime() {
    let execution = ScriptExecution(scriptName: "Test")
    let first = execution.run(
      source: "Script.setWidget(new ListWidget()); Script.complete()", scriptName: "Test")
    let second = execution.run(
      source: "Script.setWidget(new ListWidget()); Script.complete()", scriptName: "Test")

    XCTAssertFalse(first === second)
    XCTAssertTrue(execution.runtime === second)
    XCTAssertNotNil(second.scriptWidget)
  }

  func testWidgetFamilyIsAvailableToScriptsAndPreview() {
    let execution = ScriptExecution(scriptName: "Test")
    let runtime = execution.run(
      source: """
        let widget = new ListWidget()
        widget.addText(config.widgetFamily)
        Script.setWidget(widget)
        Script.complete()
        """,
      scriptName: "Test",
      widgetFamily: "small"
    )

    XCTAssertEqual((runtime.scriptWidget?.children.first as? WidgetTextModel)?.text, "small")
    XCTAssertEqual(runtime.activePreview?.family, "small")
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

  func testEightDigitColorAndExplicitAlpha() {
    guard let embeddedAlpha = ColorModel(hexString: "#b00a0fe6"),
      let explicitAlpha = ColorModel(hexString: "#b00a0f", alpha: 0.5)
    else {
      return XCTFail("Expected valid colors")
    }

    XCTAssertEqual(embeddedAlpha.red, 176.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(embeddedAlpha.green, 10.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(embeddedAlpha.blue, 15.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(embeddedAlpha.alpha, 230.0 / 255, accuracy: 0.0001)
    XCTAssertEqual(explicitAlpha.alpha, 0.5)
  }

  func testWidgetExtensionPreservesBackgroundGradient() async {
    let snapshot = await ScriptWidgetRunner.run(
      script: SharedWidgetScript(
        name: "Gradient",
        script: """
          let widget = new ListWidget()
          let gradient = new LinearGradient()
          gradient.colors = [new Color("#112233"), new Color("#445566")]
          gradient.locations = [0.2, 0.8]
          gradient.startPoint = new Point(0, 0)
          gradient.endPoint = new Point(1, 1)
          widget.backgroundGradient = gradient
          Script.setWidget(widget)
          Script.complete()
          """)
    )

    guard case .gradient(let gradient) = snapshot.background else {
      return XCTFail("Expected a gradient background")
    }
    XCTAssertEqual(gradient.colors.count, 2)
    XCTAssertEqual(gradient.locations, [0.2, 0.8])
    XCTAssertEqual(gradient.startX, 0)
    XCTAssertEqual(gradient.endY, 1)
  }

  func testWidgetExtensionPreservesLayoutSizing() async {
    let snapshot = await ScriptWidgetRunner.run(
      script: SharedWidgetScript(
        name: "Layout",
        script: """
          let widget = new ListWidget()
          widget.setPadding(12, 13, 14, 15)
          let row = widget.addStack()
          let amount = row.addText("R 20k")
          amount.minimumScaleFactor = 0.65
          row.addSpacer(6)
          row.addText("down 59%")
          Script.setWidget(widget)
          Script.complete()
          """),
      family: "small"
    )

    XCTAssertEqual(snapshot.padding.top, 12)
    XCTAssertEqual(snapshot.padding.leading, 13)
    XCTAssertEqual(snapshot.padding.bottom, 14)
    XCTAssertEqual(snapshot.padding.trailing, 15)
    guard case .stack(let row) = snapshot.elements.first else {
      return XCTFail("Expected a metric row")
    }
    guard case .text(let amount) = row.elements.first else {
      return XCTFail("Expected an amount")
    }
    XCTAssertEqual(amount.minimumScaleFactor, 0.65)
    guard case .spacer(let spacing) = row.elements[1] else {
      return XCTFail("Expected fixed row spacing")
    }
    XCTAssertEqual(spacing, 6)
  }

  func testRoundedSystemFontAppliesToWidgetText() {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    runtime.evaluate(
      """
      let widget = new ListWidget()
      let text = widget.addText("123k")
      text.font = Font.boldRoundedSystemFont(30)
      Script.setWidget(widget)
      Script.complete()
      """)

    let text = runtime.scriptWidget?.children.first as? WidgetTextModel
    XCTAssertEqual(text?.font?.font.pointSize, 30)
    XCTAssertEqual(text?.font?.systemWeight, .bold)
    XCTAssertTrue(text?.font?.isRounded == true)
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

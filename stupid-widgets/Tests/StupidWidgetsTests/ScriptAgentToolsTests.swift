import XCTest

@testable import StupidWidgetsCore

@MainActor
final class ScriptAgentToolsTests: XCTestCase {
  func testSearchAPIReturnsExactMemberDocumentation() throws {
    let documentation = try apiDocumentation()
    let result = ScriptAgentTools.execute(
      name: "search_api",
      argumentsJSON: #"{"query":"ListWidget.addText"}"#,
      script: "",
      apiDocumentation: documentation
    )

    XCTAssertFalse(result.didUpdateScript)
    XCTAssertTrue(result.text.contains(#""owner":"ListWidget""#))
    XCTAssertTrue(result.text.contains(#""signature":"addText(text: string): WidgetText""#))
    XCTAssertTrue(result.text.contains("Adds text to the widget"))
  }

  func testSearchAPIReturnsTypeOverviewAndFuzzyResults() throws {
    let documentation = try apiDocumentation()
    let typeResult = documentation.lookup(query: "ListWidget")
    let searchResult = documentation.lookup(query: "load json")

    XCTAssertTrue(typeResult.contains(#""runtime_members":["addText"]"#))
    XCTAssertTrue(typeResult.contains(#""name":"addText""#))
    XCTAssertTrue(searchResult.contains("Request.loadJSON"))
  }

  func testReadScriptReturnsBoundedNumberedLines() {
    let result = ScriptAgentTools.execute(
      name: "read_script",
      argumentsJSON: #"{"offset":2,"limit":2}"#,
      script: "one\ntwo\nthree\nfour"
    )

    XCTAssertFalse(result.didUpdateScript)
    XCTAssertTrue(result.text.contains(#"2: two\n3: three"#))
    XCTAssertTrue(result.text.contains(#""next_offset":4"#))
  }

  func testEditScriptMakesOneExactReplacement() {
    let result = ScriptAgentTools.execute(
      name: "edit_script",
      argumentsJSON: #"{"old_text":"Cape Town","new_text":"Cape Town Weather"}"#,
      script: #"const title = "Cape Town""#
    )

    XCTAssertTrue(result.didUpdateScript)
    XCTAssertEqual(result.script, #"const title = "Cape Town Weather""#)
  }

  func testEditScriptRejectsAmbiguousReplacement() {
    let result = ScriptAgentTools.execute(
      name: "edit_script",
      argumentsJSON: #"{"old_text":"Cape Town","new_text":"Cape Town Weather"}"#,
      script: "Cape Town\nCape Town"
    )

    XCTAssertFalse(result.didUpdateScript)
    XCTAssertTrue(result.text.contains("found 2"))
  }

  func testEditScriptReturnsCompilationFailureForAgentRetry() {
    let result = ScriptAgentTools.execute(
      name: "edit_script",
      argumentsJSON: #"{"old_text":"const value = 1","new_text":"const value ="}"#,
      script: "const value = 1",
      compilationError: { _ in "SyntaxError: Unexpected token '}'" }
    )

    XCTAssertTrue(result.didUpdateScript)
    XCTAssertEqual(result.script, "const value =")
    XCTAssertTrue(result.text.contains("compilation_error"))
    XCTAssertTrue(result.text.contains("Continue editing"))
  }

  func testWidgetValidationReportsRuntimeFailure() async throws {
    let error = try await ScriptAgentValidator.widgetError(
      source: "throw new Error('broken widget')",
      scriptName: "Test"
    )

    XCTAssertTrue(
      error?.contains("broken widget") == true,
      "Expected the runtime message, received \(error ?? "nil")"
    )
  }

  func testWidgetValidationRequiresAWidget() async throws {
    let error = try await ScriptAgentValidator.widgetError(
      source: "console.log('done')",
      scriptName: "Test"
    )

    XCTAssertEqual(error, "The script completed without calling Script.setWidget(widget).")
  }

  func testWidgetValidationAcceptsSuccessfulWidget() async throws {
    let error = try await ScriptAgentValidator.widgetError(
      source: """
        const widget = new ListWidget()
        widget.addText("Hello")
        Script.setWidget(widget)
        Script.complete()
        """,
      scriptName: "Test"
    )

    XCTAssertNil(error)
  }

  private func apiDocumentation() throws -> ScriptAPIDocumentation {
    let data = Data(
      #"""
      {
        "source": { "name": "Scriptable", "version": "1.7.19" },
        "types": {
          "ListWidget": {
            "name": "ListWidget",
            "summary": "A widget shown on the Home Screen.",
            "description": "Builds a widget hierarchy.",
            "url": "https://docs.scriptable.app/listwidget",
            "constructors": [],
            "properties": [],
            "methods": [
              {
                "name": "addText",
                "signature": "addText(text: string): WidgetText",
                "summary": "Adds text to the widget.",
                "description": "Creates and appends a text element.",
                "url": "https://docs.scriptable.app/listwidget/#-addtext",
                "parameters": [
                  { "name": "text", "type": "string", "description": "Text to show." }
                ],
                "returns": "The text element."
              }
            ],
            "runtimeMembers": ["addText"]
          },
          "Request": {
            "name": "Request",
            "summary": "Performs HTTP requests.",
            "description": null,
            "url": null,
            "constructors": [],
            "properties": [],
            "methods": [
              {
                "name": "loadJSON",
                "signature": "loadJSON(): Promise<any>",
                "summary": "Loads a response and parses JSON.",
                "description": null,
                "url": null
              }
            ],
            "runtimeMembers": ["loadJSON"]
          }
        },
        "globals": {},
        "functions": {}
      }
      """#.utf8)
    return try ScriptAPIDocumentation(data: data)
  }
}

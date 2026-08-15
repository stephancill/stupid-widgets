import XCTest

@testable import StupidWidgetsCore

final class ScriptAgentToolsTests: XCTestCase {
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
}

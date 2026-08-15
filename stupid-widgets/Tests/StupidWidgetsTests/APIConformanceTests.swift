import XCTest

@testable import StupidWidgetsCore

@MainActor
final class APIConformanceTests: XCTestCase {
  private let completeTypes: Set<String> = [
    "Color", "Data", "DateFormatter", "Image", "Keychain", "LinearGradient", "Path", "Point",
    "QuickLook", "RelativeDateTimeFormatter", "Size", "UITable", "UUID", "WidgetSpacer",
    "WidgetStack", "WidgetText",
  ]

  private let partialTypes: Set<String> = [
    "Alert", "Device", "FileManager", "Font", "ListWidget", "Notification", "Pasteboard",
    "Rect",
    "Request", "Safari", "SFSymbol", "Timer", "UITableCell", "UITableRow", "WidgetDate",
    "WidgetImage",
  ]

  private let absentTypes: Set<String> = [
    "Calendar", "CalendarEvent", "CallbackURL", "Contact", "ContactsContainer", "ContactsGroup",
    "DatePicker", "Dictation", "DocumentPicker", "DrawContext", "Location", "Mail", "Message",
    "Photos",
    "RecurrenceRule", "Reminder", "ShareSheet", "Speech", "TextField", "URLScheme", "WebView",
    "XMLParser",
  ]

  func testCanonicalTypeInventory() {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    let registeredTypes = Set(runtime.registeredClassShapes().keys)
    let helperTypes: Set<String> = ["NotificationAction", "RequestResponse"]

    XCTAssertEqual(
      Set(generatedAPIContract.keys),
      completeTypes.union(partialTypes).union(absentTypes).union(["Script"]))
    XCTAssertEqual(registeredTypes, completeTypes.union(partialTypes).union(helperTypes))
  }

  func testCompleteTypeRegistrationsMatchCanonicalContract() throws {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    let shapes = runtime.registeredClassShapes()

    for name in completeTypes.sorted() {
      let expected = try XCTUnwrap(
        generatedAPIContract[name], "Missing generated contract for \(name)")
      let actual = try XCTUnwrap(shapes[name], "Missing registration for \(name)")
      XCTAssertEqual(
        Set(actual.instanceProps), Set(expected.instanceProperties),
        "\(name) instance properties")
      XCTAssertEqual(
        Set(actual.instanceMethods), Set(expected.instanceMethods),
        "\(name) instance methods")
      XCTAssertEqual(
        Set(actual.asyncInstanceMethods), Set(expected.asyncInstanceMethods),
        "\(name) async instance methods")
      XCTAssertEqual(
        Set(actual.staticMethods), Set(expected.staticMethods), "\(name) static methods")
      XCTAssertEqual(
        Set(actual.asyncStaticMethods), Set(expected.asyncStaticMethods),
        "\(name) async static methods")
      XCTAssertTrue(actual.staticProps.isEmpty, "\(name) has unexpected static properties")
    }
  }

  func testPartialAndAbsentTypeStatusesRemainExplicit() {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    let registeredTypes = Set(runtime.registeredClassShapes().keys)

    XCTAssertTrue(partialTypes.isSubset(of: registeredTypes))
    XCTAssertTrue(absentTypes.isDisjoint(with: registeredTypes))
  }

  func testScriptGlobalMatchesCanonicalMembers() throws {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: "Test")
    let expected = try XCTUnwrap(generatedAPIContract["Script"])

    for member in expected.runtimeMembers {
      let type = runtime.context.evaluateScript("typeof Script['\(member)']")?.toString()
      XCTAssertEqual(type, "function", "Script.\(member)")
    }
  }
}

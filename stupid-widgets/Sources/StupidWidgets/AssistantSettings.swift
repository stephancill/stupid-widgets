import Foundation
import SwiftUI

@MainActor
final class AssistantSettings: ObservableObject {
  static let shared = AssistantSettings()

  static let storageKey = "net.stupidtech.stupidwidgets.assistantInstructions"

  static let defaultValue = """
    Style every widget like the built-in Hello Widget sample unless the user explicitly asks for a different look:
    - Use a dark navy background: widget.backgroundColor = new Color("#1b1b2f").
    - Add depth with a vertical LinearGradient from #16222A at the top to #3A6073 at the bottom, with locations [0, 1]. Assign it to widget.backgroundGradient instead of relying on the flat background.
    - Set the background or gradient directly on the ListWidget, never on a child stack.
    - Use white text (Color.white()) for all primary content on the dark background.
    - Title text: Font.boldSystemFont(16).
    - Secondary/date text: Font.mediumSystemFont(13).
    - Dim secondary text with title.textOpacity = 0.85 rather than gray colors.
    - Show the current date with widget.addDate(new Date()), then call applyTimeStyle() and applyDateStyle() on the date element.
    - Separate the title from the date with widget.addSpacer(8).
    - Keep the default vertical ListWidget layout; use addStack() with stack.layoutHorizontally() only when a horizontal row is genuinely needed.
    - Limit long titles with lineLimit and a minimumScaleFactor below 1 so they shrink instead of clipping.
    Match these exact colors, fonts, opacity values, and layout structure in every generated or edited widget.
    """

  static func current() -> String {
    UserDefaults.standard.string(forKey: storageKey) ?? defaultValue
  }

  @Published var instructions: String {
    didSet {
      UserDefaults.standard.set(instructions, forKey: Self.storageKey)
    }
  }

  private init() {
    instructions =
      UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultValue
  }

  func reset() {
    instructions = Self.defaultValue
  }
}

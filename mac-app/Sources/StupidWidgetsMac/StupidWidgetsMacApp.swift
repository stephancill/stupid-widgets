import SwiftUI
import StupidWidgetsCore

@main
struct StupidWidgetsMacApp: App {
  var body: some Scene {
    WindowGroup {
      StupidWidgetsRootView()
        .frame(minWidth: 560, minHeight: 480)
    }
  }
}
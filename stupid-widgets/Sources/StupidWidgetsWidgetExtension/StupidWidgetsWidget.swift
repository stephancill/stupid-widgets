import AppIntents
import StupidWidgetsCore
import SwiftUI
import WidgetKit

@main
struct StupidWidgetsWidgetBundle: WidgetBundle {
  var body: some Widget {
    StupidWidgetsWidget()
  }
}

struct ScriptEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Script")
  static let defaultQuery = ScriptQuery()

  let id: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(id)")
  }
}

struct ScriptQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [ScriptEntity] {
    try StupidWidgetsWidgetStorage.availableScripts()
      .filter { identifiers.contains($0.name) }
      .map { ScriptEntity(id: $0.name) }
  }

  func suggestedEntities() async throws -> [ScriptEntity] {
    try StupidWidgetsWidgetStorage.availableScripts().map { ScriptEntity(id: $0.name) }
  }

  func defaultResult() async -> ScriptEntity? {
    try? await suggestedEntities().first
  }
}

struct SelectScriptIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Select Script"
  static let description = IntentDescription("Choose the script this widget instance runs.")

  @Parameter(title: "Script")
  var script: ScriptEntity?
}

struct StupidWidgetsWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "StupidWidgetsWidget",
      intent: SelectScriptIntent.self,
      provider: Provider()
    ) { entry in
      ScriptWidgetSnapshotView(snapshot: entry.snapshot)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("stupid widgets")
    .description("Runs a selected stupid widgets script.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }

  struct Entry: TimelineEntry {
    let date: Date
    let snapshot: ScriptWidgetSnapshot
  }

  struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
      Entry(
        date: .now,
        snapshot: .message(title: "stupid widgets", body: "Select a widget script.")
      )
    }

    func snapshot(for configuration: SelectScriptIntent, in context: Context) async -> Entry {
      await entry(for: configuration)
    }

    func timeline(for configuration: SelectScriptIntent, in context: Context) async -> Timeline<
      Entry
    > {
      let entry = await entry(for: configuration)
      let refresh = entry.snapshot.refreshAfterDate ?? .now.addingTimeInterval(30 * 60)
      return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func entry(for configuration: SelectScriptIntent) async -> Entry {
      let snapshot: ScriptWidgetSnapshot
      do {
        let scripts = try StupidWidgetsWidgetStorage.availableScripts()
        guard
          let script = configuration.script
            .flatMap({ selected in scripts.first { $0.name == selected.id } })
            ?? scripts.first
        else {
          throw CocoaError(.fileNoSuchFile)
        }
        snapshot = await ScriptWidgetRunner.run(script: script)
      } catch {
        snapshot = .message(
          title: "stupid widgets",
          body: "Create and run a widget script in the app first."
        )
      }
      return Entry(date: .now, snapshot: snapshot)
    }
  }
}

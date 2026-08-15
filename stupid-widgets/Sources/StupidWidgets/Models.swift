import Foundation
import WidgetKit

struct Script: Identifiable, Hashable {
  let id: UUID
  var name: String
  var iconColor: String
  var iconGlyph: String
  var source: String
  var alwaysRunInApp: Bool
  var shareSheetInputs: [String]
  var fileURL: URL

  private struct FileContents: Codable {
    struct Icon: Codable {
      var color: String
      var glyph: String
    }

    var name: String
    var icon: Icon
    var script: String
    var alwaysRunInApp: Bool
    var shareSheetInputs: [String]

    enum CodingKeys: String, CodingKey {
      case name, icon, script
      case alwaysRunInApp = "always_run_in_app"
      case shareSheetInputs = "share_sheet_inputs"
    }
  }

  static func fromFile(_ url: URL) throws -> Script {
    let value = try JSONDecoder().decode(FileContents.self, from: Data(contentsOf: url))
    return Script(
      id: UUID(),
      name: value.name,
      iconColor: value.icon.color,
      iconGlyph: value.icon.glyph,
      source: value.script,
      alwaysRunInApp: value.alwaysRunInApp,
      shareSheetInputs: value.shareSheetInputs,
      fileURL: url
    )
  }

  func encoded() throws -> Data {
    let value = FileContents(
      name: name,
      icon: .init(color: iconColor, glyph: iconGlyph),
      script: source,
      alwaysRunInApp: alwaysRunInApp,
      shareSheetInputs: shareSheetInputs
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
}

@MainActor
final class ScriptStore: ObservableObject {
  @Published private(set) var scripts: [Script] = []
  @Published var errorMessage: String?

  private let directory: URL

  init(directory: URL? = nil) {
    self.directory =
      directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    reload()
  }

  func reload() {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try seedBundledScripts()
      let urls = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension.lowercased() == "scriptable" }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      scripts = try urls.map(Script.fromFile)
      syncWidgetScripts()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func script(id: UUID) -> Script? {
    scripts.first { $0.id == id }
  }

  @discardableResult
  func create(name: String = "Untitled Script") -> Script? {
    do {
      let uniqueName = try availableName(startingWith: name)
      let url = fileURL(for: uniqueName)
      let script = Script(
        id: UUID(),
        name: uniqueName,
        iconColor: "deep-blue",
        iconGlyph: "doc.text",
        source: "// \(uniqueName)\n",
        alwaysRunInApp: false,
        shareSheetInputs: [],
        fileURL: url
      )
      try write(script)
      scripts.append(script)
      sort()
      return script
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func updateSource(id: UUID, source: String) {
    guard let index = scripts.firstIndex(where: { $0.id == id }), scripts[index].source != source
    else { return }
    var updated = scripts[index]
    updated.source = source
    do {
      try write(updated)
      scripts[index] = updated
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func reloadWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
  }

  func rename(id: UUID, to proposedName: String) {
    guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
    let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValid(name: name) else {
      errorMessage = "Script names cannot be empty or contain / or :."
      return
    }
    guard
      !scripts.contains(where: {
        $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else {
      errorMessage = "A script named \(name) already exists."
      return
    }
    var updated = scripts[index]
    let oldURL = updated.fileURL
    updated.name = name
    updated.fileURL = fileURL(for: name)
    do {
      try write(updated)
      if oldURL != updated.fileURL {
        try FileManager.default.removeItem(at: oldURL)
        removeWidgetScript(named: oldURL.lastPathComponent)
      }
      scripts[index] = updated
      sort()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(id: UUID) {
    guard let script = script(id: id) else { return }
    do {
      try FileManager.default.removeItem(at: script.fileURL)
      removeWidgetScript(named: script.fileURL.lastPathComponent)
      scripts.removeAll { $0.id == id }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func importScript(from sourceURL: URL) {
    let accessed = sourceURL.startAccessingSecurityScopedResource()
    defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
    do {
      var script = try Script.fromFile(sourceURL)
      script.name = try availableName(startingWith: script.name)
      script.fileURL = fileURL(for: script.name)
      try write(script)
      scripts.append(script)
      sort()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func seedBundledScripts() throws {
    for source in Bundle.main.urls(forResourcesWithExtension: "scriptable", subdirectory: nil) ?? []
    {
      let destination = directory.appendingPathComponent(source.lastPathComponent)
      if !FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.copyItem(at: source, to: destination)
      }
    }
  }

  private func write(_ script: Script) throws {
    try script.encoded().write(to: script.fileURL, options: .atomic)
    if let directory = StupidWidgetsWidgetStorage.scriptsDirectory {
      try script.encoded().write(
        to: directory.appendingPathComponent(script.fileURL.lastPathComponent),
        options: .atomic
      )
    }
  }

  private func syncWidgetScripts() {
    guard let directory = StupidWidgetsWidgetStorage.scriptsDirectory else { return }
    let expected = Set(scripts.map { $0.fileURL.lastPathComponent })
    let existing =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    for url in existing where !expected.contains(url.lastPathComponent) {
      try? FileManager.default.removeItem(at: url)
    }
    for script in scripts {
      try? script.encoded().write(
        to: directory.appendingPathComponent(script.fileURL.lastPathComponent),
        options: .atomic
      )
    }
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func removeWidgetScript(named filename: String) {
    guard let directory = StupidWidgetsWidgetStorage.scriptsDirectory else { return }
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
  }

  private func availableName(startingWith requested: String) throws -> String {
    let base = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValid(name: base) else { throw CocoaError(.fileWriteInvalidFileName) }
    if !scripts.contains(where: { $0.name.caseInsensitiveCompare(base) == .orderedSame }) {
      return base
    }
    for number in 2...999 {
      let candidate = "\(base) \(number)"
      if !scripts.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
        return candidate
      }
    }
    throw CocoaError(.fileWriteFileExists)
  }

  private func isValid(name: String) -> Bool {
    !name.isEmpty && !name.contains("/") && !name.contains(":") && name != "." && name != ".."
  }

  private func fileURL(for name: String) -> URL {
    directory.appendingPathComponent(name).appendingPathExtension("scriptable")
  }

  private func sort() {
    scripts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

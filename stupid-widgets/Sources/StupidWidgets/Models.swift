import CryptoKit
import Foundation
import WidgetKit

private enum UbiquityDirectory {
  static func scriptsDirectory() -> URL? {
    guard
      let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
    else { return nil }
    let directory = container.appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("Scripts", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

struct Script: Identifiable, Hashable {
  let id: UUID
  var name: String
  var iconColor: String
  var iconGlyph: String
  var source: String
  var alwaysRunInApp: Bool
  var previewFamily: String
  var shareSheetInputs: [String]
  var fileURL: URL

  var modificationDate: Date? {
    var url = fileURL
    url.removeAllCachedResourceValues()
    return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  private struct FileContents: Codable {
    struct Icon: Codable {
      var color: String
      var glyph: String
    }

    var name: String
    var icon: Icon
    var script: String
    var alwaysRunInApp: Bool
    var previewFamily: String?
    var shareSheetInputs: [String]
    var id: String?

    enum CodingKeys: String, CodingKey {
      case name, icon, script
      case alwaysRunInApp = "always_run_in_app"
      case previewFamily = "preview_family"
      case shareSheetInputs = "share_sheet_inputs"
      case id
    }
  }

  static func fromFile(_ url: URL) throws -> Script {
    let value = try JSONDecoder().decode(FileContents.self, from: Data(contentsOf: url))
    let id = value.id.flatMap(UUID.init(uuidString:)) ?? stableID(for: url.lastPathComponent)
    return Script(
      id: id,
      name: value.name,
      iconColor: value.icon.color,
      iconGlyph: value.icon.glyph,
      source: value.script,
      alwaysRunInApp: value.alwaysRunInApp,
      previewFamily: value.previewFamily ?? "medium",
      shareSheetInputs: value.shareSheetInputs,
      fileURL: url
    )
  }

  static func stableID(for name: String) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    let digest = Array(SHA256.hash(data: Data(name.utf8)))
    for index in 0..<16 {
      bytes[index] = digest[index]
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }

  func encoded() throws -> Data {
    let value = FileContents(
      name: name,
      icon: .init(color: iconColor, glyph: iconGlyph),
      script: source,
      alwaysRunInApp: alwaysRunInApp,
      previewFamily: previewFamily,
      shareSheetInputs: shareSheetInputs,
      id: id.uuidString
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
  private var ubiquityQuery: NSMetadataQuery?
  private var ubiquityObserver: NSObjectProtocol?

  init(directory: URL? = nil) {
    if let directory {
      self.directory = directory
    } else if let ubiquityDirectory = UbiquityDirectory.scriptsDirectory() {
      self.directory = ubiquityDirectory
      observeUbiquityChanges()
    } else {
      self.directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    reload()
  }

  private func observeUbiquityChanges() {
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(
      format: "%K ENDSWITH '.widget'", "kMDItemFSName")
    ubiquityObserver = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidUpdate,
      object: query,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
    ubiquityQuery = query
    query.start()
  }

  func reload() {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try seedBundledScripts()
      let urls = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
      )
      .filter { $0.pathExtension.lowercased() == "widget" }
      scripts = try urls.map(Script.fromFile)
      sort()
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
  func create(name: String) -> Script? {
    do {
      let uniqueName = try availableName(startingWith: name)
      let url = fileURL(for: uniqueName)
      let script = Script(
        id: Script.stableID(for: "\(uniqueName).widget"),
        name: uniqueName,
        iconColor: "deep-blue",
        iconGlyph: "doc.text",
        source: """
          // A simple widget that shows the date and time.
          let widget = new ListWidget()
          widget.backgroundColor = new Color("#1b1b2f")
          let gradient = new LinearGradient()
          gradient.colors = [new Color("#16222A"), new Color("#3A6073")]
          gradient.locations = [0, 1]
          widget.backgroundGradient = gradient

          let title = widget.addText("Hello, world!")
          title.font = Font.boldSystemFont(16)
          title.textColor = Color.white()

          widget.addSpacer(8)

          let dateText = widget.addDate(new Date())
          dateText.font = Font.mediumSystemFont(13)
          dateText.textColor = Color.white()
          dateText.textOpacity = 0.85
          dateText.applyTimeStyle()

          dateText.applyDateStyle()

          Script.setWidget(widget)
          Script.complete()
          """,
        alwaysRunInApp: false,
        previewFamily: "medium",
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
      sort()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func reloadWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
  }

  func updatePreviewFamily(id: UUID, family: String) {
    guard let index = scripts.firstIndex(where: { $0.id == id }), scripts[index].previewFamily != family
    else { return }
    var updated = scripts[index]
    updated.previewFamily = family
    do {
      try write(updated)
      scripts[index] = updated
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func rename(id: UUID, to proposedName: String) {
    guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
    let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValid(name: name) else {
      errorMessage = "Widget names cannot be empty or contain / or :."
      return
    }
    guard
      !scripts.contains(where: {
        $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else {
      errorMessage = "A widget named \(name) already exists."
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
    for source in Bundle.main.urls(forResourcesWithExtension: "widget", subdirectory: nil) ?? []
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
    directory.appendingPathComponent(name).appendingPathExtension("widget")
  }

  private func sort() {
    scripts.sort {
      let leftDate = $0.modificationDate ?? .distantPast
      let rightDate = $1.modificationDate ?? .distantPast
      if leftDate != rightDate { return leftDate > rightDate }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

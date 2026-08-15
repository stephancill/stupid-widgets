import Foundation
import SwiftUI
import UIKit

public enum StupidWidgetsWidgetStorage {
  public static let appGroupID = "group.net.stupidtech.stupidwidgets"

  public static var scriptsDirectory: URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else { return nil }
    let directory = container.appendingPathComponent("Scripts", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  public static func availableScripts() throws -> [SharedWidgetScript] {
    guard let directory = scriptsDirectory else { throw CocoaError(.fileNoSuchFile) }
    return try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension.lowercased() == "scriptable" }
      .map { try JSONDecoder().decode(SharedWidgetScript.self, from: Data(contentsOf: $0)) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public static func script(named name: String) throws -> SharedWidgetScript {
    guard let script = try availableScripts().first(where: { $0.name == name }) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return script
  }
}

public struct SharedWidgetScript: Decodable, Sendable {
  public let name: String
  public let script: String
}

public struct ScriptWidgetSnapshot: Sendable {
  public let background: ScriptWidgetColor
  public let spacing: Double
  public let refreshAfterDate: Date?
  public let elements: [ScriptWidgetElement]

  public static func message(title: String, body: String) -> ScriptWidgetSnapshot {
    ScriptWidgetSnapshot(
      background: ScriptWidgetColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1),
      spacing: 8,
      refreshAfterDate: nil,
      elements: [
        .text(
          .init(
            text: title, color: .white, font: .system(size: 17), opacity: 1,
            lineLimit: 2, alignment: .left)),
        .text(
          .init(
            text: body, color: .gray, font: .system(size: 13), opacity: 1,
            lineLimit: 4, alignment: .left)),
      ]
    )
  }
}

public struct ScriptWidgetColor: Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public static let white = ScriptWidgetColor(red: 1, green: 1, blue: 1, alpha: 1)
  public static let gray = ScriptWidgetColor(red: 0.7, green: 0.72, blue: 0.75, alpha: 1)
}

public enum ScriptWidgetAlignment: Sendable {
  case left, center, right
}

public indirect enum ScriptWidgetElement: Sendable {
  case text(ScriptWidgetText)
  case image(ScriptWidgetImage)
  case spacer(Double)
  case stack(ScriptWidgetStack)
}

public struct ScriptWidgetText: Sendable {
  public let text: String
  public let color: ScriptWidgetColor
  public let font: ScriptWidgetFont
  public let opacity: Double
  public let lineLimit: Int
  public let alignment: ScriptWidgetAlignment
}

public struct ScriptWidgetFont: Sendable {
  public let name: String?
  public let size: Double
  public let weight: Double
  public let italic: Bool
  public let monospaced: Bool
  public let rounded: Bool
  public let system: Bool

  public static func system(size: Double) -> ScriptWidgetFont {
    ScriptWidgetFont(
      name: nil, size: size, weight: 0, italic: false, monospaced: false, rounded: false,
      system: true)
  }

  @MainActor
  public init(
    font: UIFont?, systemWeight: Double? = nil, isMonospaced: Bool? = nil,
    isRounded: Bool? = nil, isItalic: Bool? = nil
  ) {
    let font = font ?? UIFont.systemFont(ofSize: 17)
    let traits =
      font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
    name = font.fontName
    size = Double(font.pointSize)
    weight =
      systemWeight
      ?? (traits?[.weight] as? NSNumber)?.doubleValue
      ?? 0
    italic = isItalic ?? font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    monospaced = isMonospaced ?? font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    rounded = isRounded ?? font.fontName.contains("Rounded")
    system = font.fontName.hasPrefix(".")
  }

  private init(
    name: String?, size: Double, weight: Double, italic: Bool, monospaced: Bool, rounded: Bool,
    system: Bool
  ) {
    self.name = name
    self.size = size
    self.weight = weight
    self.italic = italic
    self.monospaced = monospaced
    self.rounded = rounded
    self.system = system
  }
}

public struct ScriptWidgetImage: Sendable {
  public let data: Data
  public let width: Double?
  public let height: Double?
  public let opacity: Double
  public let cornerRadius: Double
  public let alignment: ScriptWidgetAlignment
}

public struct ScriptWidgetStack: Sendable {
  public let horizontal: Bool
  public let spacing: Double
  public let elements: [ScriptWidgetElement]
}

public enum ScriptWidgetRunner {
  @MainActor
  public static func run(script: SharedWidgetScript) async -> ScriptWidgetSnapshot {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: script.name, runsInWidget: true)
    runtime.evaluate(script.script)

    for _ in 0..<200 where !runtime.completed {
      try? await Task.sleep(for: .milliseconds(100))
    }
    guard let widget = runtime.scriptWidget else {
      let error = runtime.consoleLines.last ?? "The selected script did not set a widget."
      return .message(title: script.name, body: error)
    }
    return snapshot(widget: widget)
  }

  @MainActor
  private static func snapshot(widget: ListWidgetModel) -> ScriptWidgetSnapshot {
    ScriptWidgetSnapshot(
      background: color(widget.backgroundColor)
        ?? ScriptWidgetColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1),
      spacing: widget.spacing,
      refreshAfterDate: widget.refreshAfterDate,
      elements: widget.children.compactMap(element)
    )
  }

  @MainActor
  private static func element(_ object: JSObject) -> ScriptWidgetElement? {
    switch object {
    case let text as WidgetTextModel:
      return .text(
        .init(
          text: text.text,
          color: color(text.textColor) ?? .white,
          font: ScriptWidgetFont(
            font: text.font?.font,
            systemWeight: text.font?.systemWeight.map { Double($0.rawValue) },
            isMonospaced: text.font?.isMonospaced,
            isRounded: text.font?.isRounded,
            isItalic: text.font?.isItalic
          ),
          opacity: text.textOpacity,
          lineLimit: text.lineLimit,
          alignment: alignment(text.alignment)
        ))
    case let date as WidgetDateModel:
      let formatter = DateFormatter()
      formatter.dateStyle = date.dateStyle
      formatter.timeStyle = date.timeStyle
      return .text(
        .init(
          text: formatter.string(from: date.date),
          color: color(date.textColor) ?? .white,
          font: ScriptWidgetFont(
            font: date.font?.font,
            systemWeight: date.font?.systemWeight.map { Double($0.rawValue) },
            isMonospaced: date.font?.isMonospaced,
            isRounded: date.font?.isRounded,
            isItalic: date.font?.isItalic
          ),
          opacity: date.textOpacity,
          lineLimit: date.lineLimit,
          alignment: alignment(date.alignment)
        ))
    case let image as WidgetImageModel:
      guard let data = image.image?.image?.pngData() else { return nil }
      return .image(
        .init(
          data: data,
          width: image.imageSize?.width,
          height: image.imageSize?.height,
          opacity: image.imageOpacity,
          cornerRadius: image.cornerRadius,
          alignment: alignment(image.alignment)
        ))
    case let spacer as WidgetSpacerModel:
      return .spacer(spacer.length)
    case let stack as WidgetStackModel:
      return .stack(
        .init(
          horizontal: stack.layout == .horizontal,
          spacing: stack.spacing,
          elements: stack.children.compactMap(element)
        ))
    default:
      return nil
    }
  }

  @MainActor
  private static func color(_ model: ColorModel?) -> ScriptWidgetColor? {
    guard let model else { return nil }
    return ScriptWidgetColor(
      red: model.red, green: model.green, blue: model.blue, alpha: model.alpha)
  }

  @MainActor
  private static func alignment(_ value: TextAlignment) -> ScriptWidgetAlignment {
    switch value {
    case .left: .left
    case .center: .center
    case .right: .right
    }
  }
}

public struct ScriptWidgetSnapshotView: View {
  private let snapshot: ScriptWidgetSnapshot

  public init(snapshot: ScriptWidgetSnapshot) {
    self.snapshot = snapshot
  }

  public var body: some View {
    ZStack {
      color(snapshot.background)
      VStack(spacing: snapshot.spacing) {
        ForEach(Array(snapshot.elements.enumerated()), id: \.offset) { _, element in
          elementView(element)
        }
      }
      .padding(14)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func elementView(_ element: ScriptWidgetElement) -> AnyView {
    switch element {
    case .text(let text):
      return AnyView(
        Text(text.text)
          .font(font(text))
          .foregroundStyle(color(text.color))
          .opacity(text.opacity)
          .lineLimit(text.lineLimit > 0 ? text.lineLimit : nil)
          .frame(maxWidth: .infinity, alignment: frameAlignment(text.alignment))
      )
    case .image(let image):
      guard let uiImage = UIImage(data: image.data) else { return AnyView(EmptyView()) }
      let width = image.width.map { CGFloat($0) }
      let height = image.height.map { CGFloat($0) }
      return AnyView(
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFit()
          .frame(width: width, height: height)
          .opacity(image.opacity)
          .clipShape(RoundedRectangle(cornerRadius: image.cornerRadius))
          .frame(maxWidth: .infinity, alignment: frameAlignment(image.alignment))
      )
    case .spacer(let length):
      return length > 0
        ? AnyView(Spacer().frame(height: length)) : AnyView(Spacer(minLength: 0))
    case .stack(let stack):
      let content = ForEach(Array(stack.elements.enumerated()), id: \.offset) { _, element in
        elementView(element)
      }
      return stack.horizontal
        ? AnyView(HStack(spacing: stack.spacing) { content })
        : AnyView(VStack(spacing: stack.spacing) { content })
    }
  }

  private func font(_ text: ScriptWidgetText) -> Font {
    if !text.font.system, let name = text.font.name {
      let font = Font.custom(name, size: text.font.size)
      return text.font.italic ? font.italic() : font
    }
    var font = Font.system(
      size: text.font.size,
      weight: weight(text.font.weight),
      design: text.font.monospaced ? .monospaced : (text.font.rounded ? .rounded : .default)
    )
    if text.font.italic { font = font.italic() }
    return font
  }

  private func weight(_ value: Double) -> Font.Weight {
    switch value {
    case ..<(-0.7): .ultraLight
    case ..<(-0.5): .thin
    case ..<(-0.2): .light
    case ..<0.1: .regular
    case ..<0.265: .medium
    case ..<0.35: .semibold
    case ..<0.48: .bold
    case ..<0.59: .heavy
    default: .black
    }
  }

  private func color(_ value: ScriptWidgetColor) -> Color {
    Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
  }

  private func frameAlignment(_ value: ScriptWidgetAlignment) -> Alignment {
    switch value {
    case .left: .leading
    case .center: .center
    case .right: .trailing
    }
  }
}

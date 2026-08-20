import Foundation
import UIKit
import WidgetRender

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
      .filter { $0.pathExtension.lowercased() == "widget" }
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

public enum ScriptWidgetRunner {
  @MainActor
  public static func run(
    script: SharedWidgetScript, family: String = "medium"
  ) async -> ScriptWidgetSnapshot {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(
      scriptName: script.name, runsInWidget: true, widgetFamily: family)
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
  static func snapshot(widget: ListWidgetModel) -> ScriptWidgetSnapshot {
    ScriptWidgetSnapshot(
      background: background(widget),
      spacing: widget.spacing,
      padding: padding(widget),
      refreshAfterDate: widget.refreshAfterDate,
      elements: widget.children.compactMap(element)
    )
  }

  @MainActor
  private static func padding(_ widget: ListWidgetModel) -> ScriptWidgetInsets {
    guard let padding = widget.padding else {
      return ScriptWidgetInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    }
    return ScriptWidgetInsets(
      top: CGFloat(padding.top),
      leading: CGFloat(padding.leading),
      bottom: CGFloat(padding.bottom),
      trailing: CGFloat(padding.trailing)
    )
  }

  @MainActor
  private static func background(_ widget: ListWidgetModel) -> ScriptWidgetBackground {
    if let gradient = widget.backgroundGradient, !gradient.colors.isEmpty {
      return .gradient(
        ScriptWidgetGradient(
          colors: gradient.colors.compactMap(color),
          locations: gradient.locations,
          startX: gradient.startPoint.x,
          startY: gradient.startPoint.y,
          endX: gradient.endPoint.x,
          endY: gradient.endPoint.y
        ))
    }
    if let image = widget.backgroundImage?.image, let data = image.pngData() {
      return .image(data)
    }
    return .color(
      color(widget.backgroundColor)
        ?? ScriptWidgetColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1))
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
          opacity: CGFloat(text.textOpacity),
          lineLimit: text.lineLimit,
          minimumScaleFactor: CGFloat(text.minimumScaleFactor),
          alignment: alignment(text.alignment)
        ))
    case let date as WidgetDateModel:
      return .text(
        .init(
          text: dateLabel(date),
          color: color(date.textColor) ?? .white,
          font: ScriptWidgetFont(
            font: date.font?.font,
            systemWeight: date.font?.systemWeight.map { Double($0.rawValue) },
            isMonospaced: date.font?.isMonospaced,
            isRounded: date.font?.isRounded,
            isItalic: date.font?.isItalic
          ),
          opacity: CGFloat(date.textOpacity),
          lineLimit: date.lineLimit,
          minimumScaleFactor: CGFloat(date.minimumScaleFactor),
          alignment: alignment(date.alignment)
        ))
    case let image as WidgetImageModel:
      guard let data = image.image?.image?.pngData() else { return nil }
      return .image(
        .init(
          data: data,
          width: image.imageSize.map { CGFloat($0.width) },
          height: image.imageSize.map { CGFloat($0.height) },
          opacity: CGFloat(image.imageOpacity),
          cornerRadius: CGFloat(image.cornerRadius),
          fills: image.contentMode == .fill,
          alignment: alignment(image.alignment)
        ))
    case let spacer as WidgetSpacerModel:
      return .spacer(spacer.length)
    case let stack as WidgetStackModel:
      return .stack(
        .init(
          horizontal: stack.layout == .horizontal,
          spacing: CGFloat(stack.spacing),
          elements: stack.children.compactMap(element)
        ))
    default:
      return nil
    }
  }

  @MainActor
  private static func dateLabel(_ date: WidgetDateModel) -> String {
    if date.isRelative {
      return RelativeDateTimeFormatter().localizedString(for: date.date, relativeTo: Date())
    }
    if date.isOffset || date.isTimer {
      let comps = Calendar.current.dateComponents(
        [.hour, .minute, .second], from: Date(), to: date.date)
      let format = date.isTimer ? "%02d:%02d:%02d" : "%d:%02d:%02d"
      return String(
        format: format, abs(comps.hour ?? 0), abs(comps.minute ?? 0), abs(comps.second ?? 0))
    }
    let formatter = DateFormatter()
    formatter.dateStyle = date.dateStyle
    formatter.timeStyle = date.timeStyle
    return formatter.string(from: date.date)
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

extension ScriptWidgetFont {
  @MainActor
  public init(
    font: UIFont?, systemWeight: Double? = nil, isMonospaced: Bool? = nil,
    isRounded: Bool? = nil, isItalic: Bool? = nil
  ) {
    let font = font ?? UIFont.systemFont(ofSize: 17)
    let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
    self.init(
      name: font.fontName,
      size: Double(font.pointSize),
      weight: systemWeight ?? (traits?[.weight] as? NSNumber)?.doubleValue ?? 0,
      italic: isItalic ?? font.fontDescriptor.symbolicTraits.contains(.traitItalic),
      monospaced: isMonospaced ?? font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace),
      rounded: isRounded ?? font.fontName.contains("Rounded"),
      system: font.fontName.hasPrefix(".")
    )
  }
}
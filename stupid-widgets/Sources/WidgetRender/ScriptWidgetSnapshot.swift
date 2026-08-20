import Foundation
import SwiftUI

public struct ScriptWidgetSnapshot: Sendable {
  public let background: ScriptWidgetBackground
  public let spacing: Double
  public let padding: ScriptWidgetInsets
  public let refreshAfterDate: Date?
  public let elements: [ScriptWidgetElement]

  public init(
    background: ScriptWidgetBackground,
    spacing: Double,
    padding: ScriptWidgetInsets,
    refreshAfterDate: Date?,
    elements: [ScriptWidgetElement]
  ) {
    self.background = background
    self.spacing = spacing
    self.padding = padding
    self.refreshAfterDate = refreshAfterDate
    self.elements = elements
  }

  public static func message(title: String, body: String) -> ScriptWidgetSnapshot {
    ScriptWidgetSnapshot(
      background: .color(ScriptWidgetColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)),
      spacing: 8,
      padding: .init(top: 14, leading: 14, bottom: 14, trailing: 14),
      refreshAfterDate: nil,
      elements: [
        .text(
          .init(
            text: title, color: .white, font: .system(size: 17), opacity: 1, lineLimit: 2,
            minimumScaleFactor: 1, alignment: .left)),
        .text(
          .init(
            text: body, color: .gray, font: .system(size: 13), opacity: 1, lineLimit: 4,
            minimumScaleFactor: 1, alignment: .left)),
      ])
  }
}

public struct ScriptWidgetInsets: Sendable {
  public let top: CGFloat
  public let leading: CGFloat
  public let bottom: CGFloat
  public let trailing: CGFloat

  public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }
}

public enum ScriptWidgetBackground: Sendable {
  case color(ScriptWidgetColor)
  case gradient(ScriptWidgetGradient)
  case image(Data)
}

public struct ScriptWidgetGradient: Sendable {
  public let colors: [ScriptWidgetColor]
  public let locations: [Double]
  public let startX: Double
  public let startY: Double
  public let endX: Double
  public let endY: Double

  public init(
    colors: [ScriptWidgetColor], locations: [Double], startX: Double, startY: Double, endX: Double,
    endY: Double
  ) {
    self.colors = colors
    self.locations = locations
    self.startX = startX
    self.startY = startY
    self.endX = endX
    self.endY = endY
  }
}

public struct ScriptWidgetColor: Sendable, Equatable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

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
  public let opacity: CGFloat
  public let lineLimit: Int
  public let minimumScaleFactor: CGFloat
  public let alignment: ScriptWidgetAlignment

  public init(
    text: String, color: ScriptWidgetColor, font: ScriptWidgetFont, opacity: CGFloat,
    lineLimit: Int, minimumScaleFactor: CGFloat, alignment: ScriptWidgetAlignment
  ) {
    self.text = text
    self.color = color
    self.font = font
    self.opacity = opacity
    self.lineLimit = lineLimit
    self.minimumScaleFactor = minimumScaleFactor
    self.alignment = alignment
  }
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

  public init(
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
  public let width: CGFloat?
  public let height: CGFloat?
  public let opacity: CGFloat
  public let cornerRadius: CGFloat
  public let fills: Bool
  public let alignment: ScriptWidgetAlignment

  public init(
    data: Data, width: CGFloat?, height: CGFloat?, opacity: CGFloat, cornerRadius: CGFloat,
    fills: Bool, alignment: ScriptWidgetAlignment
  ) {
    self.data = data
    self.width = width
    self.height = height
    self.opacity = opacity
    self.cornerRadius = cornerRadius
    self.fills = fills
    self.alignment = alignment
  }
}

public struct ScriptWidgetStack: Sendable {
  public let horizontal: Bool
  public let spacing: CGFloat
  public let elements: [ScriptWidgetElement]

  public init(horizontal: Bool, spacing: CGFloat, elements: [ScriptWidgetElement]) {
    self.horizontal = horizontal
    self.spacing = spacing
    self.elements = elements
  }
}

extension Image {
  public init(widgetImageData data: Data) {
    #if canImport(UIKit)
      self.init(uiImage: UIImage(data: data) ?? UIImage())
    #elseif canImport(AppKit)
      self.init(nsImage: NSImage(data: data) ?? NSImage())
    #endif
  }
}

public struct ScriptWidgetSnapshotView: View {
  private let snapshot: ScriptWidgetSnapshot

  public init(snapshot: ScriptWidgetSnapshot) {
    self.snapshot = snapshot
  }

  public var body: some View {
    ZStack {
      VStack(alignment: .leading, spacing: snapshot.spacing) {
        ForEach(Array(snapshot.elements.enumerated()), id: \.offset) { _, element in
          elementView(element, parentAxis: .vertical)
        }
      }
      .padding(.top, snapshot.padding.top)
      .padding(.leading, snapshot.padding.leading)
      .padding(.bottom, snapshot.padding.bottom)
      .padding(.trailing, snapshot.padding.trailing)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(background)
  }

  @ViewBuilder
  private var background: some View {
    switch snapshot.background {
    case .color(let value):
      color(value)
    case .gradient(let value):
      LinearGradient(
        gradient: gradient(value),
        startPoint: UnitPoint(x: value.startX, y: value.startY),
        endPoint: UnitPoint(x: value.endX, y: value.endY)
      )
    case .image(let data):
      Image(widgetImageData: data).resizable().scaledToFill()
    }
  }

  private func gradient(_ value: ScriptWidgetGradient) -> Gradient {
    let colors = value.colors.map(color)
    guard value.locations.count == colors.count else { return Gradient(colors: colors) }
    return Gradient(
      stops: zip(colors, value.locations).map { color, location in
        Gradient.Stop(color: color, location: location)
      })
  }

  private func elementView(_ element: ScriptWidgetElement, parentAxis: Axis) -> AnyView {
    switch element {
    case .text(let text):
      let view = Text(text.text)
        .font(font(text))
        .foregroundStyle(color(text.color))
        .opacity(text.opacity)
        .lineLimit(text.lineLimit > 0 ? text.lineLimit : nil)
        .minimumScaleFactor(text.minimumScaleFactor)
      guard parentAxis == .vertical else { return AnyView(view) }
      return AnyView(view.frame(maxWidth: .infinity, alignment: frameAlignment(text.alignment)))
    case .image(let image):
      guard image.data.isEmpty == false else { return AnyView(EmptyView()) }
      let view = Image(widgetImageData: image.data)
        .resizable()
        .aspectRatio(contentMode: image.fills ? .fill : .fit)
        .frame(width: image.width, height: image.height)
        .opacity(image.opacity)
        .clipShape(RoundedRectangle(cornerRadius: image.cornerRadius))
      guard parentAxis == .vertical else { return AnyView(view) }
      return AnyView(
        view.frame(maxWidth: .infinity, alignment: frameAlignment(image.alignment)))
    case .spacer(let length):
      guard length > 0 else { return AnyView(Spacer(minLength: 0)) }
      return parentAxis == .horizontal
        ? AnyView(Spacer().frame(width: length)) : AnyView(Spacer().frame(height: length))
    case .stack(let stack):
      let view: AnyView
      if stack.horizontal {
        view = AnyView(
          HStack(spacing: stack.spacing) {
            ForEach(Array(stack.elements.enumerated()), id: \.offset) { _, element in
              elementView(element, parentAxis: .horizontal)
            }
          })
      } else {
        view = AnyView(
          VStack(alignment: .leading, spacing: stack.spacing) {
            ForEach(Array(stack.elements.enumerated()), id: \.offset) { _, element in
              elementView(element, parentAxis: .vertical)
            }
          })
      }
      guard parentAxis == .vertical else { return view }
      return AnyView(view.frame(maxWidth: .infinity, alignment: .leading))
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
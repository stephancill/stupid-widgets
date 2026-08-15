import Foundation
import JavaScriptCore
import UIKit

// MARK: - Value models

final class ColorModel: JSObject {
  var id = 0
  var uiColor: UIColor
  var hex: String
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double

  init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
    self.uiColor = UIColor(red: red, green: green, blue: blue, alpha: alpha)
    self.hex = String(
      format: "#%02X%02X%02X%02X",
      Int(red * 255), Int(green * 255), Int(blue * 255), Int(alpha * 255)
    )
  }

  convenience init?(hexString: String) {
    var hex = hexString.trimmingCharacters(in: .whitespaces)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    let a = hex.count == 8 ? Double((value >> 24) & 0xFF) / 255 : 1
    self.init(red: r, green: g, blue: b, alpha: a)
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "hex": return hex
    case "red": return red
    case "green": return green
    case "blue": return blue
    case "alpha": return alpha
    default: return nil
    }
  }

  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "hex":
      if let v = runtime.string(value), let c = ColorModel(hexString: v) { uiColor = c.uiColor }
    case "red": red = runtime.double(value) ?? red
    case "green": green = runtime.double(value) ?? green
    case "blue": blue = runtime.double(value) ?? blue
    case "alpha": alpha = runtime.double(value) ?? alpha
    default: break
    }
  }

  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class FontModel: JSObject {
  var id = 0
  let font: UIFont
  let systemWeight: UIFont.Weight?
  let isMonospaced: Bool
  let isItalic: Bool

  init(
    font: UIFont, systemWeight: UIFont.Weight? = nil, isMonospaced: Bool = false,
    isItalic: Bool = false
  ) {
    self.font = font
    self.systemWeight = systemWeight
    self.isMonospaced = isMonospaced
    self.isItalic = isItalic
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "name": return font.fontName
    case "size": return Double(font.pointSize)
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class PointModel: JSObject {
  var id = 0
  var x: Double
  var y: Double
  init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    name == "x" ? x : (name == "y" ? y : nil)
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    if name == "x" {
      x = runtime.double(value) ?? x
    } else if name == "y" {
      y = runtime.double(value) ?? y
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class SizeModel: JSObject {
  var id = 0
  var width: Double
  var height: Double
  init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    name == "width" ? width : (name == "height" ? height : nil)
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    if name == "width" {
      width = runtime.double(value) ?? width
    } else if name == "height" {
      height = runtime.double(value) ?? height
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class RectModel: JSObject {
  var id = 0
  var x: Double, y: Double, width: Double, height: Double
  init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "x": return x
    case "y": return y
    case "width": return width
    case "height": return height
    case "minX": return x
    case "minY": return y
    case "maxX": return x + width
    case "maxY": return y + height
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    guard let v = runtime.double(value) else { return }
    switch name {
    case "x": x = v
    case "y": y = v
    case "width": width = v
    case "height": height = v
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class ImageModel: JSObject {
  var id = 0
  var image: UIImage?
  init(image: UIImage?) { self.image = image }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    if name == "size", let image {
      return runtime.toJS(
        runtime.alloc(SizeModel(width: Double(image.size.width), height: Double(image.size.height)))
      )
    }
    return nil
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class DataModel: JSObject {
  var id = 0
  var data: Data
  init(data: Data) { self.data = data }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? { nil }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "toRawString": return String(data: data, encoding: .utf8)
    case "toBase64String": return data.base64EncodedString()
    case "getBytes": return data.map { NSNumber(value: $0) }
    default: return nil
    }
  }
}

// MARK: - Widget element models

enum WidgetLayout { case vertical, horizontal }

class WidgetElementModel: JSObject {
  var id = 0
  var url: String?
  var backgroundColor: ColorModel?
  var backgroundImage: ImageModel?
  var backgroundGradient: LinearGradientModel?

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "url": return url
    case "backgroundColor": return backgroundColor.map { runtime.toJS($0) }
    case "backgroundImage": return backgroundImage.map { runtime.toJS($0) }
    case "backgroundGradient": return backgroundGradient.map { runtime.toJS($0) }
    default: return nil
    }
  }

  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "url": url = runtime.string(value)
    case "backgroundColor": backgroundColor = runtime.nativeObject(value) as? ColorModel
    case "backgroundImage": backgroundImage = runtime.nativeObject(value) as? ImageModel
    case "backgroundGradient":
      backgroundGradient = runtime.nativeObject(value) as? LinearGradientModel
    default: break
    }
  }

  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class WidgetTextModel: WidgetElementModel {
  var text: String
  var textColor: ColorModel?
  var font: FontModel?
  var textOpacity: Double = 1
  var lineLimit: Int = 0
  var minimumScaleFactor: Double = 1
  var alignment: TextAlignment = .left

  init(text: String) {
    self.text = text
    super.init()
  }

  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "text": return text
    case "textColor": return textColor.map { runtime.toJS($0) }
    case "font": return font.map { runtime.toJS($0) }
    case "textOpacity": return textOpacity
    case "lineLimit": return lineLimit
    case "minimumScaleFactor": return minimumScaleFactor
    default: return super.jsGet(runtime, name)
    }
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "text": text = runtime.string(value) ?? text
    case "textColor": textColor = runtime.nativeObject(value) as? ColorModel
    case "font": font = runtime.nativeObject(value) as? FontModel
    case "textOpacity": textOpacity = runtime.double(value) ?? textOpacity
    case "lineLimit": lineLimit = runtime.double(value).map { Int($0) } ?? lineLimit
    case "minimumScaleFactor": minimumScaleFactor = runtime.double(value) ?? minimumScaleFactor
    default: super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "leftAlignText": alignment = .left
    case "centerAlignText": alignment = .center
    case "rightAlignText": alignment = .right
    default: return nil
    }
    return nil
  }
}

final class WidgetDateModel: WidgetElementModel {
  var date: Date
  var textColor: ColorModel?
  var font: FontModel?
  var textOpacity: Double = 1
  var lineLimit: Int = 0
  var minimumScaleFactor: Double = 1
  var alignment: TextAlignment = .left
  var dateStyle: DateFormatter.Style = .medium
  var timeStyle: DateFormatter.Style = .none
  var isRelative = false
  var isOffset = false
  var isTimer = false

  init(date: Date) {
    self.date = date
    super.init()
  }

  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "date": return date
    case "textColor": return textColor.map { runtime.toJS($0) }
    case "font": return font.map { runtime.toJS($0) }
    case "textOpacity": return textOpacity
    case "lineLimit": return lineLimit
    default: return super.jsGet(runtime, name)
    }
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "date": date = runtime.date(value) ?? date
    case "textColor": textColor = runtime.nativeObject(value) as? ColorModel
    case "font": font = runtime.nativeObject(value) as? FontModel
    case "textOpacity": textOpacity = runtime.double(value) ?? textOpacity
    case "lineLimit": lineLimit = runtime.double(value).map { Int($0) } ?? lineLimit
    default: super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "applyTimeStyle": timeStyle = .short
    case "applyDateStyle": dateStyle = .medium
    case "applyRelativeStyle": isRelative = true
    case "applyOffsetStyle": isOffset = true
    case "applyTimerStyle": isTimer = true
    case "leftAlignText": alignment = .left
    case "centerAlignText": alignment = .center
    case "rightAlignText": alignment = .right
    default: return nil
    }
    return nil
  }
}

final class WidgetImageModel: WidgetElementModel {
  var image: ImageModel?
  var resizable = true
  var imageSize: SizeModel?
  var imageOpacity: Double = 1
  var cornerRadius: Double = 0
  var borderWidth: Double = 0
  var borderColor: ColorModel?
  var tintColor: ColorModel?
  var alignment: TextAlignment = .left
  var contentMode: ContentMode = .fit

  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "image": return image.map { runtime.toJS($0) }
    case "resizable": return resizable
    case "imageSize": return imageSize.map { runtime.toJS($0) }
    case "imageOpacity": return imageOpacity
    case "cornerRadius": return cornerRadius
    case "borderWidth": return borderWidth
    case "borderColor": return borderColor.map { runtime.toJS($0) }
    case "tintColor": return tintColor.map { runtime.toJS($0) }
    default: return super.jsGet(runtime, name)
    }
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "image": image = runtime.nativeObject(value) as? ImageModel
    case "resizable": resizable = runtime.bool(value) ?? resizable
    case "imageSize": imageSize = runtime.nativeObject(value) as? SizeModel
    case "imageOpacity": imageOpacity = runtime.double(value) ?? imageOpacity
    case "cornerRadius": cornerRadius = runtime.double(value) ?? cornerRadius
    case "borderWidth": borderWidth = runtime.double(value) ?? borderWidth
    case "borderColor": borderColor = runtime.nativeObject(value) as? ColorModel
    case "tintColor": tintColor = runtime.nativeObject(value) as? ColorModel
    default: super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "applyFittingContentMode": contentMode = .fit
    case "applyFillingContentMode": contentMode = .fill
    case "leftAlignImage": alignment = .left
    case "centerAlignImage": alignment = .center
    case "rightAlignImage": alignment = .right
    default: return nil
    }
    return nil
  }
}

final class WidgetSpacerModel: WidgetElementModel {
  var length: Double = 0
  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    name == "length" ? length : super.jsGet(runtime, name)
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    if name == "length" {
      length = runtime.double(value) ?? length
    } else {
      super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class WidgetStackModel: WidgetElementModel {
  var spacing: Double = 0
  var size: SizeModel?
  var cornerRadius: Double = 0
  var borderWidth: Double = 0
  var borderColor: ColorModel?
  var layout: WidgetLayout = .horizontal
  var alignment: WidgetAlignment = .top
  var padding: EdgeInsets? = nil
  var usesDefaultPadding = false
  var children: [JSObject] = []

  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "spacing": return spacing
    case "size": return size.map { runtime.toJS($0) }
    case "cornerRadius": return cornerRadius
    case "borderWidth": return borderWidth
    case "borderColor": return borderColor.map { runtime.toJS($0) }
    default: return super.jsGet(runtime, name)
    }
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "spacing": spacing = runtime.double(value) ?? spacing
    case "size": size = runtime.nativeObject(value) as? SizeModel
    case "cornerRadius": cornerRadius = runtime.double(value) ?? cornerRadius
    case "borderWidth": borderWidth = runtime.double(value) ?? borderWidth
    case "borderColor": borderColor = runtime.nativeObject(value) as? ColorModel
    default: super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addText":
      let el = runtime.alloc(WidgetTextModel(text: runtime.string(args.first) ?? ""))
      children.append(el)
      return el
    case "addDate":
      let el = runtime.alloc(WidgetDateModel(date: runtime.date(args.first) ?? Date()))
      children.append(el)
      return el
    case "addImage":
      let el = runtime.alloc(WidgetImageModel())
      (el as? WidgetImageModel)?.image = runtime.nativeObject(args.first) as? ImageModel
      children.append(el)
      return el
    case "addSpacer":
      let el = runtime.alloc(WidgetSpacerModel())
      (el as? WidgetSpacerModel)?.length = runtime.double(args.first) ?? 0
      children.append(el)
      return el
    case "addStack":
      let el = runtime.alloc(WidgetStackModel())
      children.append(el)
      return el
    case "setPadding":
      padding = EdgeInsets(
        top: runtime.double(args.count > 0 ? args[0] : nil) ?? 0,
        leading: runtime.double(args.count > 1 ? args[1] : nil) ?? 0,
        bottom: runtime.double(args.count > 2 ? args[2] : nil) ?? 0,
        trailing: runtime.double(args.count > 3 ? args[3] : nil) ?? 0
      )
      usesDefaultPadding = false
    case "useDefaultPadding":
      padding = nil
      usesDefaultPadding = true
    case "layoutHorizontally": layout = .horizontal
    case "layoutVertically": layout = .vertical
    case "topAlignContent": alignment = .top
    case "centerAlignContent": alignment = .center
    case "bottomAlignContent": alignment = .bottom
    default: return nil
    }
    return nil
  }

  func append(child: JSObject) { children.append(child) }
}

final class LinearGradientModel: JSObject {
  var id = 0
  var colors: [ColorModel] = []
  var locations: [Double] = []
  var startPoint = PointModel(x: 0.5, y: 0)
  var endPoint = PointModel(x: 0.5, y: 1)

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "colors": return colors.map { runtime.toJS($0) }
    case "locations": return locations
    case "startPoint": return runtime.toJS(startPoint)
    case "endPoint": return runtime.toJS(endPoint)
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "colors":
      colors = runtime.nativeObjects(runtime.jsArray(value) ?? []).compactMap { $0 as? ColorModel }
    case "locations": locations = (runtime.jsArray(value) ?? []).compactMap { runtime.double($0) }
    case "startPoint": if let p = runtime.nativeObject(value) as? PointModel { startPoint = p }
    case "endPoint": if let p = runtime.nativeObject(value) as? PointModel { endPoint = p }
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

enum WidgetAlignment { case top, center, bottom }

enum TextAlignment { case left, center, right }

enum ContentMode { case fit, fill }

struct EdgeInsets {
  var top: Double
  var leading: Double
  var bottom: Double
  var trailing: Double
}

// MARK: - ListWidget

final class ListWidgetModel: WidgetElementModel {
  var spacing: Double = 0
  var refreshAfterDate: Date?
  var padding: EdgeInsets?
  var usesDefaultPadding = false
  var previewFamily: String = "medium"
  var children: [JSObject] = []

  override func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "spacing": return spacing
    case "refreshAfterDate": return refreshAfterDate.map { $0 as Any }
    default: return super.jsGet(runtime, name)
    }
  }
  override func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "spacing": spacing = runtime.double(value) ?? spacing
    case "refreshAfterDate": refreshAfterDate = runtime.date(value)
    default: super.jsSet(runtime, name, value)
    }
  }
  override func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addText":
      let el = runtime.alloc(WidgetTextModel(text: runtime.string(args.first) ?? ""))
      children.append(el)
      return el
    case "addDate":
      let el = runtime.alloc(WidgetDateModel(date: runtime.date(args.first) ?? Date()))
      children.append(el)
      return el
    case "addImage":
      let el = runtime.alloc(WidgetImageModel())
      (el as? WidgetImageModel)?.image = runtime.nativeObject(args.first) as? ImageModel
      children.append(el)
      return el
    case "addSpacer":
      let el = runtime.alloc(WidgetSpacerModel())
      (el as? WidgetSpacerModel)?.length = runtime.double(args.first) ?? 0
      children.append(el)
      return el
    case "addStack":
      let el = runtime.alloc(WidgetStackModel())
      children.append(el)
      return el
    case "setPadding":
      padding = EdgeInsets(
        top: runtime.double(args.count > 0 ? args[0] : nil) ?? 0,
        leading: runtime.double(args.count > 1 ? args[1] : nil) ?? 0,
        bottom: runtime.double(args.count > 2 ? args[2] : nil) ?? 0,
        trailing: runtime.double(args.count > 3 ? args[3] : nil) ?? 0
      )
    case "useDefaultPadding": usesDefaultPadding = true
    case "presentSmall": runtime.presentPreview(widget: self, family: "small")
    case "presentMedium": runtime.presentPreview(widget: self, family: "medium")
    case "presentLarge": runtime.presentPreview(widget: self, family: "large")
    case "presentExtraLarge": runtime.presentPreview(widget: self, family: "extraLarge")
    case "presentAccessoryInline": runtime.presentPreview(widget: self, family: "accessoryInline")
    case "presentAccessoryCircular":
      runtime.presentPreview(widget: self, family: "accessoryCircular")
    case "presentAccessoryRectangular":
      runtime.presentPreview(widget: self, family: "accessoryRectangular")
    default: return nil
    }
    return nil
  }

  func append(child: JSObject) { children.append(child) }
}

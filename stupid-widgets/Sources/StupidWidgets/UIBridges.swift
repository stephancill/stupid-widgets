import Foundation
import JavaScriptCore
import UIKit

// MARK: - Presentation models (viewed by SwiftUI)

enum AlertActionStyle { case `default`, cancel, destructive }
struct AlertAction {
  let title: String
  let style: AlertActionStyle
  let url: String?
}
struct AlertRequest: Identifiable {
  let id = UUID()
  let title: String
  let message: String
  let actions: [AlertAction]
  var textFieldValues: [String] = []
}

enum PreviewKind { case widget, text, image }
struct PreviewRequest: Identifiable {
  let id = UUID()
  let kind: PreviewKind
  var family: String = "medium"
  var widget: ListWidgetModel?
  var text: String?
  var image: ImageModel?
}

// MARK: - Alert

final class AlertModel: JSObject {
  var id = 0
  var title: String?
  var message: String?
  var actions: [AlertAction] = []
  var textFieldCount = 0

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "title": return title
    case "message": return message
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "title": title = runtime.string(value)
    case "message": message = runtime.string(value)
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addAction":
      actions.append(
        AlertAction(
          title: runtime.string(args.first) ?? "", style: .default,
          url: runtime.string(args.count > 1 ? args[1] : nil)))
    case "addCancelAction":
      actions.append(
        AlertAction(title: runtime.string(args.first) ?? "Cancel", style: .cancel, url: nil))
    case "addDestructiveAction":
      actions.append(
        AlertAction(title: runtime.string(args.first) ?? "", style: .destructive, url: nil))
    case "addTextField", "addSecureTextField":
      textFieldCount += 1
    default: return nil
    }
    return nil
  }
  func jsAsync(
    _ runtime: JSRuntime, _ name: String, _ args: [Any], _ resolve: JSValue, _ reject: JSValue
  ) {
    runtime.presentAlert(from: self, resolve: resolve)
  }
}

// MARK: - UITable

final class UITableModel: JSObject {
  var id = 0
  var showSeparators = false
  var rows: [UITableRowModel] = []
  var pendingResolve: JSValue?

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    name == "showSeparators" ? showSeparators : nil
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    if name == "showSeparators" { showSeparators = runtime.bool(value) ?? showSeparators }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addRow":
      if let row = runtime.nativeObject(args.first) as? UITableRowModel { rows.append(row) }
    case "removeRow":
      if let row = runtime.nativeObject(args.first) as? UITableRowModel,
        let index = rows.firstIndex(where: { $0 === row })
      {
        rows.remove(at: index)
      }
    case "removeAllRows": rows.removeAll()
    default: return nil
    }
    return nil
  }
  func jsAsync(
    _ runtime: JSRuntime, _ name: String, _ args: [Any], _ resolve: JSValue, _ reject: JSValue
  ) {
    pendingResolve = resolve
    runtime.activeTable = self
  }
}

final class UITableRowModel: JSObject {
  var id = 0
  var height: Double = 44
  var cellSpacing: Double = 0
  var isHeader = false
  var dismissOnSelect = true
  var onSelect: JSValue?
  var cells: [UITableCellModel] = []

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "height": return height
    case "cellSpacing": return cellSpacing
    case "isHeader": return isHeader
    case "dismissOnSelect": return dismissOnSelect
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "height": height = runtime.double(value) ?? height
    case "cellSpacing": cellSpacing = runtime.double(value) ?? cellSpacing
    case "isHeader": isHeader = runtime.bool(value) ?? isHeader
    case "dismissOnSelect": dismissOnSelect = runtime.bool(value) ?? dismissOnSelect
    case "onSelect": onSelect = value as? JSValue
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addCell":
      if let cell = runtime.nativeObject(args.first) as? UITableCellModel { cells.append(cell) }
      return cells.last.map { runtime.toJS($0) }
    case "addText":
      let cell =
        runtime.alloc(UITableCellModel(kind: .text, text: runtime.string(args.first)))
        as! UITableCellModel
      cells.append(cell)
      return runtime.toJS(cell)
    case "addImage":
      let cell = runtime.alloc(UITableCellModel(kind: .image)) as! UITableCellModel
      if let img = runtime.nativeObject(args.first) as? ImageModel { cell.image = img }
      cells.append(cell)
      return runtime.toJS(cell)
    case "addImageAtURL":
      let cell =
        runtime.alloc(UITableCellModel(kind: .imageAtURL, text: runtime.string(args.first)))
        as! UITableCellModel
      cells.append(cell)
      return runtime.toJS(cell)
    case "addButton":
      let cell =
        runtime.alloc(UITableCellModel(kind: .button, text: runtime.string(args.first)))
        as! UITableCellModel
      cells.append(cell)
      return runtime.toJS(cell)
    default: return nil
    }
  }
}

enum UITableCellKind { case text, image, imageAtURL, button }

final class UITableCellModel: JSObject {
  var id = 0
  let kind: UITableCellKind
  var text: String?
  var image: ImageModel?
  var widthWeight: Double = 100
  var onTap: JSValue?
  var dismissOnTap = false
  var titleColor: ColorModel?
  var titleFont: FontModel?

  init(kind: UITableCellKind, text: String? = nil) {
    self.kind = kind
    self.text = text
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "text": return text
    case "widthWeight": return widthWeight
    case "dismissOnTap": return dismissOnTap
    case "titleColor": return titleColor.map { runtime.toJS($0) }
    case "titleFont": return titleFont.map { runtime.toJS($0) }
    case "image": return image.map { runtime.toJS($0) }
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "text": text = runtime.string(value)
    case "widthWeight": widthWeight = runtime.double(value) ?? widthWeight
    case "dismissOnTap": dismissOnTap = runtime.bool(value) ?? dismissOnTap
    case "onTap": onTap = value as? JSValue
    case "titleColor": titleColor = runtime.nativeObject(value) as? ColorModel
    case "titleFont": titleFont = runtime.nativeObject(value) as? FontModel
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "text": text = runtime.string(args.first)
    case "image": image = runtime.nativeObject(args.first) as? ImageModel
    case "imageAtURL": kind == .imageAtURL ? (text = runtime.string(args.first)) : ()
    case "button": break
    case "leftAligned": break
    case "centerAligned": break
    case "rightAligned": break
    default: return nil
    }
    return nil
  }
}

// MARK: - Runtime presentation helpers

extension JSRuntime {
  func presentAlert(from alert: AlertModel, resolve: JSValue) {
    activeAlert = AlertRequest(
      title: alert.title ?? "",
      message: alert.message ?? "",
      actions: alert.actions.isEmpty
        ? [AlertAction(title: "OK", style: .default, url: nil)]
        : alert.actions
    )
    pendingAlertResolve = resolve
    pendingAlertTextFieldCount = alert.textFieldCount
  }

  func presentPreview(widget: ListWidgetModel, family: String) {
    activePreview = PreviewRequest(kind: .widget, family: family, widget: widget)
  }

  func dismissAlert(index: Int) {
    pendingAlertResolve?.call(withArguments: [NSNumber(value: index)])
    pendingAlertResolve = nil
    activeAlert = nil
  }

  func dismissTable() {
    activeTable?.pendingResolve?.call(withArguments: [NSNull()])
    activeTable = nil
  }
}

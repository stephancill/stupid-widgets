import Foundation
import JavaScriptCore
import UIKit

// Pure-static namespace classes (Device, Keychain, ...) get this inert instance.
final class StaticOnlyObject: JSObject {
  var id = 0
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? { nil }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class SFSymbolModel: JSObject {
  var id = 0
  let symbolName: String
  var image: UIImage?

  init(symbolName: String) {
    self.symbolName = symbolName
    self.image = UIImage(systemName: symbolName)
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    if name == "image", let image {
      return runtime.toJS(runtime.alloc(ImageModel(image: image)))
    }
    return nil
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class FileManagerModel: JSObject {
  var id = 0
  let isICloud: Bool
  init(isICloud: Bool) { self.isICloud = isICloud }

  private var root: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private func path(_ p: String) -> String {
    if p.hasPrefix("/") { return p }
    return root.appendingPathComponent(p).path
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "documentsDirectory": return root.path
    case "libraryDirectory":
      return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path
    case "temporaryDirectory": return NSTemporaryDirectory()
    case "cacheDirectory":
      return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
    case "allFileBookmarks": return []
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    let s = { (i: Int) -> String? in args.count > i ? runtime.string(args[i]) : nil }
    switch name {
    case "documentsDirectory": return root.path
    case "libraryDirectory":
      return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path
    case "temporaryDirectory": return NSTemporaryDirectory()
    case "cacheDirectory":
      return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
    case "allFileBookmarks": return []
    case "joinPath":
      let parts = args.compactMap { runtime.string($0) }
      return parts.isEmpty ? nil : parts.joined(separator: "/")
    case "readString":
      guard let p = s(0) else { return nil }
      return try? String(contentsOfFile: path(p), encoding: .utf8)
    case "writeString":
      guard let p = s(0), let content = s(1) else { return nil }
      try? FileManager.default.createDirectory(
        atPath: (path(p) as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      try? content.write(toFile: path(p), atomically: true, encoding: .utf8)
      return nil
    case "read":
      guard let p = s(0), let data = FileManager.default.contents(atPath: path(p)) else {
        return nil
      }
      return runtime.toJS(runtime.alloc(DataModel(data: data)))
    case "write":
      guard let p = s(0),
        let data = runtime.nativeObject(args.count > 1 ? args[1] : nil) as? DataModel
      else { return nil }
      try? data.data.write(to: URL(fileURLWithPath: path(p)))
      return nil
    case "readImage":
      guard let p = s(0), let image = UIImage(contentsOfFile: path(p)) else { return nil }
      return runtime.toJS(runtime.alloc(ImageModel(image: image)))
    case "writeImage":
      guard let p = s(0),
        let img = runtime.nativeObject(args.count > 1 ? args[1] : nil) as? ImageModel,
        let image = img.image, let data = image.pngData()
      else { return nil }
      try? data.write(to: URL(fileURLWithPath: path(p)))
      return nil
    case "fileExists":
      guard let p = s(0) else { return false }
      return FileManager.default.fileExists(atPath: path(p))
    case "isDirectory":
      guard let p = s(0) else { return false }
      var isDir: ObjCBool = false
      FileManager.default.fileExists(atPath: path(p), isDirectory: &isDir)
      return isDir.boolValue
    case "createDirectory":
      guard let p = s(0) else { return nil }
      try? FileManager.default.createDirectory(atPath: path(p), withIntermediateDirectories: true)
      return nil
    case "remove":
      guard let p = s(0) else { return nil }
      try? FileManager.default.removeItem(atPath: path(p))
      return nil
    case "move", "copy":
      guard let from = s(0), let to = s(1) else { return nil }
      do {
        if name == "move" {
          try FileManager.default.moveItem(atPath: path(from), toPath: path(to))
        } else {
          try FileManager.default.copyItem(atPath: path(from), toPath: path(to))
        }
      } catch {}
      return nil
    case "listContents":
      guard let p = s(0) else { return [] }
      return (try? FileManager.default.contentsOfDirectory(atPath: path(p))) ?? []
    case "fileName":
      guard let p = s(0) else { return nil }
      let includeExtension = runtime.bool(args.count > 1 ? args[1] : nil) ?? true
      let url = URL(fileURLWithPath: p)
      return includeExtension
        ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    case "fileExtension":
      guard let p = s(0) else { return nil }
      return URL(fileURLWithPath: p).pathExtension
    case "fileSize":
      guard let p = s(0),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path(p)) as NSDictionary
      else { return 0 }
      return (attrs.fileSize() as NSNumber).doubleValue / 1024
    case "creationDate":
      guard let p = s(0),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path(p)) as NSDictionary
      else { return nil }
      return attrs.fileCreationDate()
    case "modificationDate":
      guard let p = s(0),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path(p)) as NSDictionary
      else { return nil }
      return attrs.fileModificationDate()
    case "bookmarkedPath", "bookmarkExists", "downloadFileFromiCloud", "isFileStoredIniCloud",
      "isFileDownloaded":
      return nil
    default: return nil
    }
  }
}

final class TimerModel: JSObject {
  var id = 0
  var timeInterval: Double = 0
  var repeats = false
  private var timer: Foundation.Timer?
  private var callback: JSValue?

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "timeInterval": return timeInterval
    case "repeats": return repeats
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "timeInterval": timeInterval = runtime.double(value) ?? timeInterval
    case "repeats": repeats = runtime.bool(value) ?? repeats
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "schedule":
      callback = args.first as? JSValue
      timer?.invalidate()
      let interval = max(timeInterval / 1000, 0.001)
      let shouldRepeat = repeats
      let callback = AnyBox()
      callback.value = self.callback
      timer = Foundation.Timer.scheduledTimer(withTimeInterval: interval, repeats: shouldRepeat) {
        _ in
        MainActor.assumeIsolated {
          (callback.value as? JSValue)?.call(withArguments: [])
        }
      }
    case "invalidate":
      timer?.invalidate()
      timer = nil
    default: break
    }
    return nil
  }
}

final class DateFormatterModel: JSObject {
  var id = 0
  var dateFormat: String?
  var localeIdentifier: String?
  var dateStyle: DateFormatter.Style = .medium
  var timeStyle: DateFormatter.Style = .medium

  private var formatter: DateFormatter {
    let f = DateFormatter()
    if let localeIdentifier { f.locale = Locale(identifier: localeIdentifier) }
    f.dateStyle = dateStyle
    f.timeStyle = timeStyle
    if let dateFormat { f.dateFormat = dateFormat }
    return f
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "dateFormat": return dateFormat
    case "locale": return localeIdentifier
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "dateFormat": dateFormat = runtime.string(value)
    case "locale": localeIdentifier = runtime.string(value)
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "string":
      guard let d = runtime.date(args.first) else { return nil }
      return formatter.string(from: d)
    case "date":
      guard let s = runtime.string(args.first) else { return nil }
      return formatter.date(from: s)
    case "useNoDateStyle": dateStyle = .none
    case "useShortDateStyle": dateStyle = .short
    case "useMediumDateStyle": dateStyle = .medium
    case "useLongDateStyle": dateStyle = .long
    case "useFullDateStyle": dateStyle = .full
    case "useNoTimeStyle": timeStyle = .none
    case "useShortTimeStyle": timeStyle = .short
    case "useMediumTimeStyle": timeStyle = .medium
    case "useLongTimeStyle": timeStyle = .long
    case "useFullTimeStyle": timeStyle = .full
    default: return nil
    }
    return nil
  }
}

final class RelativeDateTimeFormatterModel: JSObject {
  var id = 0
  var localeIdentifier: String?
  var named = true

  private var formatter: RelativeDateTimeFormatter {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = named ? .full : .abbreviated
    f.locale = localeIdentifier.map { Locale(identifier: $0) } ?? .current
    return f
  }

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    name == "locale" ? localeIdentifier : nil
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    if name == "locale" { localeIdentifier = runtime.string(value) }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "string":
      guard let d = runtime.date(args.first) else { return nil }
      let reference = runtime.date(args.count > 1 ? args[1] : nil) ?? Date()
      return formatter.localizedString(for: d, relativeTo: reference)
    case "useNamedDateTimeStyle": named = true
    case "useNumericDateTimeStyle": named = false
    default: return nil
    }
    return nil
  }
}

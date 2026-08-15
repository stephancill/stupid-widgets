import Foundation
import JavaScriptCore
import UIKit
import UserNotifications

final class RequestModel: JSObject {
  var id = 0
  var url: String?
  var method: String = "GET"
  var headers: [String: String] = [:]
  var body: Any?
  var timeoutInterval: Double = 60
  var response: RequestResponseModel?

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "url": return url
    case "method": return method
    case "headers": return headers
    case "body": return body
    case "timeoutInterval": return timeoutInterval
    case "response": return response
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "url": url = runtime.string(value)
    case "method": method = runtime.string(value) ?? method
    case "headers":
      if let js = value as? JSValue, js.isObject {
        headers = (js.toDictionary() ?? [:]).reduce(into: [:]) { $0["\($1.key)"] = "\($1.value)" }
      }
    case "body": body = value
    case "timeoutInterval": timeoutInterval = runtime.double(value) ?? timeoutInterval
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addParameterToMultipart":
      let key = runtime.string(args.first) ?? ""
      let val = runtime.string(args.count > 1 ? args[1] : nil) ?? ""
      multipartFields[key] = val
    case "addFileDataToMultipart", "addFileToMultipart", "addImageToMultipart":
      let key = runtime.string(args.first) ?? ""
      multipartFiles[key] = args.dropFirst().compactMap { runtime.nativeObject($0) }
    default: return nil
    }
    return nil
  }

  private var multipartFields: [String: String] = [:]
  private var multipartFiles: [String: [JSObject]] = [:]

  private func buildRequest() -> URLRequest? {
    guard let urlString = url, let u = URL(string: urlString) else { return nil }
    var req = URLRequest(url: u)
    req.httpMethod = method
    req.timeoutInterval = timeoutInterval
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if !multipartFields.isEmpty || !multipartFiles.isEmpty {
      let boundary = "stupidwidgets-\(UUID().uuidString)"
      req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      var data = Data()
      for (k, v) in multipartFields {
        data.append(
          "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(
            using: .utf8)!)
      }
      for (k, objects) in multipartFiles {
        for obj in objects {
          if let image = (obj as? ImageModel)?.image, let png = image.pngData() {
            data.append(
              "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"; filename=\"\(k).png\"\r\nContent-Type: image/png\r\n\r\n"
                .data(using: .utf8)!)
            data.append(png)
            data.append("\r\n".data(using: .utf8)!)
          } else if let dm = obj as? DataModel {
            data.append(
              "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"; filename=\"\(k).dat\"\r\n\r\n"
                .data(using: .utf8)!)
            data.append(dm.data)
            data.append("\r\n".data(using: .utf8)!)
          }
        }
      }
      data.append("--\(boundary)--\r\n".data(using: .utf8)!)
      req.httpBody = data
    } else if let body {
      if let dm = body as? DataModel {
        req.httpBody = dm.data
      } else if let s = body as? String {
        req.httpBody = s.data(using: .utf8)
      } else if let js = body as? JSValue, let obj = js.toDictionary() {
        req.httpBody = try? JSONSerialization.data(withJSONObject: obj)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }
    return req
  }

  func jsAsync(
    _ runtime: JSRuntime, _ name: String, _ args: [Any], _ resolve: JSValue, _ reject: JSValue
  ) {
    switch name {
    case "load", "loadString", "loadJSON", "loadImage":
      Task { @MainActor in
        guard let req = buildRequest() else {
          reject.call(withArguments: ["invalid URL"])
          return
        }
        do {
          let (data, http) = try await URLSession.shared.data(for: req)
          response =
            runtime.alloc(RequestResponseModel(data: data, response: http as? HTTPURLResponse))
            as? RequestResponseModel
          switch name {
          case "load":
            resolve.call(withArguments: [runtime.toJS(runtime.alloc(DataModel(data: data)))])
          case "loadString":
            resolve.call(withArguments: [String(data: data, encoding: .utf8) ?? ""])
          case "loadJSON":
            do {
              resolve.call(withArguments: [try JSONSerialization.jsonObject(with: data)])
            } catch {
              reject.call(withArguments: [error.localizedDescription])
            }
          case "loadImage":
            if let image = UIImage(data: data) {
              resolve.call(withArguments: [runtime.toJS(runtime.alloc(ImageModel(image: image)))])
            } else {
              reject.call(withArguments: ["not an image"])
            }
          default: break
          }
        } catch {
          reject.call(withArguments: [error.localizedDescription])
        }
      }
    default: reject.call(withArguments: ["unknown async method \(name)"])
    }
  }
}

final class RequestResponseModel: JSObject {
  var id = 0
  let statusCode: Int
  let headers: [String: String]
  init(data: Data, response: HTTPURLResponse?) {
    statusCode = response?.statusCode ?? 0
    headers = (response?.allHeaderFields ?? [:]).reduce(into: [:]) {
      $0["\($1.key)"] = "\($1.value)"
    }
  }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "statusCode": return statusCode
    case "headers": return headers
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

final class NotificationModel: JSObject {
  var id = 0
  var identifier: String = ""
  var title: String?
  var subtitle: String?
  var body: String?
  var badge: Int = 0
  var threadIdentifier: String?
  var userInfo: [String: Any] = [:]
  var sound: String?
  var openURL: String?
  var deliveryDate: Date?
  var scriptName: String?
  var actions: [NotificationActionModel] = []

  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "identifier": return identifier
    case "title": return title
    case "subtitle": return subtitle
    case "body": return body
    case "badge": return badge
    case "threadIdentifier": return threadIdentifier
    case "userInfo": return userInfo
    case "sound": return sound
    case "openURL": return openURL
    case "deliveryDate": return deliveryDate
    case "scriptName": return scriptName
    case "actions": return actions.map { runtime.toJS($0) }
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {
    switch name {
    case "identifier": identifier = runtime.string(value) ?? identifier
    case "title": title = runtime.string(value)
    case "subtitle": subtitle = runtime.string(value)
    case "body": body = runtime.string(value)
    case "badge": badge = runtime.double(value).map { Int($0) } ?? badge
    case "threadIdentifier": threadIdentifier = runtime.string(value)
    case "userInfo":
      if let js = value as? JSValue, let dict = js.toDictionary() {
        userInfo = dict.reduce(into: [String: Any]()) { $0["\($1.key)"] = $1.value }
      }
    case "sound": sound = runtime.string(value)
    case "openURL": openURL = runtime.string(value)
    case "deliveryDate": deliveryDate = runtime.date(value)
    case "scriptName": scriptName = runtime.string(value)
    default: break
    }
  }
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? {
    switch name {
    case "addAction":
      let title = runtime.string(args.first) ?? ""
      let url = runtime.string(args.count > 1 ? args[1] : nil)
      let destructive = runtime.bool(args.count > 2 ? args[2] : nil) ?? false
      actions.append(
        runtime.alloc(NotificationActionModel(title: title, url: url, destructive: destructive))
          as! NotificationActionModel)
    case "schedule":
      schedule(runtime)
    case "remove":
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
    default: return nil
    }
    return nil
  }

  private func schedule(_ runtime: JSRuntime) {
    let content = UNMutableNotificationContent()
    content.title = title ?? ""
    content.subtitle = subtitle ?? ""
    content.body = body ?? ""
    content.badge = badge > 0 ? NSNumber(value: badge) : nil
    if let threadIdentifier { content.threadIdentifier = threadIdentifier }
    content.userInfo = userInfo
    if let sound {
      content.sound =
        sound == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(sound))
    }
    content.categoryIdentifier = "net.stupidtech.stupidwidgets.notification"
    let trigger: UNNotificationTrigger
    if let deliveryDate {
      let comps = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: deliveryDate)
      trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    } else {
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    }
    let request = UNNotificationRequest(
      identifier: identifier.isEmpty ? UUID().uuidString : identifier, content: content,
      trigger: trigger)
    UNUserNotificationCenter.current().add(request)
  }
}

final class NotificationActionModel: JSObject {
  var id = 0
  let title: String
  let url: String?
  let destructive: Bool
  init(title: String, url: String?, destructive: Bool) {
    self.title = title
    self.url = url
    self.destructive = destructive
  }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? {
    switch name {
    case "title": return title
    case "url": return url
    case "destructive": return destructive
    default: return nil
    }
  }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

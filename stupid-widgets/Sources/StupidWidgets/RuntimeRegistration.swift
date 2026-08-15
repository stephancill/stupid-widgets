import Foundation
import JavaScriptCore
import Security
import UIKit
import UserNotifications

final class PathModel: JSObject {
  var id = 0
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any? { nil }
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?) {}
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any? { nil }
}

@MainActor
extension JSRuntime {

  // MARK: - Full install

  func installScriptableAPI(scriptName: String) {
    installValueClasses()
    installWidgetClasses()
    installSystemClasses()
    installNetworkClasses()
    installUIClasses()
    installGlobals(scriptName: scriptName)
  }

  // MARK: - Value classes

  private func installValueClasses() {
    register(
      JSClassSpec(
        name: "Color", instanceProps: ["hex", "red", "green", "blue", "alpha"],
        staticMethods: [
          "red", "green", "blue", "white", "black", "gray", "darkGray", "lightGray",
          "cyan", "yellow", "magenta", "orange", "purple", "brown", "clear", "dynamic",
        ]
      ) { runtime, args in
        if let s = runtime.string(args.first), let c = ColorModel(hexString: s) {
          return c
        }
        let r = runtime.double(args.count > 0 ? args[0] : nil) ?? 0
        let g = runtime.double(args.count > 1 ? args[1] : nil) ?? 0
        let b = runtime.double(args.count > 2 ? args[2] : nil) ?? 0
        let a = runtime.double(args.count > 3 ? args[3] : nil) ?? 1
        return ColorModel(red: r, green: g, blue: b, alpha: a)
      })
    registerStaticCallsForColor()

    let fontSpec = JSClassSpec(
      name: "Font", instanceProps: ["name", "size"], staticMethods: FontModel.allStaticFontNames
    ) { runtime, args in
      let name = runtime.string(args.first)
      let size = CGFloat(runtime.double(args.count > 1 ? args[1] : nil) ?? 17)
      return FontModel(
        font: name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size))
    }
    register(fontSpec)
    registerStaticCallsForFont()

    register(
      JSClassSpec(name: "Point", instanceProps: ["x", "y"]) { _, args in
        PointModel(x: .from(args, 0), y: .from(args, 1))
      })
    register(
      JSClassSpec(name: "Size", instanceProps: ["width", "height"]) { _, args in
        SizeModel(width: .from(args, 0), height: .from(args, 1))
      })
    register(
      JSClassSpec(
        name: "Rect", instanceProps: ["x", "y", "width", "height", "minX", "minY", "maxX", "maxY"]
      ) { _, args in
        RectModel(
          x: .from(args, 0), y: .from(args, 1), width: .from(args, 2), height: .from(args, 3))
      })

    register(
      JSClassSpec(name: "Image", instanceProps: ["size"], staticMethods: ["fromFile", "fromData"]) {
        _, _ in
        ImageModel(image: nil)
      })
    registerStaticCall(type: "Image", name: "fromFile") { runtime, args in
      guard let p = runtime.string(args.first), let img = UIImage(contentsOfFile: p) else {
        return nil
      }
      return runtime.alloc(ImageModel(image: img))
    }
    registerStaticCall(type: "Image", name: "fromData") { runtime, args in
      guard let data = runtime.nativeObject(args.first) as? DataModel else { return nil }
      return runtime.alloc(ImageModel(image: UIImage(data: data.data)))
    }

    register(
      JSClassSpec(
        name: "Data", instanceMethods: ["toRawString", "toBase64String", "getBytes"],
        staticMethods: [
          "fromString", "fromBase64String", "fromFile", "fromBytes", "fromJPEG", "fromPNG",
        ]
      ) { _, _ in
        DataModel(data: Data())
      })
    registerStaticCall(type: "Data", name: "fromString") { runtime, args in
      return runtime.alloc(
        DataModel(data: runtime.string(args.first)?.data(using: .utf8) ?? Data()))
    }
    registerStaticCall(type: "Data", name: "fromBase64String") { runtime, args in
      let b64 = runtime.string(args.first) ?? ""
      return runtime.alloc(DataModel(data: Data(base64Encoded: b64) ?? Data()))
    }
    registerStaticCall(type: "Data", name: "fromFile") { runtime, args in
      guard let p = runtime.string(args.first), let d = FileManager.default.contents(atPath: p)
      else { return nil }
      return runtime.alloc(DataModel(data: d))
    }
    registerStaticCall(type: "Data", name: "fromBytes") { runtime, args in
      let bytes = (runtime.jsArray(args.first) ?? []).compactMap {
        runtime.double($0).map { UInt8($0) }
      }
      return runtime.alloc(DataModel(data: Data(bytes)))
    }
    registerStaticCall(type: "Data", name: "fromJPEG") { runtime, args in
      guard let img = runtime.nativeObject(args.first) as? ImageModel, let img = img.image,
        let d = img.jpegData(compressionQuality: 1)
      else { return nil }
      return runtime.alloc(DataModel(data: d))
    }
    registerStaticCall(type: "Data", name: "fromPNG") { runtime, args in
      guard let img = runtime.nativeObject(args.first) as? ImageModel, let img = img.image,
        let d = img.pngData()
      else { return nil }
      return runtime.alloc(DataModel(data: d))
    }
  }

  private func registerStaticCallsForColor() {
    let named: [String: (Double, Double, Double, Double)] = [
      "red": (1, 0.231, 0.188, 1), "green": (0.298, 0.851, 0.392, 1),
      "blue": (0, 0.478, 1, 1), "white": (1, 1, 1, 1), "black": (0, 0, 0, 1),
      "gray": (0.556, 0.557, 0.577, 1), "darkGray": (0.329, 0.329, 0.345, 1),
      "lightGray": (0.777, 0.777, 0.784, 1), "cyan": (0.341, 0.902, 1, 1),
      "yellow": (1, 0.921, 0.231, 1), "magenta": (1, 0, 0.478, 1),
      "orange": (1, 0.584, 0, 1), "purple": (0.685, 0.321, 0.871, 1),
      "brown": (0.615, 0.507, 0.367, 1), "clear": (0, 0, 0, 0),
      "dynamic": (0.556, 0.557, 0.577, 1),
    ]
    for (name, c) in named {
      registerStaticCall(type: "Color", name: name) { runtime, _ in
        return runtime.alloc(ColorModel(red: c.0, green: c.1, blue: c.2, alpha: c.3))
      }
    }
  }

  private func registerStaticCallsForFont() {
    let weights: [String: UIFont.Weight] = [
      "ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular,
      "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy,
      "black": .black,
    ]
    let all = FontModel.allStaticFontNames
    for name in all {
      registerStaticCall(type: "Font", name: name) { runtime, args in
        let size = CGFloat(runtime.double(args.first) ?? 17)
        var font = UIFont.systemFont(ofSize: size)
        for (label, weight) in weights where name.hasPrefix(label) {
          font = .systemFont(ofSize: size, weight: weight)
          break
        }
        if name == "italicSystemFont" {
          font = UIFont.italicSystemFont(ofSize: size)
        } else if name.hasPrefix("monospaced") {
          let weight = weights.first { name.hasPrefix($0.key) }?.value ?? .regular
          font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        return runtime.alloc(FontModel(font: font))
      }
    }
  }

  // MARK: - Widget classes

  private func installWidgetClasses() {
    register(
      JSClassSpec(
        name: "ListWidget",
        instanceProps: [
          "backgroundColor", "backgroundImage", "backgroundGradient", "spacing", "url",
          "refreshAfterDate",
        ],
        instanceMethods: [
          "addText", "addDate", "addImage", "addSpacer", "addStack", "setPadding",
          "useDefaultPadding",
          "presentSmall", "presentMedium", "presentLarge", "presentExtraLarge",
          "presentAccessoryInline", "presentAccessoryCircular", "presentAccessoryRectangular",
        ]
      ) { _, _ in ListWidgetModel() })

    register(
      JSClassSpec(
        name: "WidgetStack",
        instanceProps: [
          "backgroundColor", "backgroundImage", "backgroundGradient", "spacing", "size",
          "cornerRadius", "borderWidth", "borderColor", "url",
        ],
        instanceMethods: [
          "addText", "addDate", "addImage", "addSpacer", "addStack", "setPadding",
          "useDefaultPadding",
          "layoutHorizontally", "layoutVertically", "topAlignContent", "centerAlignContent",
          "bottomAlignContent",
        ]
      ) { _, _ in WidgetStackModel() })

    register(
      JSClassSpec(
        name: "WidgetText",
        instanceProps: [
          "text", "textColor", "font", "textOpacity", "lineLimit", "minimumScaleFactor",
          "shadowColor", "shadowRadius", "shadowOffset", "url",
        ],
        instanceMethods: ["leftAlignText", "centerAlignText", "rightAlignText"]
      ) { _, _ in WidgetTextModel(text: "") })

    register(
      JSClassSpec(
        name: "WidgetDate",
        instanceProps: [
          "date", "textColor", "font", "textOpacity", "lineLimit", "minimumScaleFactor", "url",
        ],
        instanceMethods: [
          "applyTimeStyle", "applyDateStyle", "applyRelativeStyle", "applyOffsetStyle",
          "applyTimerStyle",
          "leftAlignText", "centerAlignText", "rightAlignText",
        ]
      ) { _, _ in WidgetDateModel(date: Date()) })

    register(
      JSClassSpec(
        name: "WidgetImage",
        instanceProps: [
          "image", "resizable", "imageSize", "imageOpacity", "cornerRadius", "borderWidth",
          "borderColor", "tintColor", "url",
        ],
        instanceMethods: [
          "applyFittingContentMode", "applyFillingContentMode", "leftAlignImage",
          "centerAlignImage", "rightAlignImage",
        ]
      ) { _, _ in WidgetImageModel() })

    register(
      JSClassSpec(name: "WidgetSpacer", instanceProps: ["length"]) { _, _ in WidgetSpacerModel() })

    register(
      JSClassSpec(
        name: "LinearGradient", instanceProps: ["colors", "locations", "startPoint", "endPoint"]
      ) { _, _ in
        LinearGradientModel()
      })
  }

  // MARK: - System classes

  private func installSystemClasses() {
    register(
      JSClassSpec(
        name: "Device",
        staticMethods: [
          "name", "systemName", "systemVersion", "model", "isPhone", "isPad",
          "screenSize", "screenResolution", "screenScale", "isUsingDarkAppearance",
          "preferredLanguages", "locale", "language", "batteryLevel", "isCharging",
          "isFullyCharged", "isDischarging", "isInPortrait", "isInLandscapeLeft",
          "isInLandscapeRight", "isFaceUp", "isFaceDown", "setScreenBrightness",
        ]
      ) { _, _ in StaticOnlyObject() })
    registerStaticCallsForDevice()

    register(
      JSClassSpec(name: "SFSymbol", instanceProps: ["image"], staticMethods: ["named"]) { _, _ in
        SFSymbolModel(symbolName: "")
      })
    registerStaticCall(type: "SFSymbol", name: "named") { runtime, args in
      return runtime.alloc(SFSymbolModel(symbolName: runtime.string(args.first) ?? ""))
    }

    register(
      JSClassSpec(name: "Keychain", staticMethods: ["set", "get", "remove", "contains"]) { _, _ in
        StaticOnlyObject()
      })
    registerStaticCallsForKeychain()

    register(
      JSClassSpec(
        name: "Pasteboard", staticMethods: ["copyString", "pasteString", "copy", "paste"]
      ) { _, _ in StaticOnlyObject() })
    registerStaticCallsForPasteboard()

    register(JSClassSpec(name: "UUID", staticMethods: ["string"]) { _, _ in StaticOnlyObject() })
    registerStaticCall(type: "UUID", name: "string") { _, _ in UUID().uuidString }

    register(
      JSClassSpec(
        name: "FileManager",
        instanceMethods: [
          "documentsDirectory", "libraryDirectory", "temporaryDirectory", "cacheDirectory",
          "allFileBookmarks",
          "read", "readString", "readImage", "write", "writeString", "writeImage", "remove", "move",
          "copy",
          "fileExists", "isDirectory", "createDirectory", "joinPath", "listContents", "fileName",
          "fileExtension",
          "fileSize", "creationDate", "modificationDate", "bookmarkedPath", "bookmarkExists",
          "downloadFileFromiCloud", "isFileStoredIniCloud", "isFileDownloaded",
        ], staticMethods: ["local", "iCloud"]
      ) { _, _ in
        FileManagerModel(isICloud: false)
      })
    registerStaticCall(type: "FileManager", name: "local") { runtime, _ in
      return runtime.alloc(FileManagerModel(isICloud: false))
    }
    registerStaticCall(type: "FileManager", name: "iCloud") { runtime, _ in
      return runtime.alloc(FileManagerModel(isICloud: true))
    }

    register(
      JSClassSpec(
        name: "Timer", instanceProps: ["timeInterval", "repeats"],
        instanceMethods: ["schedule", "invalidate"]
      ) { _, _ in
        TimerModel()
      })

    register(
      JSClassSpec(
        name: "DateFormatter", instanceProps: ["dateFormat", "locale"],
        instanceMethods: [
          "string", "date", "useNoDateStyle", "useShortDateStyle", "useMediumDateStyle",
          "useLongDateStyle",
          "useFullDateStyle", "useNoTimeStyle", "useShortTimeStyle", "useMediumTimeStyle",
          "useLongTimeStyle", "useFullTimeStyle",
        ]
      ) { _, _ in DateFormatterModel() })

    register(
      JSClassSpec(
        name: "RelativeDateTimeFormatter", instanceProps: ["locale"],
        instanceMethods: ["string", "useNamedDateTimeStyle", "useNumericDateTimeStyle"]
      ) { _, _ in
        RelativeDateTimeFormatterModel()
      })

    register(
      JSClassSpec(
        name: "Path",
        instanceMethods: [
          "move", "addLine", "addRect", "addEllipse", "addRoundedRect", "addCurve", "addQuadCurve",
          "addLines", "addRects", "closeSubpath",
        ]
      ) { _, _ in PathModel() })
  }

  private func registerStaticCallsForDevice() {
    registerStaticCall(type: "Device", name: "name") { _, _ in UIDevice.current.name }
    registerStaticCall(type: "Device", name: "systemName") { _, _ in UIDevice.current.systemName }
    registerStaticCall(type: "Device", name: "systemVersion") { _, _ in
      UIDevice.current.systemVersion
    }
    registerStaticCall(type: "Device", name: "model") { _, _ in UIDevice.current.model }
    registerStaticCall(type: "Device", name: "isPhone") { _, _ in
      UIDevice.current.userInterfaceIdiom == .phone
    }
    registerStaticCall(type: "Device", name: "isPad") { _, _ in
      UIDevice.current.userInterfaceIdiom == .pad
    }
    registerStaticCall(type: "Device", name: "screenSize") { runtime, _ in
      return runtime.alloc(
        SizeModel(
          width: Double(UIScreen.main.bounds.width), height: Double(UIScreen.main.bounds.height)))
    }
    registerStaticCall(type: "Device", name: "screenResolution") { runtime, _ in
      let s = UIScreen.main.scale
      return runtime.alloc(
        SizeModel(
          width: Double(UIScreen.main.bounds.width * s),
          height: Double(UIScreen.main.bounds.height * s)))
    }
    registerStaticCall(type: "Device", name: "screenScale") { _, _ in Double(UIScreen.main.scale) }
    registerStaticCall(type: "Device", name: "isUsingDarkAppearance") { _, _ in
      UITraitCollection.current.userInterfaceStyle == .dark
    }
    registerStaticCall(type: "Device", name: "preferredLanguages") { _, _ in
      Locale.preferredLanguages
    }
    registerStaticCall(type: "Device", name: "locale") { _, _ in Locale.current.identifier }
    registerStaticCall(type: "Device", name: "language") { _, _ in Locale.preferredLanguages.first }
    registerStaticCall(type: "Device", name: "batteryLevel") { _, _ in
      Double(UIDevice.current.batteryLevel)
    }
    registerStaticCall(type: "Device", name: "isCharging") { _, _ in
      UIDevice.current.batteryState == .charging
    }
    registerStaticCall(type: "Device", name: "isFullyCharged") { _, _ in
      UIDevice.current.batteryState == .full
    }
    registerStaticCall(type: "Device", name: "isDischarging") { _, _ in
      UIDevice.current.batteryState == .unplugged
    }
    registerStaticCall(type: "Device", name: "isInPortrait") { _, _ in
      UIDevice.current.orientation == .portrait
    }
    registerStaticCall(type: "Device", name: "isInLandscapeLeft") { _, _ in
      UIDevice.current.orientation == .landscapeLeft
    }
    registerStaticCall(type: "Device", name: "isInLandscapeRight") { _, _ in
      UIDevice.current.orientation == .landscapeRight
    }
    registerStaticCall(type: "Device", name: "isFaceUp") { _, _ in
      UIDevice.current.orientation == .faceUp
    }
    registerStaticCall(type: "Device", name: "isFaceDown") { _, _ in
      UIDevice.current.orientation == .faceDown
    }
    registerStaticCall(type: "Device", name: "setScreenBrightness") { _, _ in nil }
  }

  private func registerStaticCallsForKeychain() {
    let service = "net.stupidtech.stupidwidgets.scripts"
    registerStaticCall(type: "Keychain", name: "set") { _, args in
      guard let key = args.first as? String, let value = args.count > 1 ? args[1] as? String : nil
      else { return nil }
      #if targetEnvironment(simulator)
        UserDefaults.standard.set(value, forKey: "\(service).\(key)")
      #else
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: service,
          kSecAttrAccount as String: key,
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(
          query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var item = query
          item[kSecValueData as String] = data
          item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          SecItemAdd(item as CFDictionary, nil)
        }
      #endif
      return nil
    }
    registerStaticCall(type: "Keychain", name: "get") { _, args in
      guard let key = args.first as? String else { return nil }
      #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: "\(service).\(key)")
      #else
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: service,
          kSecAttrAccount as String: key,
          kSecReturnData as String: true,
          kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
      #endif
    }
    registerStaticCall(type: "Keychain", name: "contains") { _, args in
      guard let key = args.first as? String else { return false }
      #if targetEnvironment(simulator)
        return UserDefaults.standard.object(forKey: "\(service).\(key)") != nil
      #else
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: service,
          kSecAttrAccount as String: key,
          kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
      #endif
    }
    registerStaticCall(type: "Keychain", name: "remove") { _, args in
      guard let key = args.first as? String else { return nil }
      #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: "\(service).\(key)")
      #else
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: service,
          kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
      #endif
      return nil
    }
  }

  private func registerStaticCallsForPasteboard() {
    registerStaticCall(type: "Pasteboard", name: "copyString") { _, args in
      guard let s = args.first as? String else { return nil }
      UIPasteboard.general.string = s
      return nil
    }
    registerStaticCall(type: "Pasteboard", name: "pasteString") { _, _ in
      UIPasteboard.general.string
    }
    registerStaticCall(type: "Pasteboard", name: "copy") { _, args in
      guard let obj = args.first as? JSValue else { return nil }
      if let s = obj.toString() { UIPasteboard.general.string = s }
      return nil
    }
    registerStaticCall(type: "Pasteboard", name: "paste") { runtime, _ in
      return runtime.alloc(
        DataModel(data: UIPasteboard.general.data(forPasteboardType: "public.data") ?? Data()))
    }
  }

  // MARK: - Network classes

  private func installNetworkClasses() {
    register(
      JSClassSpec(
        name: "Request",
        instanceProps: ["url", "method", "headers", "body", "timeoutInterval", "response"],
        instanceMethods: [
          "addParameterToMultipart", "addFileDataToMultipart", "addFileToMultipart",
          "addImageToMultipart",
        ],
        asyncInstanceMethods: ["load", "loadString", "loadJSON", "loadImage"]
      ) { runtime, args in
        let request = RequestModel()
        request.url = runtime.string(args.first)
        return request
      })

    register(
      JSClassSpec(
        name: "RequestResponse",
        instanceProps: ["statusCode", "headers"]
      ) { _, _ in RequestResponseModel(data: Data(), response: nil) })

    register(
      JSClassSpec(
        name: "Notification",
        instanceProps: [
          "identifier", "title", "subtitle", "body", "badge", "threadIdentifier", "userInfo",
          "sound", "openURL", "deliveryDate", "scriptName", "actions",
        ],
        instanceMethods: ["addAction", "remove"],
        asyncInstanceMethods: ["schedule"],
        staticProps: ["current"],
        staticMethods: [
          "allPending", "allDelivered", "removeAllPending", "removeAllDelivered", "removePending",
          "removeDelivered", "resetCurrent",
        ]
      ) { _, _ in NotificationModel() })
    registerStaticCallsForNotification()

    register(
      JSClassSpec(name: "NotificationAction", instanceProps: ["title", "url", "destructive"]) {
        _, _ in
        NotificationActionModel(title: "", url: nil, destructive: false)
      })
  }

  private func registerStaticCallsForNotification() {
    registerStaticCall(type: "Notification", name: "allPending") { _, _ in [] }
    registerStaticCall(type: "Notification", name: "allDelivered") { _, _ in [] }
    registerStaticCall(type: "Notification", name: "removeAllPending") { _, _ in
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      return nil
    }
    registerStaticCall(type: "Notification", name: "removeAllDelivered") { _, _ in
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      return nil
    }
    registerStaticCall(type: "Notification", name: "removePending") { _, args in
      if let id = args.first as? String {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
      }
      return nil
    }
    registerStaticCall(type: "Notification", name: "removeDelivered") { _, args in
      if let id = args.first as? String {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
      }
      return nil
    }
    registerStaticCall(type: "Notification", name: "resetCurrent") { _, _ in nil }
  }

  // MARK: - UI classes

  private func installUIClasses() {
    register(
      JSClassSpec(
        name: "Alert", instanceProps: ["title", "message"],
        instanceMethods: [
          "addAction", "addCancelAction", "addDestructiveAction", "addTextField",
          "addSecureTextField",
        ], asyncInstanceMethods: ["present", "presentAlert", "presentSheet"]
      ) { _, _ in AlertModel() })

    register(
      JSClassSpec(
        name: "UITable", instanceProps: ["showSeparators"],
        instanceMethods: ["addRow", "removeRow", "removeAllRows", "reload"],
        asyncInstanceMethods: ["present"]
      ) { _, _ in
        UITableModel()
      })
    register(
      JSClassSpec(
        name: "UITableRow",
        instanceProps: ["height", "cellSpacing", "isHeader", "dismissOnSelect", "onSelect"],
        instanceMethods: ["addCell", "addText", "addImage", "addImageAtURL", "addButton"]
      ) { _, _ in
        UITableRowModel()
      })
    register(
      JSClassSpec(
        name: "UITableCell",
        instanceProps: ["widthWeight", "onTap", "dismissOnTap", "titleColor", "titleFont"],
        instanceMethods: [
          "text", "image", "imageAtURL", "button", "leftAligned", "centerAligned", "rightAligned",
        ]
      ) { _, _ in
        UITableCellModel(kind: .text)
      })

    register(
      JSClassSpec(name: "QuickLook", asyncStaticMethods: ["present"]) { _, _ in StaticOnlyObject() }
    )
    registerStaticAsync(type: "QuickLook", name: "present") {
      [weak self] runtime, args, resolve, _ in
      guard let self else { return }
      guard let obj = args.first else {
        resolve.call(withArguments: [NSNull()])
        return
      }
      if let widget = self.nativeObject(obj) as? ListWidgetModel {
        self.activePreview = PreviewRequest(
          kind: .widget, family: widget.previewFamily, widget: widget)
      } else if let table = self.nativeObject(obj) as? UITableModel {
        table.pendingResolve = resolve
        self.activeTable = table
        return
      } else if let text = self.string(obj) {
        self.activePreview = PreviewRequest(kind: .text, text: text)
      } else if let image = self.nativeObject(obj) as? ImageModel {
        self.activePreview = PreviewRequest(kind: .image, image: image)
      }
      resolve.call(withArguments: [NSNull()])
    }

    register(
      JSClassSpec(name: "Safari", staticMethods: ["open", "openInApp"]) { _, _ in StaticOnlyObject()
      })
    registerStaticCall(type: "Safari", name: "open") { _, args in
      if let urlString = args.first as? String, let url = URL(string: urlString) {
        UIApplication.shared.open(url)
      }
      return nil
    }
    registerStaticCall(type: "Safari", name: "openInApp") { _, args in
      if let urlString = args.first as? String, let url = URL(string: urlString) {
        UIApplication.shared.open(url)
      }
      return nil
    }
  }

  // MARK: - Globals

  private func installGlobals(scriptName: String) {
    // config
    let config = context.evaluateScript("({})")!
    config.setObject(true, forKeyedSubscript: "runsInApp" as NSString)
    config.setObject(false, forKeyedSubscript: "runsInWidget" as NSString)
    config.setObject(false, forKeyedSubscript: "runsWithSiri" as NSString)
    config.setObject("medium", forKeyedSubscript: "widgetFamily" as NSString)
    config.setObject(NSNull(), forKeyedSubscript: "widget" as NSString)
    context.setObject(config, forKeyedSubscript: "config" as NSString)

    // args
    let args = context.evaluateScript("({})")!
    args.setObject(NSNull(), forKeyedSubscript: "shortcutParameter" as NSString)
    args.setObject([], forKeyedSubscript: "plainTexts" as NSString)
    args.setObject([], forKeyedSubscript: "images" as NSString)
    args.setObject([], forKeyedSubscript: "urls" as NSString)
    args.setObject([], forKeyedSubscript: "fileURLs" as NSString)
    args.setObject(NSNull(), forKeyedSubscript: "notification" as NSString)
    args.setObject([:], forKeyedSubscript: "queryParameters" as NSString)
    args.setObject(NSNull(), forKeyedSubscript: "widgetParameter" as NSString)
    context.setObject(args, forKeyedSubscript: "args" as NSString)

    // module
    let module = context.evaluateScript("({})")!
    module.setObject(scriptName, forKeyedSubscript: "filename" as NSString)
    module.setObject([], forKeyedSubscript: "list" as NSString)
    module.setObject(scriptName, forKeyedSubscript: "moduleName" as NSString)
    module.setObject([], forKeyedSubscript: "dependencies" as NSString)
    module.setObject(context.evaluateScript("({})"), forKeyedSubscript: "exports" as NSString)
    context.setObject(module, forKeyedSubscript: "module" as NSString)
    rootModule = module

    // console
    let log: @convention(block) ([Any]) -> Void = { [weak self] args in
      self?.consoleLines.append(args.map { "\($0)" }.joined(separator: " "))
    }
    let error: @convention(block) ([Any]) -> Void = { [weak self] args in
      self?.consoleLines.append("Error: " + args.map { "\($0)" }.joined(separator: " "))
    }
    context.setObject(log, forKeyedSubscript: "__stupidWidgets_consoleLog" as NSString)
    context.setObject(error, forKeyedSubscript: "__stupidWidgets_consoleError" as NSString)
    let console = context.evaluateScript(
      """
      ({
        log: function() { __stupidWidgets_consoleLog(Array.prototype.slice.call(arguments)) },
        warn: function() { __stupidWidgets_consoleLog(Array.prototype.slice.call(arguments)) },
        debug: function() { __stupidWidgets_consoleLog(Array.prototype.slice.call(arguments)) },
        error: function() { __stupidWidgets_consoleError(Array.prototype.slice.call(arguments)) },
        logError: function() { __stupidWidgets_consoleError(Array.prototype.slice.call(arguments)) }
      })
      """)!
    context.setObject(console, forKeyedSubscript: "console" as NSString)

    // Script
    let script = context.evaluateScript("({})")!
    let name: @convention(block) () -> String = { scriptName }
    let setWidget: @convention(block) (JSValue) -> Void = { [weak self] widget in
      guard let self, let model = self.nativeObject(widget) as? ListWidgetModel else { return }
      self.scriptWidget = model
    }
    let complete: @convention(block) () -> Void = { [weak self] in
      guard let self else { return }
      self.completed = true
      self.presentScriptWidgetIfNeeded()
    }
    let setShortcutOutput: @convention(block) (JSValue) -> Void = { [weak self] value in
      guard let self else { return }
      let text = value.toString() ?? ""
      self.shortcutOutput = text
      self.consoleLines.append("Shortcut output: \(text)")
    }
    script.setObject(name, forKeyedSubscript: "name" as NSString)
    script.setObject(setWidget, forKeyedSubscript: "setWidget" as NSString)
    script.setObject(complete, forKeyedSubscript: "complete" as NSString)
    script.setObject(setShortcutOutput, forKeyedSubscript: "setShortcutOutput" as NSString)
    context.setObject(script, forKeyedSubscript: "Script" as NSString)

    // importModule
    let importModule: @convention(block) (String) -> JSValue? = { [weak self] name in
      guard let self else { return nil }
      return self.importModule(named: name)
    }
    context.setObject(importModule, forKeyedSubscript: "importModule" as NSString)
  }

  func importModule(named name: String) -> JSValue? {
    guard let url = resolveModule(named: name) else {
      context.exception = JSValue(newErrorFromMessage: "Cannot find module '\(name)'", in: context)
      return nil
    }

    recordDependency(url: url)
    let cacheKey = url.standardizedFileURL.path
    if let cached = moduleCache[cacheKey] { return cached }

    let source: String
    do {
      if url.pathExtension.lowercased() == "scriptable" {
        source = try Script.fromFile(url).source
      } else {
        source = try String(contentsOf: url, encoding: .utf8)
      }
    } catch {
      context.exception = JSValue(
        newErrorFromMessage: "Cannot load module '\(name)': \(error.localizedDescription)",
        in: context
      )
      return nil
    }

    let module = context.evaluateScript("({ exports: {}, dependencies: [], list: [] })")!
    module.setObject(url.path, forKeyedSubscript: "filename" as NSString)
    module.setObject(
      url.deletingPathExtension().lastPathComponent,
      forKeyedSubscript: "moduleName" as NSString
    )
    let initialExports = module.objectForKeyedSubscript("exports")!
    moduleCache[cacheKey] = initialExports
    moduleStack.append((url, module))
    defer { moduleStack.removeLast() }

    lastException = nil
    context.exception = nil
    let wrapper = context.evaluateScript(
      "(function(module, exports) {\n\(source)\n; return module.exports;\n})",
      withSourceURL: url
    )
    guard let wrapper, !wrapper.isUndefined, lastException == nil else {
      moduleCache.removeValue(forKey: cacheKey)
      return nil
    }
    lastException = nil
    guard let exports = wrapper.call(withArguments: [module, initialExports]), lastException == nil
    else {
      moduleCache.removeValue(forKey: cacheKey)
      return nil
    }
    moduleCache[cacheKey] = exports
    return exports
  }

  private func resolveModule(named name: String) -> URL? {
    let requested = URL(fileURLWithPath: name)
    var bases: [URL] = []
    if name.hasPrefix("/") {
      bases.append(requested)
      let relativeName = String(name.drop { $0 == "/" })
      bases.append(
        contentsOf: moduleSearchDirectories.map { $0.appendingPathComponent(relativeName) })
    } else {
      if let importerDirectory = moduleStack.last?.url.deletingLastPathComponent() {
        bases.append(importerDirectory.appendingPathComponent(name))
      }
      bases.append(contentsOf: moduleSearchDirectories.map { $0.appendingPathComponent(name) })
    }

    var candidates: [URL] = []
    for base in bases {
      if !base.pathExtension.isEmpty {
        candidates.append(base)
      } else {
        candidates.append(base)
        candidates.append(base.appendingPathExtension("js"))
        candidates.append(base.appendingPathExtension("scriptable"))
      }
      candidates.append(base.appendingPathComponent("index.js"))
      candidates.append(base.appendingPathComponent("index.scriptable"))
    }
    return candidates.first { url in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(
        atPath: url.standardizedFileURL.path,
        isDirectory: &isDirectory
      ) && !isDirectory.boolValue
    }?.standardizedFileURL
  }

  private func recordDependency(url: URL) {
    let owner = moduleStack.last?.module ?? rootModule
    owner?.objectForKeyedSubscript("dependencies")?.invokeMethod("push", withArguments: [url.path])
  }
}

extension Double {
  static func from(_ args: [Any], _ index: Int) -> Double {
    guard args.count > index else { return 0 }
    if let n = args[index] as? NSNumber { return n.doubleValue }
    if let s = args[index] as? String { return Double(s) ?? 0 }
    return 0
  }
}

extension FontModel {
  static let allStaticFontNames: [String] = [
    "systemFont", "ultraLightSystemFont", "thinSystemFont", "lightSystemFont",
    "regularSystemFont", "mediumSystemFont", "semiboldSystemFont", "boldSystemFont",
    "heavySystemFont", "blackSystemFont", "italicSystemFont",
    "ultraLightMonospacedSystemFont", "thinMonospacedSystemFont", "lightMonospacedSystemFont",
    "regularMonospacedSystemFont", "mediumMonospacedSystemFont", "semiboldMonospacedSystemFont",
    "boldMonospacedSystemFont", "heavyMonospacedSystemFont", "blackMonospacedSystemFont",
  ]
}

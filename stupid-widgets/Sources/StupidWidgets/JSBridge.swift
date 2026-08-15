import Foundation
import JavaScriptCore
import UIKit

/// Boxes a non-Sendable value so it can be produced inside `MainActor.assumeIsolated`
/// and returned from a `@convention(block)` closure.
final class AnyBox: @unchecked Sendable {
  var value: Any?
}

// A native Swift object exposed to JavaScript. Each instance is referenced by
// an integer id held in the JS wrapper (`__id`) and resolved through the runtime.
@MainActor
protocol JSObject: AnyObject {
  var id: Int { get set }
  func jsGet(_ runtime: JSRuntime, _ name: String) -> Any?
  func jsSet(_ runtime: JSRuntime, _ name: String, _ value: Any?)
  func jsCall(_ runtime: JSRuntime, _ name: String, _ args: [Any]) -> Any?
  func jsAsync(
    _ runtime: JSRuntime, _ name: String, _ args: [Any], _ resolve: JSValue, _ reject: JSValue)
}

extension JSObject {
  func jsAsync(
    _ runtime: JSRuntime, _ name: String, _ args: [Any], _ resolve: JSValue, _ reject: JSValue
  ) {
    let result = jsCall(runtime, name, args)
    if let result, let error = result as? String, error.hasPrefix("__error:") {
      reject.call(withArguments: [String(error.dropFirst(8))])
    } else if let result {
      resolve.call(withArguments: [runtime.toJS(result)])
    } else {
      resolve.call(withArguments: [NSNull()])
    }
  }
}

struct JSClassSpec {
  let name: String
  let instanceProps: [String]
  let instanceMethods: [String]
  let asyncInstanceMethods: [String]
  let staticProps: [String]
  let staticMethods: [String]
  let asyncStaticMethods: [String]
  let factory: @MainActor (JSRuntime, [Any]) -> JSObject

  init(
    name: String,
    instanceProps: [String] = [],
    instanceMethods: [String] = [],
    asyncInstanceMethods: [String] = [],
    staticProps: [String] = [],
    staticMethods: [String] = [],
    asyncStaticMethods: [String] = [],
    factory: @escaping @MainActor (JSRuntime, [Any]) -> JSObject
  ) {
    self.name = name
    self.instanceProps = instanceProps
    self.instanceMethods = instanceMethods
    self.asyncInstanceMethods = asyncInstanceMethods
    self.staticProps = staticProps
    self.staticMethods = staticMethods
    self.asyncStaticMethods = asyncStaticMethods
    self.factory = factory
  }
}

struct JSClassShape {
  let instanceProps: [String]
  let instanceMethods: [String]
  let asyncInstanceMethods: [String]
  let staticProps: [String]
  let staticMethods: [String]
  let asyncStaticMethods: [String]
}

/// The JavaScriptCore bridge for the Scriptable-compatible runtime.
/// Injects `__bs.*` helpers plus per-class constructors/prototypes so that JS
/// like `new ListWidget()`, `widget.addText("x")`, `Color.red()` dispatches to
/// Swift objects that implement `JSObject`.
@MainActor
final class JSRuntime: ObservableObject {
  let context: JSContext
  let moduleSearchDirectories: [URL]
  private var objects: [Int: JSObject] = [:]
  private var specs: [String: JSClassSpec] = [:]
  private var swiftClassMap: [String: String] = [:]
  private var nextID = 1
  private var staticGetters: [String: [String: @MainActor (JSRuntime) -> Any?]] = [:]
  private var staticCalls: [String: [String: @MainActor (JSRuntime, [Any]) -> Any?]] = [:]
  private var staticAsyncCalls:
    [String: [String: @MainActor (JSRuntime, [Any], JSValue, JSValue) -> Void]] = [:]
  var moduleCache: [String: JSValue] = [:]
  var moduleStack: [(url: URL, module: JSValue)] = []
  var rootModule: JSValue?
  var lastException: JSValue?

  @Published var consoleLines: [String] = []
  @Published var activeAlert: AlertRequest?
  @Published var activePreview: PreviewRequest?
  @Published var activeTable: UITableModel?
  @Published var completed = false
  @Published var scriptWidget: ListWidgetModel?
  var shortcutOutput: String?
  var pendingAlertResolve: JSValue?
  var pendingAlertTextFieldCount = 0

  init(moduleSearchDirectories: [URL]? = nil) {
    self.moduleSearchDirectories =
      moduleSearchDirectories ?? [
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        Bundle.main.bundleURL,
      ]
    context = JSContext()!
    context.exceptionHandler = { [weak self] _, exception in
      guard let self, let exception else { return }
      self.lastException = exception
      let msg = exception.toString() ?? "Unknown JavaScript error"
      self.consoleLines.append("Error: \(msg)")
    }
    installGateway()
    injectBootstrap()
  }

  // MARK: - Registration

  func register(_ spec: JSClassSpec) {
    specs[spec.name] = spec
    swiftClassMap[String(describing: type(of: spec.factory(self, [])))] = spec.name
    if !spec.staticProps.isEmpty {
      staticGetters[spec.name] = [:]
      staticCalls[spec.name] = [:]
    }
    context.evaluateScript(bootstrapScript(for: spec))
  }

  func registerStaticGet(
    type: String, name: String, handler: @escaping @MainActor (JSRuntime) -> Any?
  ) {
    staticGetters[type, default: [:]][name] = handler
  }

  func registerStaticCall(
    type: String, name: String, handler: @escaping @MainActor (JSRuntime, [Any]) -> Any?
  ) {
    staticCalls[type, default: [:]][name] = handler
  }

  func registerStaticAsync(
    type: String, name: String,
    handler: @escaping @MainActor (JSRuntime, [Any], JSValue, JSValue) -> Void
  ) {
    staticAsyncCalls[type, default: [:]][name] = handler
  }

  func registeredClassShapes() -> [String: JSClassShape] {
    specs.mapValues { spec in
      JSClassShape(
        instanceProps: spec.instanceProps,
        instanceMethods: spec.instanceMethods,
        asyncInstanceMethods: spec.asyncInstanceMethods,
        staticProps: spec.staticProps,
        staticMethods: spec.staticMethods,
        asyncStaticMethods: spec.asyncStaticMethods
      )
    }
  }

  private func bootstrapScript(for spec: JSClassSpec) -> String {
    var js =
      "globalThis.\(spec.name) = function() { if (!(this instanceof \(spec.name))) return new \(spec.name)(); this.__id = __bs._create('\(spec.name)', Array.prototype.slice.call(arguments)); };\n"

    if !spec.instanceProps.isEmpty {
      js +=
        "\(spec.name).prototype.__bsProps = [\(spec.instanceProps.map { "\"\($0)\"" }.joined(separator: ", "))];\n"
      js +=
        ";(function() { var p = \(spec.name).prototype.__bsProps; for (var i = 0; i < p.length; i++) (function(prop) { Object.defineProperty(\(spec.name).prototype, prop, { get: function() { return __bs._get(this.__id, prop); }, set: function(v) { __bs._set(this.__id, prop, v); }, enumerable: true, configurable: true }); })(p[i]); })();\n"
    }
    for method in spec.instanceMethods {
      js +=
        "\(spec.name).prototype.\(method) = function() { return __bs._call(this.__id, '\(method)', Array.prototype.slice.call(arguments)); };\n"
    }
    for method in spec.asyncInstanceMethods {
      js +=
        "\(spec.name).prototype.\(method) = function() { var p = __bs._makePromise(); __bs._async(this.__id, '\(method)', Array.prototype.slice.call(arguments), p.resolve, p.reject); return p.promise; };\n"
    }
    for prop in spec.staticProps {
      js +=
        "Object.defineProperty(\(spec.name), '\(prop)', { get: function() { return __bs._getStatic('\(spec.name)', '\(prop)'); }, set: function(v) { __bs._setStatic('\(spec.name)', '\(prop)', v); }, enumerable: true, configurable: true });\n"
    }
    for method in spec.staticMethods {
      js +=
        "\(spec.name).\(method) = function() { return __bs._callStatic('\(spec.name)', '\(method)', Array.prototype.slice.call(arguments)); };\n"
    }
    for method in spec.asyncStaticMethods {
      js +=
        "\(spec.name).\(method) = function() { var p = __bs._makePromise(); __bs._asyncStatic('\(spec.name)', '\(method)', Array.prototype.slice.call(arguments), p.resolve, p.reject); return p.promise; };\n"
    }
    let members = spec.instanceProps + spec.instanceMethods + spec.asyncInstanceMethods
    js +=
      "\(spec.name).prototype._scriptable_keys = function() { return \(members.map { "\"\($0)\"" }.description); };\n"
    js +=
      "\(spec.name).prototype._scriptable_values = function() { var self = this; return self._scriptable_keys().map(function(key) { return self[key]; }); };\n"
    js +=
      "\(spec.name).prototype.toJSON = function() { var result = {}; var keys = this._scriptable_keys(); var values = this._scriptable_values(); for (var i = 0; i < keys.length; i++) result[keys[i]] = values[i]; return result; };\n"
    js += "\(spec.name).prototype.toString = function() { return '[object \(spec.name)]'; };\n"
    js += "__bs._classes['\(spec.name)'] = \(spec.name);\n"
    return js
  }

  // MARK: - Object lifecycle

  func alloc(_ object: JSObject) -> JSObject {
    let id = nextID
    nextID += 1
    object.id = id
    objects[id] = object
    return object
  }

  func object(id: Int) -> JSObject? { objects[id] }

  func objectType(id: Int) -> String {
    guard let obj = objects[id] else { return "Object" }
    return swiftClassMap[String(describing: type(of: obj))] ?? "Object"
  }

  // MARK: - Value conversion

  func extractID(_ value: Any?) -> Int? {
    if let js = value as? JSValue {
      guard let v = js.objectForKeyedSubscript("__id") else { return nil }
      return v.isUndefined ? nil : v.toNumber()?.intValue
    }
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String, s.hasPrefix("__bs_obj:") {
      return Int(s.dropFirst("__bs_obj:".count))
    }
    return nil
  }

  func nativeObject(_ value: Any?) -> JSObject? {
    guard let id = extractID(value) else { return nil }
    return objects[id]
  }

  func nativeObjects(_ values: [Any]) -> [JSObject] {
    values.compactMap { nativeObject($0) }
  }

  func toJS(_ value: Any) -> Any {
    if let obj = value as? JSObject { return "__bs_obj:\(obj.id)" }
    if let arr = value as? [Any] { return arr.map { toJS($0) } }
    return value
  }

  func date(_ value: Any?) -> Date? {
    if let js = value as? JSValue { return js.toDate() }
    return value as? Date
  }

  func string(_ value: Any?) -> String? {
    if let js = value as? JSValue { return js.toString() }
    return value as? String
  }

  func double(_ value: Any?) -> Double? {
    if let js = value as? JSValue { return js.isNumber ? js.toDouble() : nil }
    return value as? Double
  }

  func bool(_ value: Any?) -> Bool? {
    if let js = value as? JSValue { return js.isBoolean ? js.toBool() : nil }
    return value as? Bool
  }

  func jsArray(_ value: Any?) -> [Any]? {
    if let js = value as? JSValue, js.isArray { return js.toArray() }
    return value as? [Any]
  }

  // MARK: - Gateway installation

  private func installGateway() {
    let create: @convention(block) (String, [Any]) -> NSNumber = { [weak self] type, args in
      MainActor.assumeIsolated {
        guard let self, let spec = self.specs[type] else { return -1 }
        let obj = self.alloc(spec.factory(self, args))
        return NSNumber(value: obj.id)
      }
    }
    let get: @convention(block) (NSNumber, String) -> Any? = { [weak self] id, name in
      let box = AnyBox()
      MainActor.assumeIsolated {
        guard let self, let obj = self.objects[id.intValue] else { return }
        box.value = obj.jsGet(self, name).map { self.toJS($0) }
      }
      return box.value
    }
    let set: @convention(block) (NSNumber, String, Any?) -> Void = {
      [weak self] id, name, value in
      MainActor.assumeIsolated {
        guard let self, let obj = self.objects[id.intValue] else { return }
        obj.jsSet(self, name, value)
      }
    }
    let call: @convention(block) (NSNumber, String, [Any]) -> Any? = {
      [weak self] id, name, args in
      let box = AnyBox()
      MainActor.assumeIsolated {
        guard let self, let obj = self.objects[id.intValue] else { return }
        box.value = obj.jsCall(self, name, args).map { self.toJS($0) }
      }
      return box.value
    }
    let async: @convention(block) (NSNumber, String, [Any], JSValue, JSValue) -> Void = {
      [weak self] id, name, args, resolve, reject in
      MainActor.assumeIsolated {
        guard let self, let obj = self.objects[id.intValue] else {
          reject.call(withArguments: ["object not found"])
          return
        }
        obj.jsAsync(self, name, args, resolve, reject)
      }
    }
    let typeForID: @convention(block) (NSNumber) -> String = { [weak self] id in
      MainActor.assumeIsolated {
        guard let self else { return "Object" }
        return self.objectType(id: id.intValue)
      }
    }
    let getStatic: @convention(block) (String, String) -> Any? = { [weak self] type, name in
      let box = AnyBox()
      MainActor.assumeIsolated {
        guard let self, let handler = self.staticGetters[type]?[name] else { return }
        box.value = handler(self).map { self.toJS($0) }
      }
      return box.value
    }
    let setStatic: @convention(block) (String, String, Any?) -> Void = { _, _, _ in }
    let callStatic: @convention(block) (String, String, [Any]) -> Any? = {
      [weak self] type, name, args in
      let box = AnyBox()
      MainActor.assumeIsolated {
        guard let self, let handler = self.staticCalls[type]?[name] else { return }
        box.value = handler(self, args).map { self.toJS($0) }
      }
      return box.value
    }
    let asyncStatic: @convention(block) (String, String, [Any], JSValue, JSValue) -> Void = {
      [weak self] type, name, args, resolve, reject in
      MainActor.assumeIsolated {
        guard let self, let handler = self.staticAsyncCalls[type]?[name] else {
          reject.call(withArguments: ["unknown static async method"])
          return
        }
        handler(self, args, resolve, reject)
      }
    }

    context.setObject(create, forKeyedSubscript: "__stupidWidgets_create" as NSString)
    context.setObject(get, forKeyedSubscript: "__stupidWidgets_get" as NSString)
    context.setObject(set, forKeyedSubscript: "__stupidWidgets_set" as NSString)
    context.setObject(call, forKeyedSubscript: "__stupidWidgets_call" as NSString)
    context.setObject(async, forKeyedSubscript: "__stupidWidgets_async" as NSString)
    context.setObject(typeForID, forKeyedSubscript: "__stupidWidgets_typeForID" as NSString)
    context.setObject(getStatic, forKeyedSubscript: "__stupidWidgets_getStatic" as NSString)
    context.setObject(setStatic, forKeyedSubscript: "__stupidWidgets_setStatic" as NSString)
    context.setObject(
      callStatic, forKeyedSubscript: "__stupidWidgets_callStatic" as NSString)
    context.setObject(
      asyncStatic, forKeyedSubscript: "__stupidWidgets_asyncStatic" as NSString)
  }

  private func injectBootstrap() {
    let bootstrap = """
      (function() {
        globalThis.__bs = {
          _classes: {},
          _create: function(type, args) { return __stupidWidgets_create(type, __bs._wrap(args || [])) },
          _get: function(id, prop) { return __bs._unwrap(__stupidWidgets_get(id, prop)) },
          _set: function(id, prop, value) { __stupidWidgets_set(id, prop, __bs._wrap(value)) },
          _call: function(id, method, args) { return __bs._unwrap(__stupidWidgets_call(id, method, __bs._wrap(args || []))) },
          _async: function(id, method, args, resolve, reject) { __stupidWidgets_async(id, method, __bs._wrap(args || []), function(value) { resolve(__bs._unwrap(value)) }, reject) },
          _getStatic: function(type, prop) { return __bs._unwrap(__stupidWidgets_getStatic(type, prop)) },
          _setStatic: function(type, prop, value) { __stupidWidgets_setStatic(type, prop, __bs._wrap(value)) },
          _callStatic: function(type, method, args) { return __bs._unwrap(__stupidWidgets_callStatic(type, method, __bs._wrap(args || []))) },
          _asyncStatic: function(type, method, args, resolve, reject) { __stupidWidgets_asyncStatic(type, method, __bs._wrap(args || []), function(value) { resolve(__bs._unwrap(value)) }, reject) },
          _object: function(id) {
            var type = __stupidWidgets_typeForID(id)
            var o = Object.create(__bs._classes[type].prototype)
            o.__id = id
            return o
          },
          _unwrap: function(r) {
            if (typeof r === 'string' && r.slice(0, 9) === '__bs_obj:') return __bs._object(Number(r.slice(9)))
            if (Array.isArray(r)) return r.map(__bs._unwrap)
            return r
          },
          _wrap: function(value) {
            if (value && typeof value === 'object' && typeof value.__id === 'number') return '__bs_obj:' + value.__id
            if (Array.isArray(value)) return value.map(__bs._wrap)
            return value
          },
          _makePromise: function() {
            var resolve, reject
            var promise = new Promise(function(res, rej) { resolve = res; reject = rej })
            return { promise: promise, resolve: resolve, reject: reject }
          }
        }
      })()
      """
    context.evaluateScript(bootstrap)
  }

  // MARK: - Execution

  @discardableResult
  func evaluate(_ source: String) -> JSValue? {
    consoleLines.removeAll()
    completed = false
    activeAlert = nil
    activePreview = nil
    activeTable = nil
    scriptWidget = nil
    let finished: @convention(block) (Any?) -> Void = { [weak self] error in
      guard let self else { return }
      if let error, !(error is NSNull) {
        self.consoleLines.append("Error: \(error)")
      }
      self.completed = true
      self.presentScriptWidgetIfNeeded()
    }
    context.setObject(
      finished, forKeyedSubscript: "__stupidWidgets_executionFinished" as NSString)
    let wrapped = """
      ;(async function() {
      \(source)
      })().then(
        function() { __stupidWidgets_executionFinished(null); },
        function(error) { __stupidWidgets_executionFinished(error && (error.stack || error.message) || String(error)); }
      );
      """
    let result = context.evaluateScript(wrapped)
    return result
  }

  /// If a script set a widget via `Script.setWidget` and nothing was presented
  /// explicitly, show it as the preview.
  func presentScriptWidgetIfNeeded() {
    guard activePreview == nil, activeTable == nil, activeAlert == nil,
      let widget = scriptWidget
    else { return }
    activePreview = PreviewRequest(kind: .widget, family: widget.previewFamily, widget: widget)
  }

  func reset() {
    consoleLines.removeAll()
    completed = false
    activeAlert = nil
    activePreview = nil
    activeTable = nil
    scriptWidget = nil
    nextID = 1
    objects.removeAll()
    context.evaluateScript("globalThis.__bs = undefined")
  }
}

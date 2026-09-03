import Foundation

struct WidgetReference {
  let name: String
  let source: String
}

@MainActor
final class AgentConversation {
  private(set) var items: [[String: Any]] = []

  var count: Int { items.count }

  func appendUserMessage(_ text: String) {
    items.append([
      "role": "user",
      "content": [["type": "input_text", "text": text]],
    ])
  }

  func replace(with newItems: [[String: Any]]) {
    items = newItems
  }

  func truncate(to count: Int) {
    guard items.count > count else { return }
    items.removeLast(items.count - count)
  }
}

enum ScriptAgentEvent {
  case textDelta(String)
  case scriptUpdated(String)
  case toolCalled(String)
}

struct ScriptAgentToolOutput {
  let text: String
  let script: String
  let didUpdateScript: Bool
}

struct ScriptAgentTools {
  static func execute(
    name: String,
    argumentsJSON: String,
    script: String,
    compilationError: ((String) -> String?)? = nil,
    apiDocumentation: ScriptAPIDocumentation? = nil,
    widgetLibrary: [WidgetReference] = []
  )
    -> ScriptAgentToolOutput
  {
    guard let data = argumentsJSON.data(using: .utf8),
      let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return output(error: "Invalid tool arguments.", script: script)
    }

    switch name {
    case "search_api":
      guard let query = arguments["query"] as? String,
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return output(error: "query must be non-empty.", script: script)
      }
      let documentation: ScriptAPIDocumentation
      if let apiDocumentation {
        documentation = apiDocumentation
      } else {
        do {
          documentation = try ScriptAPIDocumentation.bundledResult.get()
        } catch {
          return output(error: "API documentation resource is unavailable.", script: script)
        }
      }
      return ScriptAgentToolOutput(
        text: documentation.lookup(query: query),
        script: script,
        didUpdateScript: false
      )
    case "read_script":
      let lines = script.components(separatedBy: "\n")
      let offset = max(arguments["offset"] as? Int ?? 1, 1)
      let limit = min(max(arguments["limit"] as? Int ?? 100, 1), 200)
      guard offset <= lines.count else {
        return output(
          error: "Offset \(offset) exceeds \(lines.count) lines.", script: script)
      }
      let end = min(offset - 1 + limit, lines.count)
      let content = lines[(offset - 1)..<end]
        .enumerated()
        .map { "\(offset + $0.offset): \($0.element)" }
        .joined(separator: "\n")
      return ScriptAgentToolOutput(
        text: jsonString([
          "content": content,
          "line_count": lines.count,
          "next_offset": end < lines.count ? end + 1 : NSNull(),
        ]),
        script: script,
        didUpdateScript: false
      )
    case "search_widgets":
      guard let query = arguments["query"] as? String,
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return output(error: "query must be non-empty.", script: script)
      }
      let normalized = query.lowercased()
      let matches = widgetLibrary.filter { $0.name.lowercased().contains(normalized) }
      let widgets = matches.map { widget -> [String: Any] in
        [
          "name": widget.name,
          "line_count": widget.source.components(separatedBy: "\n").count,
        ]
      }
      return ScriptAgentToolOutput(
        text: jsonString(["widgets": widgets]),
        script: script,
        didUpdateScript: false
      )
    case "read_widget":
      guard let name = arguments["name"] as? String else {
        return output(error: "name must be non-empty.", script: script)
      }
      guard
        let widget = widgetLibrary.first(where: {
          $0.name.caseInsensitiveCompare(name) == .orderedSame
        })
      else {
        return output(
          error:
            "No widget named \(name). Use search_widgets to find the exact widget names before reading.",
          script: script
        )
      }
      let lines = widget.source.components(separatedBy: "\n")
      let offset = max(arguments["offset"] as? Int ?? 1, 1)
      let limit = min(max(arguments["limit"] as? Int ?? 100, 1), 200)
      guard offset <= lines.count else {
        return output(
          error: "Offset \(offset) exceeds \(lines.count) lines for \(name).", script: script)
      }
      let end = min(offset - 1 + limit, lines.count)
      let content = lines[(offset - 1)..<end]
        .enumerated()
        .map { "\(offset + $0.offset): \($0.element)" }
        .joined(separator: "\n")
      return ScriptAgentToolOutput(
        text: jsonString([
          "name": widget.name,
          "content": content,
          "line_count": lines.count,
          "next_offset": end < lines.count ? end + 1 : NSNull(),
        ]),
        script: script,
        didUpdateScript: false
      )
    case "edit_script":
      guard let oldText = arguments["old_text"] as? String, !oldText.isEmpty,
        let newText = arguments["new_text"] as? String
      else {
        return output(error: "old_text must be non-empty.", script: script)
      }
      let matches = ranges(of: oldText, in: script)
      guard matches.count == 1, let match = matches.first else {
        return output(
          error:
            "Expected one exact match, found \(matches.count). Read the script and retry.",
          script: script
        )
      }
      var updated = script
      updated.replaceSubrange(match, with: newText)
      if let error = compilationError?(updated) {
        return ScriptAgentToolOutput(
          text: jsonString([
            "updated": true,
            "compilation_error": error,
            "instruction": "The script does not compile. Continue editing until it compiles.",
          ]),
          script: updated,
          didUpdateScript: true
        )
      }
      return ScriptAgentToolOutput(
        text: jsonString(["updated": true]),
        script: updated,
        didUpdateScript: true
      )
    default:
      return output(error: "Unknown tool \(name).", script: script)
    }
  }

  private static func ranges(of needle: String, in value: String) -> [Range<String.Index>] {
    var result: [Range<String.Index>] = []
    var start = value.startIndex
    while start < value.endIndex,
      let range = value.range(of: needle, range: start..<value.endIndex)
    {
      result.append(range)
      start = range.upperBound
    }
    return result
  }

  private static func output(error: String, script: String) -> ScriptAgentToolOutput {
    ScriptAgentToolOutput(
      text: jsonString(["error": error]),
      script: script,
      didUpdateScript: false
    )
  }

  private static func jsonString(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
      let string = String(data: data, encoding: .utf8)
    else { return "{\"error\":\"Could not encode tool output.\"}" }
    return string
  }
}

@MainActor
enum ScriptAgentValidator {
  static func widgetError(source: String, scriptName: String) async throws -> String? {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: scriptName, runsInWidget: true)
    runtime.evaluate(source)

    for _ in 0..<650 where !runtime.completed {
      try await Task.sleep(for: .milliseconds(100))
    }
    guard runtime.completed else { return "Widget execution timed out." }
    if let error = runtime.consoleLines.last(where: { $0.hasPrefix("Error:") }) {
      return error
    }
    guard runtime.scriptWidget != nil else {
      return "The script completed without calling Script.setWidget(widget)."
    }
    return nil
  }
}

@MainActor
struct AgentAIClient {
  let auth: OpenAIAuth

  private struct ToolCall {
    let callID: String
    let name: String
    var arguments: String
  }

  private struct TurnResult {
    let calls: [ToolCall]
    let reasoningItems: [[String: Any]]
    let outputText: String
  }

  func chat(
    conversation: AgentConversation,
    script: String?,
    widgets: [WidgetReference]
  ) -> AsyncThrowingStream<ScriptAgentEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var input = conversation.items
        var workingScript = script ?? ""
        do {
          let credential = try await auth.validCredential()
          let validationRuntime = JSRuntime()
          var didUpdateScript = false

          for _ in 0..<100 {
            let result = try await responseTurn(
              credential: credential,
              input: input,
              continuation: continuation
            )
            if result.calls.isEmpty {
              if didUpdateScript,
                let error = try await ScriptAgentValidator.widgetError(
                  source: workingScript,
                  scriptName: "Agent Validation"
                )
              {
                input.append(contentsOf: result.reasoningItems)
                if !result.outputText.isEmpty {
                  input.append([
                    "role": "assistant",
                    "content": [["type": "output_text", "text": result.outputText]],
                  ])
                }
                input.append([
                  "role": "user",
                  "content": [
                    [
                      "type": "input_text",
                      "text":
                        "The edited widget failed runtime validation: \(error) Continue working: inspect the relevant code, fix the failure with edit_script, and do not finish until validation succeeds.",
                    ]
                  ],
                ])
                continue
              }
              if !result.outputText.isEmpty {
                input.append([
                  "role": "assistant",
                  "content": [["type": "output_text", "text": result.outputText]],
                ])
              }
              conversation.replace(with: input)
              continuation.finish()
              return
            }

            input.append(contentsOf: result.reasoningItems)
            for call in result.calls {
              continuation.yield(.toolCalled(call.name))
              input.append([
                "type": "function_call",
                "call_id": call.callID,
                "name": call.name,
                "arguments": call.arguments,
              ])
              let output = ScriptAgentTools.execute(
                name: call.name,
                argumentsJSON: call.arguments,
                script: workingScript,
                compilationError: validationRuntime.compilationError,
                widgetLibrary: widgets
              )
              workingScript = output.script
              if output.didUpdateScript {
                didUpdateScript = true
                continuation.yield(.scriptUpdated(workingScript))
              }
              input.append([
                "type": "function_call_output",
                "call_id": call.callID,
                "output": output.text,
              ])
            }
          }
          throw AIClientError.server(
            "ChatGPT exceeded the tool-call limit after one hundred turns.")
        } catch {
          conversation.replace(with: input)
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func responseTurn(
    credential: OpenAICredential,
    input: [[String: Any]],
    continuation: AsyncThrowingStream<ScriptAgentEvent, Error>.Continuation
  ) async throws -> TurnResult {
    var request = URLRequest(
      url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("stupidwidgets", forHTTPHeaderField: "originator")
    request.setValue("StupidWidgets/1", forHTTPHeaderField: "User-Agent")
    if let accountID = credential.accountID {
      request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(input: input))

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw AIClientError.server("ChatGPT request failed (HTTP \(http.statusCode)).")
    }

    var completed = false
    var pending: [String: ToolCall] = [:]
    var calls: [ToolCall] = []
    var reasoningItems: [[String: Any]] = []
    var outputText = ""
    responseStream: for try await line in bytes.lines {
      try Task.checkCancellation()
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" {
        completed = true
        break responseStream
      }
      guard let data = payload.data(using: .utf8),
        let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let type = event["type"] as? String
      else { continue }

      switch type {
      case "response.output_text.delta":
        if let delta = event["delta"] as? String {
          outputText += delta
          continuation.yield(.textDelta(delta))
        }
      case "response.output_item.added":
        if let item = event["item"] as? [String: Any],
          item["type"] as? String == "function_call",
          let itemID = item["id"] as? String,
          let callID = item["call_id"] as? String,
          let name = item["name"] as? String
        {
          pending[itemID] = ToolCall(
            callID: callID,
            name: name,
            arguments: item["arguments"] as? String ?? ""
          )
        }
      case "response.function_call_arguments.delta":
        if let itemID = event["item_id"] as? String,
          let delta = event["delta"] as? String,
          var call = pending[itemID]
        {
          call.arguments += delta
          pending[itemID] = call
        }
      case "response.output_item.done":
        guard let item = event["item"] as? [String: Any],
          let itemType = item["type"] as? String
        else { break }
        if itemType == "function_call",
          let itemID = item["id"] as? String,
          var call = pending.removeValue(forKey: itemID)
        {
          call.arguments = item["arguments"] as? String ?? call.arguments
          calls.append(call)
        } else if itemType == "reasoning",
          let encrypted = item["encrypted_content"] as? String
        {
          reasoningItems.append([
            "type": "reasoning",
            "summary": item["summary"] as? [[String: Any]] ?? [],
            "encrypted_content": encrypted,
          ])
        }
      case "response.completed":
        completed = true
        break responseStream
      case "response.failed", "response.incomplete", "error":
        let responseError =
          (event["response"] as? [String: Any])?["error"]
          as? [String: Any]
        let message =
          responseError?["message"] as? String
          ?? (event["error"] as? [String: Any])?["message"] as? String
          ?? event["message"] as? String
          ?? "ChatGPT could not complete the response."
        throw AIClientError.server(message)
      default:
        break
      }
    }
    guard completed else { throw AIClientError.invalidResponse }
    return TurnResult(calls: calls, reasoningItems: reasoningItems, outputText: outputText)
  }

  private func requestBody(input: [[String: Any]]) -> [String: Any] {
    [
      "model": "gpt-5.4-mini",
      "instructions": systemPrompt,
      "input": input,
      "tools": tools,
      "tool_choice": "auto",
      "store": false,
      "include": ["reasoning.encrypted_content"],
      "stream": true,
      "reasoning": ["effort": "medium", "summary": "auto"],
      "text": ["verbosity": "low"],
    ]
  }

  private var tools: [[String: Any]] {
    [
      [
        "type": "function",
        "name": "search_api",
        "description":
          "Search the canonical Scriptable API documentation by type or member. Use exact queries such as ListWidget, ListWidget.addText, or Request.loadJSON when possible.",
        "parameters": [
          "type": "object",
          "properties": [
            "query": [
              "type": "string",
              "description": "Type, member, signature, or concept to find.",
            ]
          ],
          "required": ["query"],
          "additionalProperties": false,
        ],
        "strict": false,
      ],
      [
        "type": "function",
        "name": "read_script",
        "description":
          "Read a bounded range of the current editor script with one-based line numbers.",
        "parameters": [
          "type": "object",
          "properties": [
            "offset": ["type": "integer", "description": "One-based starting line."],
            "limit": ["type": "integer", "description": "Maximum lines, up to 200."],
          ],
          "required": ["offset", "limit"],
          "additionalProperties": false,
        ],
        "strict": false,
      ],
      [
        "type": "function",
        "name": "search_widgets",
        "description":
          "Search the user's library of existing widget scripts by name. Use this to find reusable widget files before creating or editing scripts; the result lists matching widget names and their line counts.",
        "parameters": [
          "type": "object",
          "properties": [
            "query": [
              "type": "string",
              "description": "Case-insensitive substring to match against widget names.",
            ]
          ],
          "required": ["query"],
          "additionalProperties": false,
        ],
        "strict": false,
      ],
      [
        "type": "function",
        "name": "read_widget",
        "description":
          "Read a bounded range of another widget's source by exact name, with one-based line numbers. Use it to reuse an existing widget's style, structure, or logic. Only the widget being edited may be modified.",
        "parameters": [
          "type": "object",
          "properties": [
            "name": ["type": "string", "description": "Exact widget name."],
            "offset": ["type": "integer", "description": "One-based starting line."],
            "limit": ["type": "integer", "description": "Maximum lines, up to 200."],
          ],
          "required": ["name"],
          "additionalProperties": false,
        ],
        "strict": false,
      ],
      [
        "type": "function",
        "name": "edit_script",
        "description": "Replace one exact, unique text block in the current editor script.",
        "parameters": [
          "type": "object",
          "properties": [
            "old_text": ["type": "string", "description": "Exact existing text."],
            "new_text": ["type": "string", "description": "Replacement text."],
          ],
          "required": ["old_text", "new_text"],
          "additionalProperties": false,
        ],
        "strict": false,
      ],
    ]
  }

  private var systemPrompt: String {
    """
    You edit JavaScript in stupid widgets, an iOS Scriptable-compatible JavaScriptCore runtime. Inspect only relevant ranges with read_script, then make minimal exact replacements with edit_script. Never reproduce the full script in text. Keep unrelated code unchanged. Use search_api to confirm API names, signatures, properties, return values, and behavior instead of guessing. The search results describe canonical Scriptable; use only these currently supported APIs: ListWidget and widget elements, Request, FileManager, Data, Image, Color, Font, Alert, UITable, Notification, Keychain, Pasteboard, Device, SFSymbol, Timer, DateFormatter, QuickLook, Safari, config, args, module, importModule, console, and Script. Use Request rather than fetch. Async/await is supported. Always await async entry-point calls so script execution does not finish before the widget is ready. For widgets call Script.setWidget(widget) and Script.complete(). Use search_widgets to find the user's other widgets by name and read_widget to inspect their source when matching or reusing existing widget styles would help; never modify any widget other than the one being edited. If edit_script reports compilation_error or widget runtime validation reports a failure, do not finish: inspect the affected code and continue editing until validation succeeds. After successful edits, briefly summarize what changed.

    ## Coding assistant instructions
    \(AssistantSettings.current())
    """
  }
}

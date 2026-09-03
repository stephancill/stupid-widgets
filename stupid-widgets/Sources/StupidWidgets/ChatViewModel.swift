import Foundation
import SwiftUI

struct ChatRewind {
  let prompt: String
  let sourceBefore: String
  let messageCount: Int
  let itemCount: Int
}

@MainActor
final class ChatViewModel: ObservableObject {
  @Published var messages: [AIChatMessage] = []
  @Published var isStreaming = false
  @Published var streamingText = ""
  @Published var currentTool: String?
  @Published var errorMessage: String?
  let auth = OpenAIAuth.shared
  private var streamingTask: Task<Void, Never>?
  private let conversation = AgentConversation()
  private var rewindRecords: [ChatRewind] = []
  private var pendingRewind: ChatRewind?

  var canUndo: Bool { !rewindRecords.isEmpty }

  func send(
    _ prompt: String,
    script: String?,
    widgets: [WidgetReference],
    onInsert: @escaping (String) -> Void,
    onFinish: @escaping (Bool) -> Void
  ) {
    let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !request.isEmpty, !isStreaming else { return }
    pendingRewind = ChatRewind(
      prompt: request,
      sourceBefore: script ?? "",
      messageCount: messages.count,
      itemCount: conversation.count
    )
    messages.append(AIChatMessage(role: "user", content: request))
    conversation.appendUserMessage(request)
    isStreaming = true
    streamingText = ""
    currentTool = nil
    errorMessage = nil
    let client = AgentAIClient(auth: auth)
    streamingTask = Task {
      var accumulated = ""
      var changedScript = false
      do {
        for try await event in client.chat(
          conversation: conversation, script: script, widgets: widgets)
        {
          switch event {
          case .textDelta(let delta):
            accumulated += delta
            streamingText = accumulated
          case .scriptUpdated(let script):
            changedScript = true
            onInsert(script)
          case .toolCalled(let name):
            currentTool = name
          }
        }
        messages.append(AIChatMessage(role: "assistant", content: accumulated))
        if let code = extractCodeBlock(from: accumulated) {
          changedScript = true
          onInsert(code)
        }
      } catch is CancellationError {
      } catch {
        errorMessage = error.localizedDescription
        messages.append(
          AIChatMessage(
            role: "assistant", content: "Error: \(error.localizedDescription)"))
      }
      if changedScript, let rewind = pendingRewind {
        rewindRecords.append(rewind)
      }
      pendingRewind = nil
      isStreaming = false
      streamingText = ""
      currentTool = nil
      streamingTask = nil
      onFinish(changedScript)
    }
  }

  func undo() -> (prompt: String, source: String)? {
    guard let record = rewindRecords.popLast() else { return nil }
    pendingRewind = nil
    conversation.truncate(to: record.itemCount)
    if messages.count > record.messageCount {
      messages.removeLast(messages.count - record.messageCount)
    }
    return (record.prompt, record.sourceBefore)
  }

  func cancel() {
    streamingTask?.cancel()
    streamingTask = nil
    isStreaming = false
    streamingText = ""
    currentTool = nil
  }

  func extractCodeBlock(from text: String) -> String? {
    guard let openingFence = text.range(of: "```"),
      let closingFence = text.range(
        of: "```",
        range: openingFence.upperBound..<text.endIndex
      )
    else { return nil }

    let fencedContent = text[openingFence.upperBound..<closingFence.lowerBound]
    let codeStart =
      fencedContent.firstIndex(of: "\n").map { fencedContent.index(after: $0) }
      ?? fencedContent.startIndex
    return String(fencedContent[codeStart...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

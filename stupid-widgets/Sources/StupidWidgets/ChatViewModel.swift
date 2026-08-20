import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
  @Published var messages: [AIChatMessage] = []
  @Published var isStreaming = false
  @Published var streamingText = ""
  @Published var currentTool: String?
  @Published var errorMessage: String?
  let auth = OpenAIAuth.shared
  private var streamingTask: Task<Void, Never>?

  func send(
    _ prompt: String, script: String?, onInsert: @escaping (String) -> Void,
    onFinish: @escaping (Bool) -> Void
  ) {
    messages.append(AIChatMessage(role: "user", content: prompt))
    isStreaming = true
    streamingText = ""
    currentTool = nil
    errorMessage = nil
    let client = AgentAIClient(auth: auth)
    streamingTask = Task {
      var accumulated = ""
      var changedScript = false
      do {
        for try await event in client.chat(messages: messages, script: script) {
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
      isStreaming = false
      streamingText = ""
      currentTool = nil
      streamingTask = nil
      onFinish(changedScript)
    }
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

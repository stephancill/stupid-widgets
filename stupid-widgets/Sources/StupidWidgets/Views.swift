import SwiftUI
import UIKit

public struct StupidWidgetsRootView: View {
  @StateObject private var store = ScriptStore()

  public init() {}

  public var body: some View {
    ScriptListView()
      .environmentObject(store)
  }
}

// MARK: - Script list

struct ScriptListView: View {
  @EnvironmentObject private var store: ScriptStore
  @State private var renaming: Script?
  @State private var renameText = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.scripts) { script in
          NavigationLink(value: script.id) {
            HStack(spacing: 12) {
              Image(systemName: iconSymbol(for: script.iconGlyph))
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor(script.iconColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
              Text(script.name)
            }
          }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              store.delete(id: script.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
            Button {
              renaming = script
              renameText = script.name
            } label: {
              Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
          }
          .contextMenu {
            ShareLink(item: script.fileURL) { Label("Export", systemImage: "square.and.arrow.up") }
          }
        }
      }
      .navigationTitle("Scripts")
      .navigationDestination(for: UUID.self) { id in
        if let script = store.script(id: id) {
          EditorView(script: script)
        } else {
          ContentUnavailableView("Script Not Found", systemImage: "doc.badge.ellipsis")
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            if let script = store.create() {
              renaming = script
              renameText = script.name
            }
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .alert(
        "Rename Script",
        isPresented: Binding(
          get: { renaming != nil },
          set: { if !$0 { renaming = nil } }
        )
      ) {
        TextField("Name", text: $renameText)
        Button("Cancel", role: .cancel) { renaming = nil }
        Button("Rename") {
          if let script = renaming { store.rename(id: script.id, to: renameText) }
          renaming = nil
        }
      }
      .alert(
        "Script Error",
        isPresented: Binding(
          get: { store.errorMessage != nil },
          set: { if !$0 { store.errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(store.errorMessage ?? "")
      }
    }
  }

  private func iconSymbol(for glyph: String) -> String {
    let symbol = glyph.hasSuffix(".fill") ? String(glyph.dropLast(5)) : glyph
    if UIImage(systemName: symbol) != nil { return symbol }
    return "doc.text"
  }

  private func iconColor(_ name: String) -> Color {
    switch name {
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    case "deep-blue": return Color(red: 0.1, green: 0.2, blue: 0.5)
    default: return .gray
    }
  }
}

// MARK: - Editor

@MainActor
final class ScriptExecution: ObservableObject {
  @Published var runtime: JSRuntime

  init(scriptName: String) {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: scriptName)
    self.runtime = runtime
  }

  @discardableResult
  func run(source: String, scriptName: String) -> JSRuntime {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: scriptName)
    self.runtime = runtime
    runtime.evaluate(source)
    return runtime
  }
}

struct EditorView: View {
  @EnvironmentObject private var store: ScriptStore
  let script: Script
  @StateObject private var execution: ScriptExecution
  @StateObject private var chat = ChatViewModel()
  @ObservedObject private var auth = OpenAIAuth.shared
  @State private var source: String
  @State private var showingCode = false
  @State private var hasRun = false
  @State private var prompt = ""
  @State private var undoSources: [String] = []
  @State private var pendingUndoSource: String?

  init(script: Script) {
    self.script = script
    _source = State(initialValue: script.source)
    _execution = StateObject(wrappedValue: ScriptExecution(scriptName: script.name))
  }

  var body: some View {
    Group {
      if showingCode {
        VStack(spacing: 0) {
          TextEditor(text: $source)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(uiColor: .secondarySystemBackground))

          Divider()

          RuntimeConsole(runtime: execution.runtime)
        }
      } else {
        ScriptDetailPreview(runtime: execution.runtime)
      }
    }
    .navigationTitle(script.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(showingCode ? "Preview" : "Edit") {
          showingCode.toggle()
          if !showingCode { run() }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      ChangePromptField(
        prompt: $prompt,
        canUndo: !undoSources.isEmpty,
        isWorking: chat.isStreaming || auth.isSigningIn,
        onUndo: undoChanges,
        onSubmit: submitPrompt,
        onCancel: cancelPrompt,
        onRender: run
      )
      .padding(.horizontal, 28)
      .padding(.top, 10)
      .padding(.bottom, 8)
      .background(.black.opacity(0.001))
    }
    .background(
      RuntimePresentationHost(runtime: execution.runtime, presentsWidgetPreviews: false)
    )
    .onChange(of: source) { _, newValue in store.updateSource(id: script.id, source: newValue) }
    .alert(
      "Assistant Error",
      isPresented: Binding(
        get: { chat.errorMessage != nil || auth.errorMessage != nil },
        set: {
          if !$0 {
            chat.errorMessage = nil
            auth.errorMessage = nil
          }
        }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(chat.errorMessage ?? auth.errorMessage ?? "Unknown error")
    }
    .task {
      guard !hasRun else { return }
      hasRun = true
      run()
    }
  }

  private func run() {
    let runtime = execution.run(source: source, scriptName: script.name)
    Task { @MainActor in
      for _ in 0..<200 where !runtime.completed {
        try? await Task.sleep(for: .milliseconds(100))
      }
      if runtime.scriptWidget != nil {
        store.reloadWidgets()
      }
    }
  }

  private func submitPrompt() {
    let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !request.isEmpty, !chat.isStreaming, !auth.isSigningIn else { return }
    guard auth.isSignedIn else {
      auth.signIn()
      return
    }
    pendingUndoSource = source
    chat.send(
      request,
      script: source,
      onInsert: { updatedSource in
        guard updatedSource != source else { return }
        if let previousSource = pendingUndoSource {
          undoSources.append(previousSource)
          pendingUndoSource = nil
        }
        source = updatedSource
      },
      onFinish: { changedSource in
        pendingUndoSource = nil
        prompt = ""
        if changedSource { run() }
      }
    )
  }

  private func cancelPrompt() {
    if auth.isSigningIn {
      auth.cancelSignIn()
    } else {
      chat.cancel()
    }
    pendingUndoSource = nil
  }

  private func undoChanges() {
    guard let previousSource = undoSources.popLast() else { return }
    source = previousSource
    run()
  }
}

private struct ChangePromptField: View {
  @Binding var prompt: String
  let canUndo: Bool
  let isWorking: Bool
  let onUndo: () -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void
  let onRender: () -> Void
  @State private var compactTextWidth: CGFloat = 0

  var body: some View {
    HStack(spacing: 10) {
      if !isExpanded, canUndo { undoButton }
      promptField
      if !isExpanded { renderButton }
    }
    .frame(maxWidth: .infinity)
    .animation(.snappy, value: isExpanded)
    .accessibilityElement(children: .contain)
  }

  private var undoButton: some View {
    Button(action: onUndo) {
      Image(systemName: "arrow.uturn.backward")
        .font(.title3)
    }
    .frame(width: 54, height: 54)
    .background(.ultraThinMaterial, in: Circle())
    .overlay {
      Circle()
        .stroke(.secondary.opacity(0.25), lineWidth: 1)
    }
    .buttonStyle(.plain)
    .disabled(isWorking)
    .accessibilityLabel("Undo changes")
  }

  private var promptField: some View {
    ZStack(alignment: isExpanded ? .topTrailing : .trailing) {
      TextField("Describe changes", text: $prompt, axis: .vertical)
        .lineLimit(isExpanded ? 3...6 : 1...1)
        .submitLabel(.go)
        .foregroundStyle(isWorking ? .gray : .primary)
        .disabled(isWorking)
        .onSubmit(onSubmit)
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.width
        } action: { width in
          if !isExpanded, width > 0 { compactTextWidth = width }
        }
        .padding(.leading, 16)
        .padding(.trailing, 52)
        .padding(.vertical, isExpanded ? 14 : 0)
        .frame(
          minHeight: isExpanded ? 96 : 54,
          alignment: isExpanded ? .topLeading : .leading
        )

      Button(action: isWorking ? onCancel : onSubmit) {
        Image(systemName: isWorking ? "stop.fill" : "play.fill")
          .font(.title3)
      }
      .frame(width: 44, height: 44)
      .buttonStyle(.plain)
      .padding(.top, isExpanded ? 5 : 0)
      .padding(.trailing, 6)
      .disabled(!isWorking && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel(isWorking ? "Stop changes" : "Apply changes")
    }
    .frame(maxWidth: .infinity)
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: isExpanded ? 24 : 27)
    )
    .overlay {
      RoundedRectangle(cornerRadius: isExpanded ? 24 : 27)
        .stroke(.secondary.opacity(0.25), lineWidth: 1)
    }
  }

  private var renderButton: some View {
    Button(action: onRender) {
      Image(systemName: "arrow.clockwise")
        .font(.title3)
    }
    .frame(width: 54, height: 54)
    .background(.ultraThinMaterial, in: Circle())
    .overlay {
      Circle()
        .stroke(.secondary.opacity(0.25), lineWidth: 1)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Rerender widget")
  }

  private var isExpanded: Bool {
    guard compactTextWidth > 0, !prompt.isEmpty else { return false }
    let font = UIFont.preferredFont(forTextStyle: .body)
    let bounds = (prompt as NSString).boundingRect(
      with: CGSize(width: compactTextWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    )
    return bounds.height > font.lineHeight * 2.05
  }
}

struct ScriptDetailPreview: View {
  @ObservedObject var runtime: JSRuntime

  var body: some View {
    Group {
      if let preview = runtime.activePreview, case .widget = preview.kind,
        let widget = preview.widget
      {
        WidgetRenderer(widget: widget, family: preview.family)
          .frame(width: 320, height: preview.family == "medium" ? 155 : 320)
      } else if !runtime.completed {
        ProgressView("Running script...")
      } else {
        ContentUnavailableView(
          "No Widget", systemImage: "rectangle.slash",
          description: Text("This script did not produce a widget."))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

struct RuntimeConsole: View {
  @ObservedObject var runtime: JSRuntime

  var body: some View {
    if !runtime.consoleLines.isEmpty {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 3) {
          ForEach(Array(runtime.consoleLines.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(line.hasPrefix("Error") ? .red : .secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(8)
      }
      .frame(maxHeight: 140)
      .background(Color(uiColor: .tertiarySystemBackground))
    }
  }
}

struct RuntimePresentationHost: View {
  @ObservedObject var runtime: JSRuntime
  var presentsWidgetPreviews = true

  var body: some View {
    Color.clear
      .sheet(item: $runtime.activeAlert) { _ in AlertSheet(runtime: runtime) }
      .sheet(item: presentedPreview) { preview in WidgetPreviewSheet(preview: preview) }
      .sheet(
        isPresented: Binding(
          get: { runtime.activeTable != nil },
          set: { if !$0 { runtime.dismissTable() } }
        )
      ) {
        if let table = runtime.activeTable { TableSheet(table: table, runtime: runtime) }
      }
  }

  private var presentedPreview: Binding<PreviewRequest?> {
    Binding(
      get: {
        guard let preview = runtime.activePreview else { return nil }
        if !presentsWidgetPreviews, case .widget = preview.kind { return nil }
        return preview
      },
      set: { runtime.activePreview = $0 }
    )
  }
}

// MARK: - Alert

struct AlertSheet: View {
  @ObservedObject var runtime: JSRuntime
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 16) {
      Text(runtime.activeAlert?.title ?? "")
        .font(.headline)
      if let msg = runtime.activeAlert?.message, !msg.isEmpty {
        Text(msg).font(.body).foregroundStyle(.secondary)
      }
      ForEach(Array((runtime.activeAlert?.actions ?? []).enumerated()), id: \.offset) {
        idx, action in
        Button {
          runtime.dismissAlert(index: idx)
        } label: {
          Text(action.title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(
          action.style == .destructive ? .red : (action.style == .cancel ? .gray : .accentColor))
      }
    }
    .padding(24)
    .presentationDetents([.medium])
  }
}

// MARK: - Widget / text / image preview

struct WidgetPreviewSheet: View {
  let preview: PreviewRequest

  var body: some View {
    VStack(spacing: 12) {
      switch preview.kind {
      case .widget:
        if let widget = preview.widget {
          WidgetRenderer(widget: widget, family: preview.family)
            .frame(width: 320, height: preview.family == "medium" ? 155 : 320)
            .padding()
        }
      case .text:
        ScrollView {
          Text(preview.text ?? "")
            .font(.system(.body, design: .monospaced))
            .padding()
        }
      case .image:
        if let image = preview.image?.image {
          Image(uiImage: image).resizable().scaledToFit().padding()
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

// MARK: - Table

struct TableSheet: View {
  let table: UITableModel
  @ObservedObject var runtime: JSRuntime
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(Array(table.rows.enumerated()), id: \.offset) { idx, row in
          rowView(row, rowIndex: idx)
        }
      }
      .navigationTitle("Result")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { runtime.dismissTable() }
        }
      }
    }
  }

  @ViewBuilder
  private func rowView(_ row: UITableRowModel, rowIndex: Int) -> some View {
    let content = HStack(spacing: CGFloat(row.cellSpacing)) {
      ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
        cellView(cell)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    if row.isHeader {
      content.font(.headline)
    } else {
      Button {
        row.onSelect?.call(withArguments: [NSNumber(value: rowIndex)])
        if row.dismissOnSelect { runtime.dismissTable() }
      } label: {
        content
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func cellView(_ cell: UITableCellModel) -> some View {
    switch cell.kind {
    case .text:
      Text(cell.text ?? "")
        .font(cell.titleFont.map { Font($0.font) } ?? .body)
        .foregroundColor(cell.titleColor.map { Color($0.uiColor) } ?? .primary)
    case .image:
      if let image = cell.image?.image {
        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 80)
      }
    case .imageAtURL:
      Image(systemName: "photo").foregroundStyle(.secondary)
    case .button:
      Button(cell.text ?? "") { cell.onTap?.call(withArguments: []) }
        .buttonStyle(.bordered)
    }
  }
}

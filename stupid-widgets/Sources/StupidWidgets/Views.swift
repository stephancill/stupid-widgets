import SwiftUI
import UIKit
import WidgetRender

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
  @State private var navigationPath: [UUID] = []
  @State private var showingSettings = false
  @FocusState private var isNameFieldFocused: Bool

  var body: some View {
    NavigationStack(path: $navigationPath) {
      List {
        ForEach(store.scripts) { script in
          scriptRow(script)
        }
      }
      .contentMargins(.top, 16, for: .scrollContent)
      .overlay {
        if store.scripts.isEmpty {
          ContentUnavailableView {
            Label("No Widgets", systemImage: "square.grid.3x3")
          } description: {
            Text("Create a widget script to get started.")
          } actions: {
            Button {
              createAndOpenWidget()
            } label: {
              Label("New Widget", systemImage: "plus")
            }
          }
        }
      }
      .navigationTitle("Widgets")
      .navigationDestination(for: UUID.self) { id in
        if let script = store.script(id: id) {
          EditorView(script: script)
        } else {
          ContentUnavailableView("Widget Not Found", systemImage: "doc.badge.ellipsis")
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
          .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            createAndOpenWidget()
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsSheet()
      }
      .alert(
        "Rename Widget",
        isPresented: Binding(
          get: { renaming != nil },
          set: { if !$0 { renaming = nil } }
        )
      ) {
        TextField("Name", text: $renameText)
          .focused($isNameFieldFocused)
        Button("Cancel", role: .cancel) {
          renaming = nil
        }
        Button("Rename") {
          if let script = renaming {
            store.rename(id: script.id, to: renameText)
          }
          renaming = nil
        }
        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .alert(
        "Widget Error",
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

  private func scriptRow(_ script: Script) -> some View {
    NavigationLink(value: script.id) {
      HStack(spacing: 8) {
        Text(script.name)
          .font(.body)
          .lineLimit(1)
        Spacer()
        Text(relativeEditedTime(for: script))
          .font(.body)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 2)
    }
    .swipeActions {
      Button("Delete", role: .destructive) {
        store.delete(id: script.id)
      }
    }
    .swipeActions(edge: .leading) {
      Button("Rename") {
        renaming = script
        renameText = script.name
        focusNameField(selectAll: false)
      }
      .tint(.blue)
    }
    .contextMenu {
      ShareLink(item: script.fileURL) {
        Label("Export", systemImage: "square.and.arrow.up")
      }
    }
  }

  private func createAndOpenWidget() {
    if let widget = store.create(name: "Untitled Widget") {
      navigationPath.append(widget.id)
    }
  }

  private func relativeEditedTime(for script: Script) -> String {
    guard let date = script.modificationDate else { return "" }

    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 30 { return "\(days)d" }
    let months = days / 30
    if months < 12 { return "\(months)mo" }
    return "\(months / 12)y"
  }

  private func focusNameField(selectAll: Bool) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(100))
      isNameFieldFocused = true
      guard selectAll else { return }
      try? await Task.sleep(for: .milliseconds(50))
      for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows {
          if let textField = firstResponderTextField(in: window) {
            textField.selectAll(nil)
            return
          }
        }
      }
    }
  }

  private func firstResponderTextField(in view: UIView) -> UITextField? {
    if let textField = view as? UITextField, textField.isFirstResponder { return textField }
    for subview in view.subviews {
      if let textField = firstResponderTextField(in: subview) { return textField }
    }
    return nil
  }
}

// MARK: - Editor

enum WidgetPreviewFamily: String, CaseIterable, Identifiable {
  case small
  case medium
  case large

  var id: Self { self }

  var title: String { rawValue.capitalized }

  var size: CGSize {
    switch self {
    case .small: CGSize(width: 170, height: 170)
    case .medium: CGSize(width: 360, height: 170)
    case .large: CGSize(width: 360, height: 380)
    }
  }
}

@MainActor
final class ScriptExecution: ObservableObject {
  @Published var runtime: JSRuntime

  init(scriptName: String) {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(scriptName: scriptName, runsInWidget: true)
    self.runtime = runtime
  }

  @discardableResult
  func run(source: String, scriptName: String, widgetFamily: String = "medium") -> JSRuntime {
    let runtime = JSRuntime()
    runtime.installScriptableAPI(
      scriptName: scriptName, runsInWidget: true, widgetFamily: widgetFamily)
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
  @State private var isEditingTitle = false
  @State private var titleText = ""
  @State private var previewFamily = WidgetPreviewFamily.medium

  init(script: Script) {
    self.script = script
    _source = State(initialValue: script.source)
    _execution = StateObject(wrappedValue: ScriptExecution(scriptName: script.name))
    _previewFamily = State(initialValue: WidgetPreviewFamily(rawValue: script.previewFamily) ?? .medium)
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
        ScriptDetailPreview(
          runtime: execution.runtime,
          family: $previewFamily,
          onShowError: { showingCode = true }
        )
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Button {
          titleText = scriptName
          isEditingTitle = true
        } label: {
          Text(scriptName)
            .font(.headline)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit title")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(showingCode ? "Preview" : "Edit") {
          showingCode.toggle()
          if !showingCode { run() }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      statusAccessory
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    .alert("Rename Widget", isPresented: $isEditingTitle) {
      TextField("Name", text: $titleText)
      Button("Cancel", role: .cancel) {}
      Button("Rename", action: saveTitle)
    }
    .background(
      RuntimePresentationHost(runtime: execution.runtime, presentsWidgetPreviews: false)
    )
    .onChange(of: source) { _, newValue in store.updateSource(id: script.id, source: newValue) }
    .onChange(of: previewFamily) { _, _ in
      store.updatePreviewFamily(id: script.id, family: previewFamily.rawValue)
      run()
    }
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
    .alert(
      "Widget Error",
      isPresented: Binding(
        get: { store.errorMessage != nil },
        set: { if !$0 { store.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(store.errorMessage ?? "")
    }
    .task {
      guard !hasRun else { return }
      hasRun = true
      run()
    }
  }

  private func run() {
    let runtime = execution.run(
      source: source, scriptName: scriptName, widgetFamily: previewFamily.rawValue)
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
    let widgets = store.scripts.map { WidgetReference(name: $0.name, source: $0.source) }
    chat.send(
      request,
      script: source,
      widgets: widgets,
      onInsert: { updatedSource in
        guard updatedSource != source else { return }
        source = updatedSource
      },
      onFinish: { changedSource in
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
  }

  private func undoChanges() {
    guard let rewind = chat.undo() else { return }
    source = rewind.source
    prompt = rewind.prompt
    run()
  }

  @ViewBuilder
  private var statusAccessory: some View {
    if auth.isSignedIn {
      VStack(spacing: 6) {
        if chat.isStreaming, let tool = chat.currentTool {
          toolStatus(tool)
            .id(tool)
            .animation(.default, value: chat.currentTool)
        }
        ChangePromptField(
          prompt: $prompt,
          canUndo: chat.canUndo,
          isWorking: chat.isStreaming || auth.isSigningIn,
          onUndo: undoChanges,
          onSubmit: submitPrompt,
          onCancel: cancelPrompt,
          onRerun: run
        )
      }
    } else {
      HStack(spacing: 10) {
        connectButton
        reloadButton
      }
    }
  }

  private func toolStatus(_ tool: String) -> some View {
    Label(tool, systemImage: "hammer")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .center)
      .transition(.move(edge: .top).combined(with: .opacity))
  }

  private var connectButton: some View {
    Button(action: { auth.signIn() }) {
      Text("Edit with ChatGPT")
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
          Capsule()
            .stroke(.secondary.opacity(0.25), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .disabled(auth.isSigningIn)
    .accessibilityLabel("Edit with ChatGPT")
  }

  private var reloadButton: some View {
    Button(action: run) {
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
    .accessibilityLabel("Rerun widget script")
  }

  private var scriptName: String {
    store.script(id: script.id)?.name ?? script.name
  }

  private func saveTitle() {
    let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    store.rename(id: script.id, to: title)
    isEditingTitle = false
  }
}

private struct ChangePromptField: View {
  @Binding var prompt: String
  let canUndo: Bool
  let isWorking: Bool
  let onUndo: () -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void
  let onRerun: () -> Void
  @State private var compactTextWidth: CGFloat = 0

  var body: some View {
    HStack(spacing: 10) {
      if !isExpanded, canUndo { undoButton }
      promptField
      if !isExpanded { rerunButton }
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

  private var rerunButton: some View {
    Button(action: onRerun) {
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
    .accessibilityLabel("Rerun widget script")
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
  @Binding var family: WidgetPreviewFamily
  let onShowError: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Picker("Widget size", selection: $family) {
        ForEach(WidgetPreviewFamily.allCases) { family in
          Text(family.title).tag(family)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 320)

      Group {
        if let preview = runtime.activePreview, case .widget = preview.kind,
          let widget = preview.widget
        {
          WidgetPreviewCanvas(widget: widget, family: family)
        } else if !runtime.completed {
          ProgressView("Running script...")
        } else {
          ContentUnavailableView {
            Label("No Widget", systemImage: "rectangle.slash")
          } description: {
            Text("This script did not produce a widget.")
          } actions: {
            Button("Show Error", action: onShowError)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

private struct WidgetPreviewCanvas: View {
  let widget: ListWidgetModel
  let family: WidgetPreviewFamily

  var body: some View {
    ScriptWidgetSnapshotView(snapshot: ScriptWidgetRunner.snapshot(widget: widget))
      .clipShape(RoundedRectangle(cornerRadius: family == .medium ? 22 : 18))
      .frame(width: family.size.width, height: family.size.height)
  }
}

struct RuntimeConsole: View {
  @ObservedObject var runtime: JSRuntime

  var body: some View {
    if !runtime.consoleLines.isEmpty {
      VStack(spacing: 0) {
        if let errorText {
          HStack {
            Text("Error")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.red)
            Spacer()
            Button {
              UIPasteboard.general.string = errorText
            } label: {
              Label("Copy Error", systemImage: "doc.on.doc")
            }
            .font(.caption)
            .buttonStyle(.borderless)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)

          Divider()
        }

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
      }
      .background(Color(uiColor: .tertiarySystemBackground))
    }
  }

  private var errorText: String? {
    let errors = runtime.consoleLines.filter { $0.hasPrefix("Error") }
    return errors.isEmpty ? nil : errors.joined(separator: "\n")
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
          WidgetPreviewCanvas(
            widget: widget,
            family: WidgetPreviewFamily(rawValue: preview.family) ?? .medium
          )
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

// MARK: - Settings

struct SettingsSheet: View {
  @ObservedObject private var auth = OpenAIAuth.shared
  @ObservedObject private var settings = AssistantSettings.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("ChatGPT") {
          HStack {
            Label(
              "ChatGPT",
              systemImage: auth.isSignedIn
                ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.questionmark"
            )
            Spacer()
            if auth.isSignedIn {
              Button("Sign Out", role: .destructive) {
                auth.signOut()
              }
            } else {
              Button(auth.isSigningIn ? "Signing In…" : "Connect") {
                auth.signIn()
              }
              .disabled(auth.isSigningIn)
            }
          }
          if let error = auth.errorMessage {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        Section {
          TextEditor(text: $settings.instructions)
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 240)
        } header: {
          Text("Coding Assistant Instructions")
        } footer: {
          Text(
            "These instructions are injected into every conversation with the coding assistant. The default keeps new widgets styled like the Hello Widget sample."
          )
        }
        Section {
          Button("Reset to Hello Widget Style") {
            settings.reset()
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

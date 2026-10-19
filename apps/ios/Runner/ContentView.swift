import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @State private var composer = ""
  @State private var showingPairing = false
  @State private var showingSettings = false
  @State private var drawerProgress: CGFloat = 0
  @State private var gestureStartProgress: CGFloat?
  @State private var horizontalGesture: Bool?
  @State private var shareFile: ShareFile?

  var body: some View {
    GeometryReader { proxy in
      let drawerWidth = proxy.size.width * 0.80
      ZStack(alignment: .leading) {
        MobileDrawer(width: drawerWidth, close: closeDrawer, openSettings: { closeDrawer(); showingSettings = true })
          .environmentObject(bridge)

        mainLayer
          .frame(width: proxy.size.width)
          .clipShape(LeadingRoundedRectangle(radius: 36 * drawerProgress))
          .shadow(color: .black.opacity(0.13 * drawerProgress), radius: 8, x: -4, y: 0)
          .offset(x: drawerWidth * drawerProgress)
          .gesture(drawerGesture(width: drawerWidth))
      }
      .background(Color.white.ignoresSafeArea())
    }
    .preferredColorScheme(.light)
    .sheet(isPresented: $showingSettings) { SettingsView() }
    .sheet(item: $shareFile) { value in ActivityView(url: value.url) }
    .sheet(isPresented: $showingPairing) {
      PairingView { raw in
        showingPairing = false
        Task { await bridge.pair(from: raw) }
      }
    }
    .sheet(item: $bridge.approval) { approval in
      NativeApprovalSheet(approval: approval)
    }
  }

  private var mainLayer: some View {
    VStack(spacing: 0) {
      header
      conversation
      composerBar
    }
    .background(Color.white)
  }

  private func drawerGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 10)
      .onChanged { value in
        if horizontalGesture == nil {
          horizontalGesture = abs(value.translation.width) > abs(value.translation.height) && abs(value.translation.width) > 6
        }
        guard horizontalGesture == true else { return }
        if gestureStartProgress == nil { gestureStartProgress = drawerProgress }
        let delta = value.translation.width / max(width, 1)
        drawerProgress = min(1, max(0, (gestureStartProgress ?? drawerProgress) + delta))
      }
      .onEnded { value in
        guard horizontalGesture == true else {
          gestureStartProgress = nil
          horizontalGesture = nil
          return
        }
        let start = gestureStartProgress ?? drawerProgress
        let projected = start + value.predictedEndTranslation.width / max(width, 1)
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
          drawerProgress = projected > 0.45 ? 1 : 0
        }
        gestureStartProgress = nil
        horizontalGesture = nil
      }
  }

  private func closeDrawer() {
    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
      drawerProgress = 0
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
          drawerProgress = drawerProgress > 0.5 ? 0 : 1
        }
      } label: {
        Image(systemName: "line.3.horizontal")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 36, height: 36)
      }
      .buttonStyle(MobileIconButtonStyle())
      .accessibilityLabel("打开侧边菜单")
      VStack(alignment: .leading, spacing: 2) {
        Text(threadTitle)
          .font(.system(size: bridge.currentThread == nil ? 22 : 15, weight: .semibold))
          .lineLimit(1)
        if bridge.currentThread != nil {
          HStack(spacing: 5) {
            Circle().fill(bridge.running ? Color.orange : Color.green).frame(width: 6, height: 6)
            Text(bridge.running ? "运行中" : bridge.status)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
      if bridge.currentThread == nil && bridge.desktopReady {
        HStack(spacing: 5) {
          Circle().fill(bridge.running ? Color.orange : Color.green).frame(width: 6, height: 6)
          Text(bridge.running ? "运行中" : "Connected")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 7)
  }

  private var threadTitle: String {
    guard let thread = bridge.currentThread else { return "Mobile Codex" }
    if let project = bridge.projects.first(where: { $0.id == thread.projectId }) {
      return "\(project.label)/\(thread.title)"
    }
    return thread.title
  }

  private var conversation: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if !bridge.desktopReady {
            EmptyStateView(
              title: "连接你的电脑",
              message: bridge.notice.isEmpty ? "配对后可以继续 Desktop 上的任务。" : bridge.notice,
              actionTitle: bridge.hasCredentials ? "重新连接" : "开始配对",
              action: {
                if bridge.hasCredentials { Task { await bridge.connect() } } else { showingPairing = true }
              }
            )
          } else if bridge.currentThread == nil && bridge.messages.isEmpty {
            EmptyStateView(
              title: "开始一个任务",
              message: "选择一个聊天，或直接输入新的任务。",
              actionTitle: "查看聊天",
              action: { openDrawer() }
            )
          } else {
            ForEach(bridge.messages) { message in
              MessageRow(message: message)
                .id(message.id)
            }
            if !bridge.diff.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Label("Diff", systemImage: "arrow.left.arrow.right")
                  .font(.subheadline.weight(.semibold))
                Text(bridge.diff)
                  .font(.system(.footnote, design: .monospaced))
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(14)
              .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.08)))
            }
            if !bridge.artifacts.isEmpty {
              ForEach(bridge.artifacts) { artifact in
                Button {
                  Task {
                    do { shareFile = ShareFile(url: try await bridge.download(artifact)) }
                    catch { bridge.setNotice(error.localizedDescription) }
                  }
                } label: {
                  Label(artifact.name, systemImage: "paperclip")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
              }
            }
            if bridge.running {
              HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("电脑正在处理任务")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 16)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
      }
      .onChange(of: bridge.messages.count) { _ in
        if let id = bridge.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
      }
    }
  }

  private var composerBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $composer)
          .font(.system(size: 14))
          .frame(minHeight: 42, maxHeight: 104)
          .padding(.horizontal, 8)
          .padding(.vertical, 7)
          .background(Color.white)
          .onSubmit { submit() }
        if composer.isEmpty {
          Text(bridge.currentThread == nil ? "Message Codex…" : "Add direction to this task…")
            .font(.system(size: 14))
            .foregroundStyle(Color.black.opacity(0.38))
            .padding(.horizontal, 13)
            .padding(.vertical, 15)
            .allowsHitTesting(false)
        }
      }
      HStack(spacing: 7) {
        Menu {
          Picker("模式", selection: $bridge.mode) {
            Text("Default").tag("default")
            Text("Plan").tag("plan")
          }
        } label: {
          Label(bridge.mode == "plan" ? "Plan" : "Default", systemImage: "route")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        if !bridge.models.isEmpty {
          Menu {
            ForEach(bridge.models) { model in
              Button {
                bridge.selectedModel = model.id
              } label: {
                if model.id == bridge.selectedModel { Label(model.label, systemImage: "checkmark") } else { Text(model.label) }
              }
            }
          } label: {
            Text(bridge.models.first(where: { $0.id == bridge.selectedModel })?.label ?? "Model")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
        Spacer(minLength: 0)
        if bridge.running {
          Button { Task { await bridge.interrupt() } } label: {
            Image(systemName: "stop.fill")
              .font(.system(size: 11, weight: .bold))
              .frame(width: 34, height: 34)
              .background(Color.black, in: Circle())
              .foregroundStyle(.white)
          }
          .accessibilityLabel("停止任务")
        } else {
          Button(action: submit) {
            Image(systemName: "arrow.up")
              .font(.system(size: 14, weight: .bold))
              .frame(width: 34, height: 34)
              .background(Color.black, in: Circle())
              .foregroundStyle(.white)
          }
          .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bridge.desktopReady)
          .opacity(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bridge.desktopReady ? 0.35 : 1)
          .accessibilityLabel("发送")
        }
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 8)
    }
    .padding(.horizontal, 13)
    .padding(.top, 9)
    .padding(.bottom, 5)
    .background(Color.white)
    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.black.opacity(0.11)))
    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    .padding(.horizontal, 13)
    .padding(.bottom, 10)
  }

  private func submit() {
    let value = composer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, bridge.desktopReady else { return }
    composer = ""
    Task { await bridge.send(value) }
  }

  private func openDrawer() {
    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
      drawerProgress = 1
    }
  }

}
private struct EmptyStateView: View {
  let title: String
  let message: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "sparkles")
        .font(.system(size: 38, weight: .light))
        .foregroundStyle(.primary)
      Text(title).font(.title3.weight(.semibold))
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(actionTitle, action: action)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.black, in: Capsule())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 90)
  }
}
private struct NativeApprovalSheet: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @Environment(\.dismiss) private var dismiss
  @State private var answers: [String: String] = [:]
  @State private var values: [String: String] = [:]
  @State private var booleans: [String: Bool] = [:]
  let approval: NativeApproval

  var body: some View {
    NavigationView {
      Form {
        if approval.method == "item/tool/requestUserInput" {
          ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
            let id = nativeString(question["id"]) ?? ""
            Section(nativeString(question["question"]) ?? "问题") {
              ForEach(Array(nativeArray(question["options"]).enumerated()), id: \.offset) { _, option in
                let label = nativeString(option["label"]) ?? ""
                Button(label) { answers[id] = label }
                  .foregroundStyle(answers[id] == label ? Color.accentColor : Color.primary)
              }
              TextField("输入你的回答", text: binding(for: id, in: $answers))
            }
          }
        } else if approval.method == "mcpServer/elicitation/request" && nativeString(approval.payload["mode"]) == "form" {
          Section(nativeString(approval.payload["message"]) ?? "请填写以下字段") {
            ForEach(propertyNames, id: \.self) { name in
              let property = properties[name] ?? [:]
              let title = nativeString(property["title"]) ?? name
              if nativeString(property["type"]) == "boolean" {
                Toggle(title, isOn: Binding(get: { booleans[name] ?? false }, set: { booleans[name] = $0 }))
              } else if let choices = property["enum"] as? [Any] {
                Picker(title, selection: binding(for: name, in: $values)) {
                  ForEach(choices.compactMap(nativeString), id: \.self) { choice in Text(choice).tag(choice) }
                }
              } else {
                TextField(title, text: binding(for: name, in: $values), prompt: Text(nativeString(property["description"]) ?? ""))
                  .keyboardType(["integer", "number"].contains(nativeString(property["type"]) ?? "") ? .decimalPad : .default)
              }
            }
          }
        }
        if !["item/tool/requestUserInput", "mcpServer/elicitation/request"].contains(approval.method) {
          Section("请求内容") {
            Text(approval.method).font(.subheadline.weight(.semibold))
            if let data = try? JSONSerialization.data(withJSONObject: approval.payload, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
              Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
          }
        }
      }
      .navigationTitle("审批")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("拒绝", role: .cancel) { submit(false) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("允许") { submit(true) }.disabled(!canAccept)
        }
      }
    }
  }

  private var questions: [[String: Any]] { nativeArray(approval.payload["questions"]) }
  private var properties: [String: [String: Any]] {
    guard let schema = nativeDictionary(approval.payload["requestedSchema"]),
          let rawProperties = schema["properties"] as? [String: Any] else {
      return [:]
    }
    return rawProperties.reduce(into: [:]) { result, entry in
      if let property = entry.value as? [String: Any] {
        result[entry.key] = property
      }
    }
  }
  private var propertyNames: [String] { properties.keys.sorted() }
  private var requiredFields: Set<String> { Set((nativeDictionary(approval.payload["requestedSchema"])?["required"] as? [String]) ?? []) }

  private var canAccept: Bool {
    if approval.method == "item/tool/requestUserInput" {
      return questions.allSatisfy { question in
        guard let id = nativeString(question["id"]) else { return false }
        return !(answers[id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      }
    }
    if approval.method == "mcpServer/elicitation/request" && nativeString(approval.payload["mode"]) == "form" {
      return requiredFields.allSatisfy { key in
        nativeString(properties[key]?["type"]) == "boolean" || !(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      }
    }
    return true
  }

  private func binding(for key: String, in values: Binding<[String: String]>) -> Binding<String> {
    Binding(get: { values.wrappedValue[key] ?? "" }, set: { values.wrappedValue[key] = $0 })
  }

  private func submit(_ accepted: Bool) {
    var payload: [String: Any]
    switch approval.method {
    case "item/permissions/requestApproval":
      payload = ["permissions": accepted ? (approval.payload["permissions"] ?? [:]) : [:], "scope": "turn"]
    case "item/tool/requestUserInput":
      let response = Dictionary(uniqueKeysWithValues: answers.compactMap { key, value in
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (key, ["answers": [value]])
      })
      payload = ["answers": response]
    case "mcpServer/elicitation/request":
      var content: [String: Any] = [:]
      for (name, property) in properties {
        let type = nativeString(property["type"])
        if type == "boolean" {
          content[name] = booleans[name] ?? false
        } else if let text = values[name], !text.isEmpty {
          if type == "integer", let number = Int(text) { content[name] = number }
          else if type == "number", let number = Double(text) { content[name] = number }
          else if type == "integer" || type == "number" { continue }
          else { content[name] = text }
        }
      }
      payload = ["action": accepted ? "accept" : "decline"]
      if accepted { payload["content"] = content }
    default:
      payload = ["decision": accepted ? "accept" : "decline"]
    }
    if approval.method == "item/tool/requestUserInput" || approval.method == "mcpServer/elicitation/request" {
      if !accepted { payload = approval.method == "item/tool/requestUserInput" ? ["answers": [:]] : ["action": "decline"] }
    }
    Task { await bridge.respond(to: approval, payload: payload) }
    dismiss()
  }
}

private struct MessageRow: View {
  let message: NativeMessage

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(spacing: 0) {
        Circle()
          .fill(message.role == .user ? Color.black.opacity(0.22) : Color.green)
          .frame(width: 7, height: 7)
          .padding(.top, 6)
        Rectangle()
          .fill(Color.black.opacity(0.10))
          .frame(width: 1)
          .frame(maxHeight: .infinity)
      }
      .frame(width: 9)
      if message.role == .user {
        Spacer(minLength: 12)
        Text(markdown(message.text))
          .font(.system(size: 14))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Text(message.role == .plan ? "Plan" : message.role == .reasoning ? "Reasoning" : "Agent")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
          Text(markdown(message.text))
            .font(.system(size: 14))
            .textSelection(.enabled)
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 3)
  }

  private func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text)) ?? AttributedString(text)
  }
}

private struct MobileDrawer: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  let width: CGFloat
  let close: () -> Void
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Chats")
          .font(.system(size: 22, weight: .semibold))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 15)
      .padding(.top, 18)
      .padding(.bottom, 16)

      if !bridge.projects.isEmpty {
        Menu {
          ForEach(bridge.projects) { project in
            Button {
              bridge.selectedProjectId = project.id
            } label: {
              if project.id == bridge.selectedProjectId { Label(project.label, systemImage: "checkmark") } else { Text(project.label) }
            }
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "folder")
              .font(.system(size: 13, weight: .medium))
            Text(bridge.projects.first(where: { $0.id == bridge.selectedProjectId })?.label ?? "Workspace")
              .font(.system(size: 12, weight: .medium))
              .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .semibold))
          }
          .foregroundStyle(.secondary)
          .padding(.horizontal, 11)
          .frame(minHeight: 36)
          .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 15)
        .padding(.bottom, 17)
      }

      Text("Recent")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .kerning(1.1)
        .padding(.horizontal, 15)
        .padding(.bottom, 7)

      ScrollView {
        LazyVStack(spacing: 0) {
          if bridge.threads.isEmpty {
            Text("暂无聊天")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 15)
              .padding(.vertical, 14)
          } else {
            ForEach(bridge.threads) { thread in
              Button {
                Task {
                  if let projectID = thread.projectId { bridge.selectedProjectId = projectID }
                  await bridge.select(thread)
                  close()
                }
              } label: {
                HStack(alignment: .top, spacing: 9) {
                  Image(systemName: "message.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .padding(.top, 2)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(drawerTitle(for: thread))
                      .font(.system(size: 12, weight: .medium))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    if let preview = thread.preview, !preview.isEmpty {
                      Text(preview)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                      Text(thread.pinned ? "Pinned" : "Chat")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                  }
                  Spacer(minLength: 4)
                  if thread.pinned {
                    Image(systemName: "pin.fill")
                      .font(.system(size: 9))
                      .foregroundStyle(.secondary)
                  }
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .padding(.horizontal, 15)
              .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.055)).frame(height: 1).padding(.leading, 39)
              }
            }
          }
        }
      }

      Spacer(minLength: 0)
      HStack {
        Button {
          Task {
            await bridge.createThread()
            close()
          }
        } label: {
          Label("Chat", systemImage: "square.and.pencil")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建聊天")
        Spacer()
        Button(action: openSettings) {
          Image(systemName: "gearshape")
            .font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38)
            .foregroundStyle(.primary)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置")
      }
      .padding(.horizontal, 15)
      .padding(.top, 12)
      .padding(.bottom, 3)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .frame(width: width)
    .background(Color.white)
    .padding(.top, 0)
  }

  private func drawerTitle(for thread: NativeThread) -> String {
    guard let projectID = thread.projectId,
          let project = bridge.projects.first(where: { $0.id == projectID }) else {
      return thread.title
    }
    return "\(project.label)/\(thread.title)"
  }
}

private struct SettingsView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @Environment(\.dismiss) private var dismiss
  @State private var pairingText = ""
  @State private var showingPairing = false

  var body: some View {
    NavigationView {
      Form {
        Section("连接") {
          HStack { Text("状态"); Spacer(); Text(bridge.status).foregroundStyle(.secondary) }
          if bridge.desktopReady {
            Button("断开并清除配对") { bridge.forget() }
              .foregroundStyle(.red)
          } else {
            Button("连接电脑") { showingPairing = true }
          }
        }
        Section("任务") {
          Picker("模型", selection: Binding(get: { bridge.selectedModel ?? "" }, set: { bridge.selectedModel = $0 })) {
            ForEach(bridge.models) { model in Text(model.label).tag(model.id) }
          }
          if let model = bridge.models.first(where: { $0.id == bridge.selectedModel }), !model.efforts.isEmpty {
            Picker("Reasoning effort", selection: Binding(get: { bridge.selectedEffort ?? "" }, set: { bridge.selectedEffort = $0 })) {
              Text("Default").tag("")
              ForEach(model.efforts, id: \.self) { Text($0).tag($0) }
            }
          }
          Picker("默认模式", selection: $bridge.mode) {
            Text("Default").tag("default")
            Text("Plan").tag("plan")
          }
        }
      }
      .navigationTitle("设置")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
      .sheet(isPresented: $showingPairing) {
        PairingView { raw in
          pairingText = ""
          showingPairing = false
          Task { await bridge.pair(from: raw) }
        }
      }
    }
  }
}

private struct PairingView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var showingScanner = false
  let onPair: (String) -> Void

  var body: some View {
    NavigationView {
      Form {
        Section {
          TextEditor(text: $text).frame(minHeight: 180)
          Button { showingScanner = true } label: { Label("扫描配对二维码", systemImage: "qrcode.viewfinder") }
        } footer: {
          Text("粘贴电脑生成的 pairing.json 内容。连接使用 TLS certificate pinning。")
        }
      }
      .sheet(isPresented: $showingScanner) {
        NavigationView {
          PairingQRScanner { code in
            text = code
            showingScanner = false
          }
          .navigationTitle("扫描配对二维码")
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showingScanner = false } } }
        }
      }
      .navigationTitle("连接电脑")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("连接") { onPair(text); dismiss() }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct ShareFile: Identifiable {
  let id = UUID()
  let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = controller.view
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct PairingQRScanner: UIViewControllerRepresentable {
  let onCode: (String) -> Void

  func makeUIViewController(context: Context) -> QRScannerController {
    let controller = QRScannerController()
    controller.onCode = onCode
    return controller
  }

  func updateUIViewController(_ controller: QRScannerController, context: Context) {
    controller.onCode = onCode
  }
}

private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let capture = AVCaptureSession()
  private var preview: AVCaptureVideoPreviewLayer?
  var onCode: ((String) -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    guard let camera = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: camera),
          capture.canAddInput(input) else {
      showCameraError()
      return
    }
    capture.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard capture.canAddOutput(output) else { showCameraError(); return }
    capture.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]
    let layer = AVCaptureVideoPreviewLayer(session: capture)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    preview = layer
    DispatchQueue.global(qos: .userInitiated).async { [capture] in capture.startRunning() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if capture.isRunning { DispatchQueue.global(qos: .userInitiated).async { [capture] in capture.stopRunning() } }
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
    onCode?(value)
  }

  private func showCameraError() {
    let label = UILabel()
    label.text = "无法启动相机。请检查相机权限。"
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }
}

private struct MobileIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .background(Color.white, in: Circle())
      .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.16), radius: configuration.isPressed ? 3 : 6, y: 2)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
  }
}

private struct LeadingRoundedRectangle: Shape {
  var radius: CGFloat

  var animatableData: CGFloat {
    get { radius }
    set { radius = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let r = min(max(radius, 0), min(rect.width, rect.height) / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

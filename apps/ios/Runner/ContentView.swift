import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @State private var composer = ""
  @State private var showingPairing = false
  @State private var pairingText = ""
  @State private var showingSettings = false
  @State private var showingChats = false
  @State private var shareFile: ShareFile?

  var body: some View {
    NavigationView {
      ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 0) {
          header
          Divider()
          conversation
          composerBar
        }
      }
      .navigationBarHidden(true)
      .sheet(isPresented: $showingChats) { ChatListView() }
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .sheet(item: $shareFile) { value in ActivityView(url: value.url) }
      .sheet(isPresented: $showingPairing) {
        PairingView { raw in
          pairingText = ""
          showingPairing = false
          Task { await bridge.pair(from: raw) }
        }
      }
      .sheet(item: $bridge.approval) { approval in
        NativeApprovalSheet(approval: approval)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button { showingChats = true } label: {
        Image(systemName: "sidebar.left")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 36, height: 36)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(bridge.currentThread?.title ?? "Mobile Codex")
          .font(.headline)
          .lineLimit(1)
        HStack(spacing: 5) {
          Circle().fill(bridge.desktopReady ? .green : .secondary).frame(width: 7, height: 7)
          Text(bridge.desktopReady ? (bridge.running ? "正在运行" : "已连接") : bridge.status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button { showingSettings = true } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 17, weight: .medium))
          .frame(width: 36, height: 36)
      }
      .disabled(!bridge.desktopReady && !bridge.hasCredentials)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .liquidGlass()
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
              action: { showingChats = true }
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
              .liquidGlass()
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
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Menu {
          Picker("模式", selection: $bridge.mode) {
            Text("Default").tag("default")
            Text("Plan").tag("plan")
          }
        } label: {
          Label(bridge.mode == "plan" ? "Plan" : "Default", systemImage: "slider.horizontal.3")
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.borderless)
        Spacer()
        if bridge.running {
          Button { Task { await bridge.interrupt() } } label: {
            Image(systemName: "stop.circle.fill").font(.title3)
          }
          .tint(.red)
        }
      }
      HStack(alignment: .bottom, spacing: 10) {
        TextEditor(text: $composer)
          .frame(minHeight: 38, maxHeight: 112)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onSubmit { submit() }
        Button(action: submit) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 29))
        }
        .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bridge.desktopReady)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(.thinMaterial)
  }

  private func submit() {
    let value = composer
    composer = ""
    Task { await bridge.send(value) }
  }

}

private struct EmptyStateView: View {
  let title: String
  let message: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "link.circle")
        .font(.system(size: 38, weight: .light))
        .foregroundStyle(.secondary)
      Text(title).font(.title3.weight(.semibold))
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(actionTitle, action: action).buttonStyle(.borderedProminent)
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
  private var properties: [String: [String: Any]] { nativeDictionary(nativeDictionary(approval.payload["requestedSchema"])?["properties"]) ?? [:] }
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
      Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
        .foregroundStyle(message.role == .user ? .blue : .purple)
        .font(.title3)
      VStack(alignment: .leading, spacing: 5) {
        Text(message.role == .user ? "你" : message.role == .plan ? "计划" : message.role == .reasoning ? "推理" : "Codex")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(markdown(message.text))
          .font(.body)
          .textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .padding(13)
    .liquidGlass()
  }

  private func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text)) ?? AttributedString(text)
  }
}

private struct ChatListView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      List {
        Section("项目") {
          ForEach(bridge.projects) { project in
            Button {
              bridge.selectedProjectId = project.id
              dismiss()
            } label: {
              Label(project.label, systemImage: project.id == bridge.selectedProjectId ? "checkmark.circle.fill" : "folder")
            }
          }
        }
        Section("聊天") {
          if bridge.threads.isEmpty {
            Text("暂无聊天").foregroundStyle(.secondary)
          }
          ForEach(bridge.threads) { thread in
            Button {
              Task { await bridge.select(thread); dismiss() }
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(thread.title).lineLimit(1)
                if let preview = thread.preview { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
              }
            }
          }
        }
        Section {
          Button {
            Task { await bridge.createThread(); dismiss() }
          } label: {
            Label("新建聊天", systemImage: "plus")
          }
        }
      }
      .navigationTitle("聊天")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
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

private struct LiquidGlassModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    } else {
      content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }
}

private extension View {
  func liquidGlass() -> some View { modifier(LiquidGlassModifier()) }
}

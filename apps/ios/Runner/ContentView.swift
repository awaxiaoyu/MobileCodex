import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
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
          .clipShape(LeadingRoundedRectangle(radius: 20 * drawerProgress))
          .overlay(alignment: .leading) {
            LeadingSeam(radius: 20 * drawerProgress)
              .stroke(Color.white.opacity(0.85 * drawerProgress), style: StrokeStyle(lineWidth: 1, lineCap: .round))
              .shadow(color: .black.opacity(0.08 * drawerProgress), radius: 5, x: -2, y: 0)
          }
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
    NativeChatView(
      onMenu: toggleDrawer,
      onPairing: { showingPairing = true },
      onShareFile: { shareFile = ShareFile(url: $0) }
    )
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
  private func toggleDrawer() {
    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
      drawerProgress = drawerProgress > 0.5 ? 0 : 1
    }
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

private struct MobileDrawer: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  let width: CGFloat
  let close: () -> Void
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Chats")
          .font(.system(size: 23, weight: .semibold))
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
        .tracking(1.1)
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
                      .font(.system(size: 14, weight: .medium))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    if let preview = thread.preview, !preview.isEmpty {
                      Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                      Text(thread.pinned ? "Pinned" : "Chat")
                        .font(.system(size: 12))
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
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .frame(height: 40)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.045), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建聊天")
        Spacer()
        Button(action: openSettings) {
          Image(systemName: "gearshape")
            .font(.system(size: 17, weight: .medium))
            .frame(width: 40, height: 40)
            .foregroundStyle(.primary)
            .background(Color.white, in: Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.075), lineWidth: 1))
            .shadow(color: .black.opacity(0.055), radius: 4, y: 1)
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

private struct LeadingSeam: Shape {
  var radius: CGFloat

  var animatableData: CGFloat {
    get { radius }
    set { radius = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let r = min(max(radius, 0), rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
    path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
    return path
  }
}

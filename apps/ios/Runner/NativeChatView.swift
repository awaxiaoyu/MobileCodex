import SwiftUI

struct NativeChatView: View {
  @EnvironmentObject private var bridge: NativeBridgeClient
  @State private var composer = ""

  let onMenu: () -> Void
  let onPairing: () -> Void
  let onOpenDrawer: () -> Void
  let onShareFile: (URL) -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      conversation
      composerBar
    }
    .background(Color.white)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button(action: onMenu) {
        Image(systemName: "line.3.horizontal")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(NativeIconButtonStyle())
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
        LazyVStack(alignment: .leading, spacing: 20) {
          if !bridge.desktopReady {
            NativeChatEmptyState(
              title: "连接你的电脑",
              message: bridge.notice.isEmpty ? "配对后可以继续 Desktop 上的任务。" : bridge.notice,
              actionTitle: bridge.hasCredentials ? "重新连接" : "开始配对",
              action: {
                if bridge.hasCredentials { Task { await bridge.connect() } } else { onPairing() }
              }
            )
          } else if bridge.currentThread == nil && bridge.messages.isEmpty {
            NativeChatEmptyState(
              title: "开始一个任务",
              message: "选择一个聊天，或直接输入新的任务。",
              actionTitle: "查看聊天",
              action: onOpenDrawer
            )
          } else {
            ForEach(NativeTimelineTurn.project(bridge.messages)) { turn in
              VStack(alignment: .leading, spacing: 16) {
                ForEach(turn.messages) { message in
                  NativeMessageRow(message: message)
                    .id(message.id)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
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
              .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !bridge.artifacts.isEmpty {
              ForEach(bridge.artifacts) { artifact in
                Button {
                  Task {
                    do { onShareFile(try await bridge.download(artifact)) }
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
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        Color.clear.frame(height: 1).id("native-chat-bottom")
      }
      .scrollIndicators(.hidden)
      .onChange(of: bridge.messages.count) { _ in scrollToLatest(proxy) }
      .onChange(of: bridge.messages.last?.text) { _ in proxy.scrollTo("native-chat-bottom", anchor: .bottom) }
    }
  }

  private var composerBar: some View {
    VStack(alignment: .leading, spacing: 5) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $composer)
          .font(.system(size: 16))
          .scrollContentBackground(.hidden)
          .frame(minHeight: 40, maxHeight: 120)
          .padding(.horizontal, 7)
          .padding(.vertical, 5)
        if composer.isEmpty {
          Text(bridge.currentThread == nil ? "Message Codex…" : "Add direction to this task…")
            .font(.system(size: 16))
            .foregroundStyle(Color.black.opacity(0.38))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
        }
      }

      HStack(spacing: 6) {
        Menu {
          Picker("模式", selection: $bridge.mode) {
            Text("Default").tag("default")
            Text("Plan").tag("plan")
          }
        } label: {
          Label(bridge.mode == "plan" ? "Plan" : "Default", systemImage: "route")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)

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
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .frame(maxWidth: 100, minHeight: 44, alignment: .leading)
        }

        Spacer(minLength: 0)
        if bridge.running {
          Button { Task { await bridge.interrupt() } } label: {
            Image(systemName: "stop.fill")
              .font(.system(size: 13, weight: .bold))
              .frame(width: 44, height: 44)
              .background(Color.black, in: Circle())
              .foregroundStyle(.white)
          }
          .accessibilityLabel("停止任务")
        } else {
          Button(action: submit) {
            Image(systemName: "arrow.up")
              .font(.system(size: 15, weight: .bold))
              .frame(width: 44, height: 44)
              .background(Color.black, in: Circle())
              .foregroundStyle(.white)
          }
          .disabled(!canSubmit)
          .opacity(canSubmit ? 1 : 0.35)
          .accessibilityLabel("发送")
        }
      }
      .padding(.horizontal, 5)
    }
    .padding(.horizontal, 11)
    .padding(.top, 7)
    .padding(.bottom, 7)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.black.opacity(0.09)))
    .shadow(color: .black.opacity(0.07), radius: 10, y: 2)
    .padding(.horizontal, 13)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private var canSubmit: Bool {
    !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bridge.desktopReady
  }

  private func submit() {
    let value = composer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, bridge.desktopReady else { return }
    composer = ""
    Task { await bridge.send(value) }
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
      proxy.scrollTo("native-chat-bottom", anchor: .bottom)
    }
  }
}

private struct NativeChatEmptyState: View {
  let title: String
  let message: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "sparkles")
        .font(.system(size: 34, weight: .light))
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
        .frame(minHeight: 40)
        .background(Color.black, in: Capsule())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 90)
  }
}

private struct NativeMessageRow: View {
  let message: NativeMessage

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if message.role == .user {
        Spacer(minLength: 36)
        Text(markdown(message.text))
          .font(.system(size: 16))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .padding(.horizontal, 15)
          .padding(.vertical, 11)
          .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Text(message.role == .plan ? "Plan" : message.role == .reasoning ? "Reasoning" : "Agent")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
          Text(markdown(message.text))
            .font(.system(size: 16))
            .textSelection(.enabled)
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 2)
  }

  private func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text)) ?? AttributedString(text)
  }
}

private struct NativeIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .background(Color.white, in: Circle())
      .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.16), radius: configuration.isPressed ? 3 : 6, y: 2)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
  }
}

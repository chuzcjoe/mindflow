import AppKit
import KeyboardShortcuts
import MindFlowKit
import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.18)
    static let green = Color(red: 0.16, green: 0.40, blue: 0.31)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.44)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
}

struct ContentView: View {
    let controller: DictationController
    private let textInsertion = CursorTextInsertion.shared
    @ViewState private var copied = false

    private var isRecording: Bool { controller.phase == .recording }
    private var canRecord: Bool { [.ready, .recording].contains(controller.phase) }
    private var timerLabel: String {
        let seconds = Int(controller.elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 28) {
                    recordingArea
                    shortcutCard
                    insertionCard
                    if controller.phase == .preparing { preparationCard }
                    if let message = controller.errorMessage { errorCard(message) }
                    transcriptCard
                }
                .padding(.horizontal, 40)
                .padding(.top, 30)
                .padding(.bottom, 30)
            }
            footer
        }
        .frame(minWidth: 580, minHeight: 650)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            textInsertion.refreshPermission()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.green)
            Text("MindFlow")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(controller.phase == .ready || isRecording ? Palette.green : Palette.muted)
                    .frame(width: 6, height: 6)
                Text("本地语音转文字").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.7), in: Capsule())
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1) }
    }

    private var recordingArea: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("把想法，说出来。")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(1)
                Text("普通话 · English · 自动识别")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }

            Text("SenseVoice · 本地快速识别")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.green)

            Button {
                Task { await controller.toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color(red: 0.97, green: 0.89, blue: 0.85) : Palette.green.opacity(0.08))
                        .frame(width: 134, height: 134)
                    Circle()
                        .fill(isRecording ? Color(red: 0.73, green: 0.28, blue: 0.20) : Palette.green)
                        .frame(width: 104, height: 104)
                        .shadow(color: Palette.green.opacity(0.12), radius: 14, y: 6)
                    if controller.phase == .transcribing || controller.phase == .requestingPermission {
                        ProgressView().controlSize(.large).tint(.white)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: isRecording ? 28 : 36, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .opacity(canRecord || controller.phase == .transcribing ? 1 : 0.45)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)
            .accessibilityLabel(isRecording ? "结束录音" : "开始说话")
            .help(isRecording ? "结束录音并转成文字" : "点击开始录音")

            VStack(spacing: 7) {
                Text(buttonCaption).font(.system(size: 15, weight: .semibold))
                Text(isRecording ? "再次点击按钮，结束并转写" : "点击开始，再次点击结束录音")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }

            HStack(spacing: 3) {
                ForEach(Array(controller.audioLevels.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(isRecording ? Palette.green.opacity(0.8) : Palette.green.opacity(0.15))
                        .frame(width: 3, height: isRecording ? 4 + level * 29 : idleBarHeight(index))
                }
            }
            .frame(height: 34)
            .animation(.easeOut(duration: 0.1), value: controller.audioLevels)
            .accessibilityHidden(true)
            .overlay(alignment: .trailing) {
                if isRecording {
                    Text(timerLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .offset(x: 62)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var buttonCaption: String {
        switch controller.phase {
        case .preparing: return "正在准备…"
        case .ready: return "开始说话"
        case .requestingPermission: return "等待麦克风授权…"
        case .recording: return "正在聆听 \(timerLabel)"
        case .transcribing: return "正在转成文字…"
        case .failed: return "模型尚未就绪"
        }
    }

    private func idleBarHeight(_ index: Int) -> Double {
        4 + abs(sin(Double(index) * 0.7)) * 10
    }

    private var canEditShortcut: Bool {
        ![.recording, .requestingPermission, .transcribing].contains(controller.phase)
    }

    private var shortcutCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Label("录音快捷键", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                Text(canEditShortcut ? "点击右侧设置，例如 ⌃⌥空格" : "结束录音和转写后可修改")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                Text("按一次开始，再按一次结束；转写后输入当前光标处。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            ShortcutRecorderControl()
                .disabled(!canEditShortcut)
                .accessibilityLabel("设置开始和结束录音的全局快捷键")
                .help("点击后按下你想使用的组合键。按 Esc 取消，点击 × 清除。")
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ink.opacity(0.07)) }
    }

    private var insertionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("快捷键自动输入", systemImage: "character.cursor.ibeam")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if textInsertion.permissionGranted {
                    Label("已授权", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.green)
                } else {
                    Button("开启辅助功能权限") { textInsertion.requestPermission() }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                }
            }
            Text("在目标文本框中用快捷键结束录音，转写完成后自动输入。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            if !textInsertion.permissionGranted {
                Text("在系统隐私设置中允许 MindFlow 使用辅助功能，才能向其他应用粘贴文字。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }
            if let message = textInsertion.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.green)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ink.opacity(0.07)) }
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(controller.preparationMessage).font(.system(size: 12))
                Spacer(minLength: 0)
                if let progress = controller.downloadProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                }
            }
            if let progress = controller.downloadProgress {
                ProgressView(value: progress).tint(Palette.green)
            }
            Text("准备完成后即可使用，之后无需重复下载。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .background(Palette.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if controller.phase == .failed {
                Button("重新准备模型") { Task { await controller.prepare() } }
                    .buttonStyle(.bordered)
            }
            if controller.needsMicrophonePermission {
                Button("打开麦克风设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(Color(red: 0.65, green: 0.26, blue: 0.17))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("识别结果", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if let seconds = controller.lastTranscriptionSeconds {
                    Text("\(seconds, specifier: "%.2f") 秒")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .padding(.trailing, 8)
                }
                if !controller.transcript.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(controller.transcript, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.green)
                }
            }
            .padding(.bottom, 18)
            if controller.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.phase == .transcribing ? "正在整理你刚才说的话…" : "你的话，会出现在这里。")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.muted.opacity(0.7))
                    Text("转写完成后，自动复制到剪贴板。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted.opacity(0.65))
                }
            } else {
                Text(controller.transcript)
                    .font(.system(size: 17))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("转写完成后已自动复制，可直接粘贴。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.green)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.ink.opacity(0.07)) }
        .onChange(of: controller.transcript) { _, _ in copied = false }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield")
            Text("语音仅在本机处理，录音在转写后自动删除")
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted)
        .padding(.bottom, 18)
        .padding(.top, 8)
    }
}

private struct ShortcutRecorderControl: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        KeyboardShortcuts.RecorderCocoa(for: .toggleRecording)
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        // Explicitly forward the SwiftUI state to the native field so the
        // combination cannot be changed while it is needed to stop recording.
        nsView.isEnabled = context.environment.isEnabled
    }
}

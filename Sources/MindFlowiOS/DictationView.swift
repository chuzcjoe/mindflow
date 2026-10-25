import MindFlowKit
import SwiftUI
import UIKit

private enum Colors {
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.19)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.44)
    static let green = Color(red: 0.18, green: 0.43, blue: 0.33)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
}

struct DictationView: View {
    let controller: DictationController
    var usesSampleAudio = false
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    private var isRecording: Bool { controller.phase == .recording }
    private var canRecord: Bool { controller.phase == .ready || isRecording }
    private var timeLabel: String {
        let seconds = Int(controller.elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                #if DEBUG
                if usesSampleAudio {
                    Label("模拟器样本测试 · 使用音频文件作为输入", systemImage: "testtube.2")
                        .font(.caption2)
                        .foregroundStyle(Colors.green)
                }
                #endif
                recordingCard
                if controller.phase == .preparing { preparationCard }
                if let message = controller.errorMessage { errorCard(message) }
                transcriptCard
                Label("语音在本机处理，转写后删除临时录音", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(Colors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Colors.paper.ignoresSafeArea())
        .foregroundStyle(Colors.ink)
        .tint(Colors.green)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack {
            Label("MindFlow", systemImage: "waveform")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Colors.green)
            Spacer()
            Text("本地语音转文字")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Colors.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private var recordingCard: some View {
        VStack(spacing: 17) {
            Text("把想法，说出来。")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .padding(.top, 12)
            Text("普通话 · English · 自动识别")
                .font(.subheadline)
                .foregroundStyle(Colors.muted)

            Button {
                Task { await controller.toggleRecording() }
            } label: {
                ZStack {
                    Circle().fill(isRecording ? Color.orange.opacity(0.12) : Colors.green.opacity(0.08))
                        .frame(width: 150, height: 150)
                    Circle().fill(isRecording ? Color(red: 0.73, green: 0.28, blue: 0.20) : Colors.green)
                        .frame(width: 116, height: 116)
                        .shadow(color: Colors.green.opacity(0.15), radius: 14, y: 7)
                    if controller.phase == .transcribing || controller.phase == .requestingPermission {
                        ProgressView().tint(.white).scaleEffect(1.3)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: isRecording ? 30 : 40, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .opacity(canRecord || controller.phase == .transcribing ? 1 : 0.45)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)
            .accessibilityLabel(isRecording ? "结束录音" : "开始说话")
            .accessibilityHint(isRecording ? "结束后自动显示识别文字" : "再次点击结束录音")
            .accessibilityIdentifier("recordButton")
            .padding(.vertical, 7)

            VStack(spacing: 7) {
                Text(statusLabel).font(.headline).accessibilityIdentifier("recordingStatus")
                Text(isRecording ? "再次点击，结束并转成文字" : "点击开始，再次点击结束录音")
                    .font(.caption)
                    .foregroundStyle(Colors.muted)
            }

            HStack(spacing: 4) {
                ForEach(Array(controller.audioLevels.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(Colors.green.opacity(isRecording ? 0.8 : 0.18))
                        .frame(width: 3, height: isRecording ? 4 + level * 28 : 4 + abs(sin(Double(index) * 0.7)) * 10)
                }
            }
            .frame(height: 34)
            .animation(.easeOut(duration: 0.1), value: controller.audioLevels)
            .accessibilityHidden(true)

            Text("SenseVoice · 离线识别")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Colors.green)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLabel: String {
        switch controller.phase {
        case .preparing: return "正在准备模型…"
        case .ready: return "开始说话"
        case .requestingPermission: return "等待麦克风授权…"
        case .recording: return "正在聆听 \(timeLabel)"
        case .transcribing: return "正在转成文字…"
        case .failed: return "模型尚未就绪"
        }
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ProgressView().controlSize(.small)
                Text(controller.preparationMessage)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let progress = controller.downloadProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                }
            }
            if let progress = controller.downloadProgress { ProgressView(value: progress) }
            Text("首次需要下载约 239 MB，之后可离线使用。")
                .font(.caption2)
                .foregroundStyle(Colors.muted)
        }
        .padding(16)
        .background(Colors.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if controller.phase == .failed {
                Button("重新准备模型") { Task { await controller.prepare() } }
                    .buttonStyle(.bordered)
            }
            if controller.needsMicrophonePermission {
                Button("打开麦克风设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(Color(red: 0.65, green: 0.26, blue: 0.17))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("识别结果", systemImage: "text.alignleft").font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if let seconds = controller.lastTranscriptionSeconds {
                    Text("\(seconds, specifier: "%.2f") 秒").font(.caption.monospacedDigit())
                }
                if !controller.transcript.isEmpty {
                    Button {
                        UIPasteboard.general.string = controller.transcript
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Colors.green)
                    .accessibilityLabel(copied ? "已复制" : "复制识别结果")
                }
            }
            .foregroundStyle(Colors.muted)
            if controller.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.phase == .transcribing ? "正在整理你刚才说的话…" : "你的话，会出现在这里。")
                        .font(.body)
                    Text("转写完成后，自动复制到剪贴板。")
                        .font(.caption)
                }
                .foregroundStyle(Colors.muted.opacity(0.8))
            } else {
                Text(controller.transcript)
                    .font(.body)
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("transcriptText")
                Text("转写完成后已自动复制，可直接粘贴。")
                    .font(.caption2)
                    .foregroundStyle(Colors.green)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(20)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Colors.ink.opacity(0.06)) }
        .onChange(of: controller.transcript) { _, _ in copied = false }
    }
}

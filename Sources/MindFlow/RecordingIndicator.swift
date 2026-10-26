import AppKit
import MindFlowKit
import SwiftUI

@MainActor
protocol RecordingIndicatorPresenting: AnyObject {
    func show(for controller: DictationController)
    func hide()
}

/// A click-through panel: showing it must preserve the destination app's focus.
@MainActor
final class RecordingIndicator: NSObject, RecordingIndicatorPresenting {
    private var panel: RecordingIndicatorPanel?
    private var screen: NSScreen?
    private let panelSize = NSSize(width: 348, height: 96)

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show(for controller: DictationController) {
        guard controller.phase == .recording else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        let pointer = NSEvent.mouseLocation
        screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        panel.contentView = NSHostingView(rootView: RecordingIndicatorView(controller: controller))
        positionPanel()
        // Show above other apps without making the panel key or activating MindFlow.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        screen = nil
    }

    private func makePanel() -> RecordingIndicatorPanel {
        let panel = RecordingIndicatorPanel(contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "MindFlow 录音提示"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let availableScreens = NSScreen.screens
        let target = availableScreens.first { $0 == screen } ?? NSScreen.main ?? availableScreens.first
        guard let target else { return }
        screen = target
        let visible = target.visibleFrame
        panel.setFrame(NSRect(x: visible.midX - panelSize.width / 2,
            y: visible.minY + 12, width: panelSize.width, height: panelSize.height), display: true)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        if panel?.isVisible == true { positionPanel() }
    }
}

private final class RecordingIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct RecordingIndicatorView: View {
    let controller: DictationController
    private let mint = Color(red: 0.57, green: 0.91, blue: 0.73)

    private var time: String {
        let seconds = Int(controller.elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mint)
                .frame(width: 30, height: 30)
                .background(mint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("正在聆听")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("再次按快捷键结束")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(Array(controller.audioLevels.suffix(15).enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(mint)
                        .frame(width: 2, height: 4 + min(1, max(0, level)) * 23)
                }
            }
            .frame(width: 72, height: 28)
            .animation(.easeOut(duration: 0.09), value: controller.audioLevels)
            Text(time)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .frame(minWidth: 34)
        }
        .padding(.horizontal, 16)
        .frame(width: 316, height: 60)
        .background {
            Capsule().fill(LinearGradient(colors: [
                Color(red: 0.13, green: 0.17, blue: 0.15),
                Color(red: 0.055, green: 0.075, blue: 0.065),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        .frame(width: 348, height: 96)
        .preferredColorScheme(.dark)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MindFlow 正在录音，\(time)，再次按快捷键结束")
    }
}

import AppKit
import ApplicationServices
import Observation

/// macOS-only delivery of a successful shortcut recording to its input field.
/// The speech engine and iOS app do not depend on accessibility or key events.
@MainActor @Observable
final class CursorTextInsertion {
    typealias Completion = @MainActor (String) async -> Void

    struct Target {
        let isStillFocused: @MainActor () -> Bool
        let paste: @MainActor () -> Bool
    }

    static let shared = CursorTextInsertion()

    private(set) var permissionGranted = false
    private(set) var statusMessage: String?

    @ObservationIgnored private let clipboard: NSPasteboard
    @ObservationIgnored private let hasPermission: @MainActor () -> Bool
    @ObservationIgnored private let captureTarget: @MainActor () -> Target?
    @ObservationIgnored private let waitForKeyRelease: @MainActor () async throws -> Void
    @ObservationIgnored private var copiedText: String?
    @ObservationIgnored private var clipboardRevision: Int?

    init(
        clipboard: NSPasteboard = .general,
        hasPermission: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() && CGPreflightPostEventAccess() },
        captureTarget: @escaping @MainActor () -> Target? = { CursorTextInsertion.captureFocusedTarget() },
        waitForKeyRelease: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(120))
        }
    ) {
        self.clipboard = clipboard
        self.hasPermission = hasPermission
        self.captureTarget = captureTarget
        self.waitForKeyRelease = waitForKeyRelease
        refreshPermission()
    }

    func refreshPermission() {
        permissionGranted = hasPermission()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    /// Called by the shared controller for button and shortcut recordings alike.
    func copy(_ text: String) {
        statusMessage = nil
        copiedText = nil
        clipboardRevision = nil
        clipboard.clearContents()
        if clipboard.setString(text, forType: .string) {
            copiedText = text
            clipboardRevision = clipboard.changeCount
        } else {
            statusMessage = "文字已识别，但复制失败，请点击复制重试。"
        }
    }

    /// Capture the destination BEFORE awaiting recognition. Returning a completion
    /// keeps the destination local to this recording and avoids stale paste jobs.
    func prepareInsertion() -> Completion {
        refreshPermission()
        guard permissionGranted else {
            return messageCompletion("文字已复制。允许辅助功能权限后，快捷键结束录音即可自动输入。")
        }
        guard let target = captureTarget() else {
            return messageCompletion("文字已复制。未找到可输入的位置，请先点击目标文本框。")
        }
        return { [weak self] text in
            guard let self else { return }
            let revision = self.clipboardRevision
            do { try await self.waitForKeyRelease() }
            catch { return }
            guard !Task.isCancelled else { return }
            self.refreshPermission()
            guard self.permissionGranted else {
                self.statusMessage = "文字已复制。自动输入需要辅助功能权限。"
                return
            }
            guard target.isStillFocused() else {
                self.statusMessage = "输入位置已改变，文字已保留在剪贴板，可手动粘贴。"
                return
            }
            guard !text.isEmpty, self.copiedText == text,
                  let revision, self.clipboardRevision == revision,
                  self.clipboard.changeCount == revision else {
                self.statusMessage = "剪贴板内容已改变，未自动粘贴。识别文字仍在下方。"
                return
            }
            self.statusMessage = target.paste()
                ? "已输入到当前光标处，文字同时保留在剪贴板。"
                : "文字已复制，自动输入未完成，可手动粘贴。"
        }
    }

    private func messageCompletion(_ message: String) -> Completion {
        { [weak self] _ in self?.statusMessage = message }
    }

    private static func captureFocusedTarget() -> Target? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        guard let element = focusedElement(in: appElement) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard stringAttribute(element, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String) else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute)
        let textRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].map { $0 as String }
        var selectedTextSettable = DarwinBoolean(false)
        let supportsSelection = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &selectedTextSettable
        ) == .success && selectedTextSettable.boolValue
        guard role.map(textRoles.contains) == true || supportsSelection else { return nil }

        let pid = application.processIdentifier
        return Target(
            isStillFocused: {
                guard !application.isTerminated,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      let current = focusedElement(in: appElement) else { return false }
                return CFEqual(current, element)
                    && stringAttribute(current, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String)
            },
            paste: {
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
                // Cmd+V only: never send Return or submit the destination form.
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(pid)
                up.postToPid(pid)
                return true
            }
        )
    }

    private static func focusedElement(in application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

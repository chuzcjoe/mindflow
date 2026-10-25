import AppKit
import Testing
@testable import MindFlow

@Suite @MainActor
struct CursorTextInsertionTests {
    @Test
    func testSuccessfulInsertionUsesCopiedTextAndKeepsClipboard() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var pastes = 0
        let output = CursorTextInsertion(clipboard: board, hasPermission: { true }, captureTarget: {
            .init(isStillFocused: { true }, paste: { pastes += 1; return true })
        }, waitForKeyRelease: {})
        let completion = output.prepareInsertion()
        output.copy("在光标处输入。")
        await completion("在光标处输入。")
        #expect(pastes == 1)
        #expect(board.string(forType: .string) == "在光标处输入。")
    }

    @Test
    func testFocusChangeWhileWaitingPreventsPaste() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var focused = true
        var pastes = 0
        let output = CursorTextInsertion(clipboard: board, hasPermission: { true }, captureTarget: {
            .init(isStillFocused: { focused }, paste: { pastes += 1; return true })
        }, waitForKeyRelease: { focused = false })
        let completion = output.prepareInsertion()
        output.copy("保留这段文字")
        await completion("保留这段文字")
        #expect(pastes == 0)
        #expect(board.string(forType: .string) == "保留这段文字")
        #expect(output.statusMessage != nil)
    }

    @Test
    func testChangedClipboardIsNeverPastedOrOverwritten() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var pastes = 0
        let output = CursorTextInsertion(clipboard: board, hasPermission: { true }, captureTarget: {
            .init(isStillFocused: { true }, paste: { pastes += 1; return true })
        }, waitForKeyRelease: {
            board.clearContents()
            board.setString("用户刚复制的新内容", forType: .string)
        })
        let completion = output.prepareInsertion()
        output.copy("识别结果")
        await completion("识别结果")
        #expect(pastes == 0)
        #expect(board.string(forType: .string) == "用户刚复制的新内容")
    }

    @Test
    func testMissingPermissionDoesNotInspectOtherApps() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var captures = 0
        let output = CursorTextInsertion(clipboard: board, hasPermission: { false }, captureTarget: {
            captures += 1
            return nil
        }, waitForKeyRelease: {})
        let completion = output.prepareInsertion()
        output.copy("仍然可以手动粘贴")
        await completion("仍然可以手动粘贴")
        #expect(!output.permissionGranted)
        #expect(captures == 0)
        #expect(board.string(forType: .string) == "仍然可以手动粘贴")
        #expect(output.statusMessage != nil)
    }

    @Test
    func testPermissionRevokedAfterRecordingPreventsPaste() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var permitted = true
        var pastes = 0
        let output = CursorTextInsertion(clipboard: board, hasPermission: { permitted }, captureTarget: {
            .init(isStillFocused: { true }, paste: { pastes += 1; return true })
        }, waitForKeyRelease: { permitted = false })
        let completion = output.prepareInsertion()
        output.copy("识别结果")
        await completion("识别结果")
        #expect(pastes == 0)
        #expect(!output.permissionGranted)
    }
}

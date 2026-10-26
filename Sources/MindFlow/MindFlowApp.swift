import AppKit
import KeyboardShortcuts
import MindFlowKit
import SwiftUI

@main
struct MindFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var controller = DictationController(onTranscription: { text in
        CursorTextInsertion.shared.copy(text)
    })

    var body: some Scene {
        Window("MindFlow", id: "main") {
            ContentView(controller: controller)
                .onAppear { appDelegate.connect(to: controller) }
                .task { await controller.prepare() }
        }
        .defaultSize(width: 700, height: 850)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?
    private let recordingIndicator = RecordingIndicator()
    private lazy var shortcut = RecordingShortcutHandler(recordingIndicator: recordingIndicator, prepareInsertion: {
        CursorTextInsertion.shared.prepareInsertion()
    })

    func connect(to controller: DictationController) {
        self.controller = controller
        shortcut.connect(to: controller)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardShortcuts.removeAllHandlers()
        shortcut.disconnect()
        controller?.shutDown()
    }
}

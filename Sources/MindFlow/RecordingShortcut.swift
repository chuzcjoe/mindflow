import KeyboardShortcuts
import MindFlowKit

extension KeyboardShortcuts.Name {
    // No initial binding: the user chooses a combination that fits their setup.
    // The stable name lets KeyboardShortcuts restore the choice on every launch.
    static let toggleRecording = Self("toggleRecording")
}

@MainActor
final class RecordingShortcutHandler {
    typealias Action = @MainActor () async -> Void
    typealias Registrar = (@escaping Action) -> Void
    typealias Insertion = @MainActor (String) async -> Void

    private let register: Registrar
    private let prepareInsertion: @MainActor () -> Insertion?
    private weak var controller: DictationController?
    private var isConnected = false

    init(prepareInsertion: @escaping @MainActor () -> Insertion? = { nil }, register: @escaping Registrar = { action in
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            Task { @MainActor in await action() }
        }
    }) {
        self.register = register
        self.prepareInsertion = prepareInsertion
    }

    func connect(to controller: DictationController) {
        self.controller = controller
        // A window can appear again. Keep one native listener, and route it to
        // the latest controller without retaining a closed window's state.
        guard !isConnected else { return }
        isConnected = true
        register { [weak self] in
            guard let self, let controller = self.controller else { return }
            let isStopping = controller.phase == .recording
            let insertion = isStopping ? self.prepareInsertion() : nil
            await controller.toggleRecording()
            guard isStopping, self.controller === controller,
                  controller.phase == .ready, controller.errorMessage == nil else { return }
            await insertion?(controller.transcript)
        }
    }
}

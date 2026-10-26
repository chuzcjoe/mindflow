import Foundation
import KeyboardShortcuts
import MindFlowKit
import Observation

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
    private let recordingIndicator: (any RecordingIndicatorPresenting)?
    private var indicatorSessionID: UUID?
    private weak var controller: DictationController?
    private var isConnected = false

    init(recordingIndicator: (any RecordingIndicatorPresenting)? = nil,
         prepareInsertion: @escaping @MainActor () -> Insertion? = { nil }, register: @escaping Registrar = { action in
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            Task { @MainActor in await action() }
        }
    }) {
        self.register = register
        self.prepareInsertion = prepareInsertion
        self.recordingIndicator = recordingIndicator
    }

    func connect(to controller: DictationController) {
        if self.controller !== controller { hideRecordingIndicator() }
        self.controller = controller
        // A window can appear again. Keep one native listener, and route it to
        // the latest controller without retaining a closed window's state.
        guard !isConnected else { return }
        isConnected = true
        register { [weak self] in
            guard let self, let controller = self.controller else { return }
            let isStarting = controller.phase == .ready
            let isStopping = controller.phase == .recording
            let insertion = isStopping ? self.prepareInsertion() : nil
            if isStopping { self.hideRecordingIndicator() }
            await controller.toggleRecording()
            guard self.controller === controller else { return }
            if isStarting, controller.phase == .recording {
                self.showRecordingIndicator(for: controller)
            }
            guard isStopping,
                  controller.phase == .ready, controller.errorMessage == nil else { return }
            await insertion?(controller.transcript)
        }
    }

    func disconnect() {
        hideRecordingIndicator()
        controller = nil
    }

    private func showRecordingIndicator(for controller: DictationController) {
        guard let recordingIndicator else { return }
        hideRecordingIndicator()
        let sessionID = UUID()
        indicatorSessionID = sessionID
        // Also dismiss when the app button stops capture, capture fails, or the
        // session is cancelled. A stale observer must not dismiss a new session.
        withObservationTracking {
            _ = controller.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.indicatorSessionID == sessionID else { return }
                self?.hideRecordingIndicator()
            }
        }
        recordingIndicator.show(for: controller)
    }

    private func hideRecordingIndicator() {
        guard indicatorSessionID != nil else { return }
        indicatorSessionID = nil
        recordingIndicator?.hide()
    }
}

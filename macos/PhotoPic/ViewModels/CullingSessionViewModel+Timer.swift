import Foundation

extension CullingSessionViewModel {
    package var formattedSessionDuration: String {
        session.metadata.formattedDuration(at: timerNow)
    }

    package func startSessionTimerManual(at now: Date = Date()) {
        session.metadata.startManual(at: now)
        timerNow = now
        SessionMetadataStore.save(session.metadata, for: session.directoryURL)
        syncTimerTicker()
    }

    package func stopAndFinishSessionTimer(at now: Date = Date()) {
        session.metadata.stopAndFinish(at: now)
        timerNow = now
        SessionMetadataStore.save(session.metadata, for: session.directoryURL)
        cancelTimerTicker()
    }

    package func resetSessionTimer() {
        session.metadata.resetTimer()
        timerNow = Date()
        SessionMetadataStore.save(session.metadata, for: session.directoryURL)
        cancelTimerTicker()
    }

    package func handleFirstShotTimerAutoStartIfNeeded(capturedAt: Date, now: Date = Date()) {
        guard autoStartTimerOnFirstShot, session.metadata.hasNeverStartedTimer else { return }
        session.metadata.autoStartFromFirstShot(capturedAt: capturedAt, now: now)
        timerNow = now
        SessionMetadataStore.save(session.metadata, for: session.directoryURL)
        syncTimerTicker()
    }

    package func syncTimerTicker() {
        guard session.metadata.isTimerRunning else {
            cancelTimerTicker()
            return
        }
        guard timerTickTask == nil else { return }
        timerNow = Date()
        timerTickTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.session.metadata.isTimerRunning {
                self.timerNow = Date()
                try? await Task.sleep(for: .seconds(1))
            }
            self?.timerTickTask = nil
        }
    }

    package func cancelTimerTicker() {
        timerTickTask?.cancel()
        timerTickTask = nil
    }
}

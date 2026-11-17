import AVFoundation

/// Sagt "Schneller" oder "Langsamer" über die aktuelle Audio-Ausgabe (AirPods).
///
/// Wichtig für den gesperrten Bildschirm: iOS erlaubt einer App im Hintergrund nicht,
/// ihre Audio-Ausgabe neu einzuschalten. Deshalb wird die Audio-Session beim Start
/// (im Vordergrund) aktiviert und bleibt bis zum Stopp aktiv. Für die Ansagen wird
/// nur die Musik kurz leiser gestellt, die Session selbst bleibt an.
@MainActor
final class VoiceCoach: NSObject, ObservableObject {
    /// Für die Anzeige in der App: was zuletzt gesagt wurde bzw. was schiefging.
    @Published private(set) var lastAnnouncement: String?
    @Published private(set) var lastAnnouncementDate: Date?
    @Published private(set) var lastError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpoken: Date = .distantPast
    private var sessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: - Session

    /// Beim Tippen auf Start aufrufen – also solange die App im Vordergrund ist.
    func beginSession() {
        do {
            try configure(duck: false)
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActive = true
        } catch {
            record("Audio-Start", error)
        }
    }

    func endSession() {
        sessionActive = false
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configure(duck: Bool) throws {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if duck { options.insert(.duckOthers) }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: options)
    }

    /// Anruf, Siri o. Ä. haben die Audio-Ausgabe unterbrochen – danach wieder einschalten.
    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended
        else { return }
        Task { @MainActor in
            guard self.sessionActive else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                self.record("Nach Unterbrechung", error)
            }
        }
    }

    // MARK: - Ansagen

    /// Prüft den Puls gegen den Zielbereich. Gesprochen wird höchstens alle `interval` Sekunden.
    func evaluate(bpm: Double, low: Int, high: Int, interval: TimeInterval) {
        let text: String
        if bpm < Double(low) {
            text = "Schneller"
        } else if bpm > Double(high) {
            text = "Langsamer"
        } else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastSpoken) >= interval else { return }
        lastSpoken = now
        speak(text)
    }

    func reset() {
        lastSpoken = .distantPast
        lastAnnouncement = nil
        lastAnnouncementDate = nil
        lastError = nil
    }

    func speak(_ text: String) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Musik leiser stellen. Schlägt das fehl, wird trotzdem gesprochen –
            // nur eben über die laute Musik.
            try configure(duck: true)
            try audioSession.setActive(true)
        } catch {
            record("Musik leiser", error)
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)

        lastAnnouncement = text
        lastAnnouncementDate = Date()
    }

    private func finishedSpeaking() {
        if sessionActive {
            // Session bleibt an (sonst darf sie im Hintergrund nicht wieder starten),
            // nur das Leiserstellen der Musik wird aufgehoben.
            do {
                try configure(duck: false)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                record("Musik wieder laut", error)
            }
        } else {
            // Nur "Stimme testen" ohne laufende Session: Audio ganz abgeben.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func record(_ step: String, _ error: Error) {
        let time = Date().formatted(date: .omitted, time: .standard)
        lastError = "\(time) – \(step): \(error.localizedDescription)"
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishedSpeaking()
        }
    }
}

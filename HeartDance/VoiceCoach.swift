import AVFoundation

/// Sagt "Schneller" oder "Langsamer" über die aktuelle Audio-Ausgabe (AirPods).
/// Laufende Musik wird dabei kurz leiser gestellt.
@MainActor
final class VoiceCoach: NSObject, ObservableObject {
    /// Für die Anzeige in der App: was zuletzt gesagt wurde bzw. was schiefging.
    @Published private(set) var lastAnnouncement: String?
    @Published private(set) var lastAnnouncementDate: Date?
    @Published private(set) var lastError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpoken: Date = .distantPast

    override init() {
        super.init()
        synthesizer.delegate = self
    }

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
            // .duckOthers macht die Session "mischbar" – nur so darf sie auch im
            // Hintergrund (Bildschirm gesperrt) aktiviert werden.
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audioSession.setActive(true)
            lastError = nil
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
        }

        // Falls eine alte Ansage hängen geblieben ist, nicht ewig blockieren.
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
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Musik wieder auf normale Lautstärke bringen.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

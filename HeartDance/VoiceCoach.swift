import AVFoundation

/// Sagt "Schneller" oder "Langsamer" über die aktuelle Audio-Ausgabe (AirPods).
/// Laufende Musik wird dabei kurz leiser gestellt.
@MainActor
final class VoiceCoach: NSObject {
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
        guard now.timeIntervalSince(lastSpoken) >= interval, !synthesizer.isSpeaking else { return }
        lastSpoken = now
        speak(text)
    }

    func reset() {
        lastSpoken = .distantPast
    }

    func speak(_ text: String) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio-Session-Fehler: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Musik wieder auf normale Lautstärke bringen.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

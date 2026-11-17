import AVFoundation

/// Sagt "Schneller" oder "Langsamer" über die aktuelle Audio-Ausgabe (AirPods).
///
/// Warum so aufwendig: Bei gesperrtem Bildschirm darf eine App keine *neue* Audio-Wiedergabe
/// starten (Fehler "Failed to start audio queue"). Deshalb:
/// 1. Die Ansagen werden im Vordergrund einmal als fertige Tonschnipsel erzeugt.
/// 2. Beim Start läuft ein eigener Audio-Player los, der bis zum Stopp ununterbrochen
///    weiterläuft (zwischen den Ansagen spielt er Stille).
/// 3. Im Hintergrund wird nur noch ein fertiger Schnipsel in diesen Player gelegt.
/// Musik (Spotify) läuft parallel weiter und wird nicht leiser gestellt.
@MainActor
final class VoiceCoach: NSObject, ObservableObject {
    /// Für die Anzeige in der App: was zuletzt gesagt wurde bzw. was schiefging.
    @Published private(set) var lastAnnouncement: String?
    @Published private(set) var lastAnnouncementDate: Date?
    @Published private(set) var lastError: String?

    private static let phrases = ["Schneller", "Langsamer", "Los geht's"]
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()

    private var rendered: [String: AVAudioPCMBuffer] = [:]
    private var renderQueue: [String] = []
    private var isRendering = false

    private var lastSpoken: Date = .distantPast
    private var sessionActive = false

    override init() {
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: AVAudioSession.sharedInstance())
        center.addObserver(self, selector: #selector(handleEngineConfigurationChange(_:)),
                           name: .AVAudioEngineConfigurationChange,
                           object: engine)

        renderQueue = Self.phrases
        renderNext()
    }

    // MARK: - Session

    /// Beim Tippen auf Start aufrufen – also solange die App im Vordergrund ist.
    func beginSession() {
        sessionActive = true
        startAudio()
    }

    func endSession() {
        sessionActive = false
        stopAudio()
    }

    private func startAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers])
            try audioSession.setActive(true)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            record("Audio-Start", error)
        }
    }

    private func stopAudio() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Anruf, Siri o. Ä. haben die Audio-Ausgabe unterbrochen – danach wieder einschalten.
    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended
        else { return }
        Task { @MainActor in
            if self.sessionActive { self.startAudio() }
        }
    }

    /// Z. B. AirPods raus/rein: Die Audio-Engine stoppt dann und muss neu starten.
    @objc nonisolated private func handleEngineConfigurationChange(_ notification: Notification) {
        Task { @MainActor in
            if self.sessionActive { self.startAudio() }
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
        lastAnnouncement = text
        lastAnnouncementDate = Date()

        guard let buffer = rendered[text] else {
            // Schnipsel noch nicht fertig (nur direkt nach App-Start möglich):
            // direkt sprechen – klappt im Vordergrund.
            speakDirectly(text)
            return
        }

        if !engine.isRunning || !player.isPlaying {
            startAudio()
        }

        let keepRunning = sessionActive
        player.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            // Für "Stimme testen" ohne laufende Session: Audio danach wieder abgeben.
            guard !keepRunning else { return }
            Task { @MainActor in
                guard let self, !self.sessionActive else { return }
                self.stopAudio()
            }
        }
    }

    private func speakDirectly(_ text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            record("Direkte Ansage", error)
        }
        synthesizer.speak(Self.makeUtterance(text))
    }

    private func record(_ step: String, _ error: Error) {
        let time = Date().formatted(date: .omitted, time: .standard)
        lastError = "\(time) – \(step): \(error.localizedDescription)"
    }

    // MARK: - Tonschnipsel erzeugen

    private static func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        return utterance
    }

    private func renderNext() {
        guard !isRendering, !renderQueue.isEmpty else { return }
        isRendering = true
        let text = renderQueue.removeFirst()

        var parts: [AVAudioPCMBuffer] = []
        synthesizer.write(Self.makeUtterance(text)) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength > 0 {
                if let copy = Self.copy(pcm) { parts.append(copy) }
                return
            }
            // Ein leerer Puffer bedeutet: fertig.
            let finished = parts
            Task { @MainActor in
                self?.finishRendering(text, parts: finished)
            }
        }
    }

    private func finishRendering(_ text: String, parts: [AVAudioPCMBuffer]) {
        if let buffer = Self.convert(parts, to: playbackFormat) {
            rendered[text] = buffer
        } else {
            lastError = "Ansage „\(text)“ konnte nicht vorbereitet werden."
        }
        isRendering = false
        renderNext()
    }

    private nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, target) {
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
    }

    /// Fügt die Teile zusammen und wandelt sie ins Abspielformat um.
    private static func convert(_ parts: [AVAudioPCMBuffer], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let first = parts.first,
              let converter = AVAudioConverter(from: first.format, to: format)
        else { return nil }

        let totalFrames = parts.reduce(0) { $0 + Int($1.frameLength) }
        let ratio = format.sampleRate / first.format.sampleRate
        let capacity = AVAudioFrameCount(Double(totalFrames) * ratio) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var index = 0
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard index < parts.count else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            let part = parts[index]
            index += 1
            inputStatus.pointee = .haveData
            return part
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

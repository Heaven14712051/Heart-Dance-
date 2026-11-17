import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = HeartRateMonitor()
    @StateObject private var coach = VoiceCoach()
    @State private var liveActivity = LiveActivityController()

    @AppStorage("lowBPM") private var lowBPM = 120
    @AppStorage("highBPM") private var highBPM = 130
    @AppStorage("announceInterval") private var announceInterval = 10
    @AppStorage("useSiri") private var useSiri = false

    private enum Field { case low, high }
    @FocusState private var focusedField: Field?
    @State private var lowText = ""
    @State private var highText = ""
    @State private var inputError: String?

    private let allowedRange = 40...220

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    heartRateDisplay
                }

                Section {
                    bpmRow(title: "Minimum", text: $lowText, field: .low,
                           value: $lowBPM, range: allowedRange.lowerBound...(highBPM - 1))
                    bpmRow(title: "Maximum", text: $highText, field: .high,
                           value: $highBPM, range: (lowBPM + 1)...allowedRange.upperBound)
                } header: {
                    Text("Zielbereich")
                } footer: {
                    if let inputError {
                        Text(inputError).foregroundStyle(.red)
                    } else {
                        Text("Zahl antippen zum Eintippen, oder mit +/− ändern.")
                    }
                }

                Section {
                    Picker("Ansage über", selection: $useSiri) {
                        Text("App-Stimme").tag(false)
                        Text("Siri").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Höchstens alle \(announceInterval) s", value: $announceInterval, in: 3...60, step: 1)
                    Button("Stimme testen") { coach.speak("Schneller") }
                    if let text = coach.lastAnnouncement, let date = coach.lastAnnouncementDate {
                        LabeledContent("Letzte Ansage") {
                            Text("„\(text)“ um \(date.formatted(date: .omitted, time: .standard))")
                        }
                    }
                    if let error = coach.lastError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                } header: {
                    Text("Ansagen")
                } footer: {
                    if useSiri {
                        Text("Siri liest die Ansagen bei gesperrtem iPhone vor und stellt die Musik dabei leiser. Dafür einschalten: Einstellungen → Mitteilungen → Mitteilungen ankündigen → Heart Dance. Ist die App offen, spricht die App-Stimme.")
                    } else {
                        Text("Liegt dein Puls unter dem Minimum, hörst du „Schneller“, darüber „Langsamer“. Im Zielbereich bleibt es still. Musik läuft dabei in voller Lautstärke weiter.")
                    }
                }

                Section {
                    startStopButton
                }
            }
            .navigationTitle("Heart Dance")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            coach.useSiri = useSiri
            syncTexts()
            monitor.onHeartRate = { bpm in
                liveActivity.update(bpm: bpm, low: lowBPM, high: highBPM)
                coach.evaluate(
                    bpm: bpm,
                    low: lowBPM,
                    high: highBPM,
                    interval: TimeInterval(announceInterval)
                )
            }
        }
        // Verlässt du ein Feld (Fertig, anderes Feld antippen), wird die Eingabe übernommen.
        .onChange(of: focusedField) { oldValue, _ in
            if let oldValue { commit(oldValue) }
        }
        .onChange(of: monitor.state) { _, newState in
            if case .failed = newState {
                liveActivity.end()
                coach.endSession()
            }
        }
        .onChange(of: useSiri) { _, newValue in coach.useSiri = newValue }
        .onChange(of: lowBPM) { _, _ in rangeChanged() }
        .onChange(of: highBPM) { _, _ in rangeChanged() }
    }

    // MARK: - Eingabe

    private func bpmRow(title: String, text: Binding<String>, field: Field,
                        value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .focused($focusedField, equals: field)
            Text("bpm").foregroundStyle(.secondary)
            Stepper(title, value: value, in: range)
                .labelsHidden()
        }
    }

    private func commit(_ field: Field) {
        let raw = (field == .low ? lowText : highText).trimmingCharacters(in: .whitespaces)
        guard let number = Int(raw), allowedRange.contains(number) else {
            inputError = "Bitte eine Zahl zwischen \(allowedRange.lowerBound) und \(allowedRange.upperBound) eingeben."
            syncTexts()
            return
        }
        switch field {
        case .low:
            guard number < highBPM else {
                inputError = "Das Minimum muss kleiner als das Maximum (\(highBPM)) sein."
                syncTexts()
                return
            }
            lowBPM = number
        case .high:
            guard number > lowBPM else {
                inputError = "Das Maximum muss größer als das Minimum (\(lowBPM)) sein."
                syncTexts()
                return
            }
            highBPM = number
        }
        inputError = nil
        syncTexts()
    }

    private func rangeChanged() {
        syncTexts()
        liveActivity.update(bpm: monitor.heartRate, low: lowBPM, high: highBPM)
    }

    private func syncTexts() {
        if focusedField != .low { lowText = String(lowBPM) }
        if focusedField != .high { highText = String(highBPM) }
    }

    // MARK: - Anzeige

    private var heartRateDisplay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(zoneColor)
                    .symbolEffect(.pulse, isActive: monitor.state == .running)
                Text(monitor.heartRate.map { "\(Int($0.rounded()))" } ?? "––")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var startStopButton: some View {
        Button {
            focusedField = nil
            Task {
                if monitor.isActive {
                    liveActivity.end()
                    coach.endSession()
                    await monitor.stop()
                } else {
                    coach.reset()
                    await monitor.start()
                    if monitor.state == .running {
                        liveActivity.start(low: lowBPM, high: highBPM)
                        coach.beginSession()
                        // Erste Ansage im Vordergrund – bereitet die Audio-Ausgabe vor.
                        coach.speak("Los geht's")
                    }
                }
            }
        } label: {
            Text(monitor.isActive ? "Stopp" : "Start")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .tint(monitor.isActive ? .red : .green)
        .disabled(monitor.state == .stopping)
    }

    private var zoneColor: Color {
        guard let bpm = monitor.heartRate else { return .gray }
        if bpm < Double(lowBPM) { return .blue }
        if bpm > Double(highBPM) { return .red }
        return .green
    }

    private var statusText: String {
        switch monitor.state {
        case .idle:
            return "AirPods Pro 3 einsetzen und auf Start tippen."
        case .starting:
            return "Starte …"
        case .running:
            return monitor.heartRate == nil
                ? "Warte auf Pulswerte von den AirPods …"
                : "Ziel: \(lowBPM)–\(highBPM) bpm"
        case .stopping:
            return "Beende …"
        case .failed(let message):
            return "Fehler: \(message)"
        }
    }
}

#Preview {
    ContentView()
}

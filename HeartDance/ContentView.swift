import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = HeartRateMonitor()
    @State private var coach = VoiceCoach()

    @AppStorage("lowBPM") private var lowBPM = 120
    @AppStorage("highBPM") private var highBPM = 130
    @AppStorage("announceInterval") private var announceInterval = 10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    heartRateDisplay
                }

                Section("Zielbereich") {
                    Stepper("Minimum: \(lowBPM) bpm", value: $lowBPM, in: 40...(highBPM - 1), step: 1)
                    Stepper("Maximum: \(highBPM) bpm", value: $highBPM, in: (lowBPM + 1)...220, step: 1)
                }

                Section {
                    Stepper("Höchstens alle \(announceInterval) s", value: $announceInterval, in: 3...60, step: 1)
                    Button("Stimme testen") { coach.speak("Schneller") }
                } header: {
                    Text("Ansagen")
                } footer: {
                    Text("Liegt dein Puls unter dem Minimum, hörst du „Schneller“, darüber „Langsamer“. Im Zielbereich bleibt es still.")
                }

                Section {
                    startStopButton
                }
            }
            .navigationTitle("Heart Dance")
        }
        .onAppear {
            monitor.onHeartRate = { bpm in
                coach.evaluate(
                    bpm: bpm,
                    low: lowBPM,
                    high: highBPM,
                    interval: TimeInterval(announceInterval)
                )
            }
        }
    }

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
            Task {
                if monitor.isActive {
                    await monitor.stop()
                } else {
                    coach.reset()
                    await monitor.start()
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

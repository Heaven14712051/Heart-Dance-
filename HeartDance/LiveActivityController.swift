import ActivityKit
import Foundation

/// Startet, aktualisiert und beendet die Live-Aktivität auf dem Sperrbildschirm.
@MainActor
final class LiveActivityController {
    private var activity: Activity<HeartRateActivityAttributes>?
    private var lastSent: HeartRateActivityAttributes.ContentState?
    private var lastSentDate: Date = .distantPast

    /// Muss aufgerufen werden, während die App im Vordergrund ist (z. B. beim Tippen auf Start).
    func start(low: Int, high: Int) {
        endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = HeartRateActivityAttributes.ContentState(bpm: nil, low: low, high: high)
        do {
            activity = try Activity.request(
                attributes: HeartRateActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastSent = state
            lastSentDate = Date()
        } catch {
            print("Live-Aktivität konnte nicht gestartet werden: \(error)")
        }
    }

    func update(bpm: Double?, low: Int, high: Int) {
        guard let activity else { return }
        let state = HeartRateActivityAttributes.ContentState(
            bpm: bpm.map { Int($0.rounded()) },
            low: low,
            high: high
        )
        let now = Date()
        // Nur senden, wenn sich etwas geändert hat (oder als Lebenszeichen alle 30 s).
        guard state != lastSent || now.timeIntervalSince(lastSentDate) > 30 else { return }
        lastSent = state
        lastSentDate = now

        // Kommen 60 s keine neuen Werte, zeigt der Sperrbildschirm "keine Daten".
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(60))
        Task {
            await activity.update(content)
        }
    }

    func end() {
        endAll()
    }

    private func endAll() {
        activity = nil
        lastSent = nil
        for running in Activity<HeartRateActivityAttributes>.activities {
            Task {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

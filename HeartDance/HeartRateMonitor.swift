import Foundation
import HealthKit

/// Startet eine Workout-Session auf dem iPhone (ab iOS 26 möglich) und liefert
/// live die Herzfrequenz. Mit AirPods Pro 3 im Ohr kommt der Puls von deren Sensor.
@MainActor
final class HeartRateMonitor: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var lastUpdate: Date?

    /// Wird bei jedem neuen Pulswert aufgerufen.
    var onHeartRate: ((Double) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private static let heartRateType = HKQuantityType(.heartRate)
    private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    var isActive: Bool {
        state == .starting || state == .running
    }

    func start() async {
        guard !isActive else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("Health-Daten sind auf diesem Gerät nicht verfügbar.")
            return
        }

        state = .starting
        heartRate = nil
        lastUpdate = nil

        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [Self.heartRateType]
            )

            let configuration = HKWorkoutConfiguration()
            // Workout-Typ, unter dem die Session in Health gespeichert wird.
            configuration.activityType = .cardioDance
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            state = .running
        } catch {
            cleanUp()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard let session, let builder else {
            state = .idle
            return
        }
        state = .stopping
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            // Speichern ist optional – Fehler hier ignorieren wir bewusst.
        }
        cleanUp()
        state = .idle
    }

    private func cleanUp() {
        session = nil
        builder = nil
    }

    fileprivate func receive(_ bpm: Double) {
        heartRate = bpm
        lastUpdate = Date()
        onHeartRate?(bpm)
    }

    fileprivate func fail(_ message: String) {
        cleanUp()
        state = .failed(message)
    }
}

extension HeartRateMonitor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.fail(message)
        }
    }
}

extension HeartRateMonitor: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in
            self.receive(bpm)
        }
    }
}

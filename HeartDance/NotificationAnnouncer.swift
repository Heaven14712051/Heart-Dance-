import UserNotifications

/// Schickt Ansagen als Mitteilung. Ist auf dem iPhone "Mitteilungen ankündigen" für
/// Heart Dance eingeschaltet, liest Siri sie bei gesperrtem Bildschirm über die AirPods
/// vor und stellt die Musik dabei leiser.
@MainActor
final class NotificationAnnouncer {
    private let center = UNUserNotificationCenter.current()
    private var deliveredIDs: [String] = []

    /// Im Vordergrund aufrufen (fragt beim ersten Mal nach der Erlaubnis).
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ text: String, onError: @escaping @MainActor (String) -> Void) {
        // Alte Ansagen aus der Mitteilungszentrale entfernen, damit sie sich nicht stapeln.
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        center.removePendingNotificationRequests(withIdentifiers: deliveredIDs)

        let content = UNMutableNotificationContent()
        content.body = text
        content.interruptionLevel = .active

        // Jede Ansage braucht eine neue ID – eine bloß ersetzte Mitteilung liest Siri nicht erneut vor.
        let id = "heartdance.coach.\(UUID().uuidString)"
        deliveredIDs = [id]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in onError(message) }
        }
    }

    func clear() {
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        deliveredIDs = []
    }
}

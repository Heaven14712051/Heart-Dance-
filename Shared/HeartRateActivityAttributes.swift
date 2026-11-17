import ActivityKit
import Foundation

/// Daten der Live-Aktivität auf dem Sperrbildschirm. Wird von App und Widget-Erweiterung geteilt.
struct HeartRateActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var bpm: Int?
        var low: Int
        var high: Int
    }

    var title: String = "Heart Dance"
}

enum HeartRateZone {
    case below, inRange, above, unknown

    init(bpm: Int?, low: Int, high: Int) {
        guard let bpm else { self = .unknown; return }
        if bpm < low {
            self = .below
        } else if bpm > high {
            self = .above
        } else {
            self = .inRange
        }
    }

    var label: String {
        switch self {
        case .below: return "Schneller"
        case .inRange: return "Im Ziel"
        case .above: return "Langsamer"
        case .unknown: return "Warte auf Puls"
        }
    }
}

extension HeartRateActivityAttributes.ContentState {
    var zone: HeartRateZone { HeartRateZone(bpm: bpm, low: low, high: high) }
}

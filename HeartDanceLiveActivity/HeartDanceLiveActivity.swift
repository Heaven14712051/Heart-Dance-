import ActivityKit
import SwiftUI
import WidgetKit

@main
struct HeartDanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeartRateLiveActivity()
    }
}

struct HeartRateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartRateActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // Nur für iPhones mit Dynamic Island – das iPhone SE nutzt die Sperrbildschirm-Ansicht.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(context.state.zone.color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(bpmText(context.state, isStale: context.isStale))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.zone.label)
                }
            } compactLeading: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(context.state.zone.color)
            } compactTrailing: {
                Text(bpmText(context.state, isStale: context.isStale))
                    .monospacedDigit()
            } minimal: {
                Text(bpmText(context.state, isStale: context.isStale))
                    .monospacedDigit()
            }
        }
    }
}

private struct LockScreenView: View {
    let state: HeartRateActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let zone: HeartRateZone = isStale ? .unknown : state.zone

        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 34))
                .foregroundStyle(zone.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(bpmText(state, isStale: isStale))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Ziel \(state.low)–\(state.high)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text(isStale ? "Keine Daten" : zone.label)
                .font(.headline)
                .foregroundStyle(zone.color)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private func bpmText(_ state: HeartRateActivityAttributes.ContentState, isStale: Bool) -> String {
    guard !isStale, let bpm = state.bpm else { return "––" }
    return "\(bpm)"
}

extension HeartRateZone {
    var color: Color {
        switch self {
        case .below: return .blue
        case .inRange: return .green
        case .above: return .red
        case .unknown: return .gray
        }
    }
}

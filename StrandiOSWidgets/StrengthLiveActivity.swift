import SwiftUI
import WidgetKit
import ActivityKit
import StrandDesign

struct StrengthLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StrengthActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption); Spacer(); Text(context.state.restStart == nil ? "WORKOUT" : "REST").font(.caption) }
                HStack {
                    StrengthActivityClock(state: context.state, start: context.attributes.startedAt).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(StrandPalette.accent)
                    Spacer()
                    VStack(alignment: .trailing) { Text(context.state.exercise).font(.headline); Text(context.state.setLabel).font(.caption) }
                }
                Link(destination: context.attributes.url) { Text("Open workout").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
            }.padding(16).activityBackgroundTint(StrandPalette.surfaceBase).activitySystemActionForegroundColor(StrandPalette.accent).widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("NOOP Lab", systemImage: "dumbbell.fill").font(.caption).foregroundStyle(StrandPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StrengthActivityClock(state: context.state, start: context.attributes.startedAt).font(.title2.monospacedDigit()).foregroundStyle(StrandPalette.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) { Text(context.state.exercise).font(.headline); Text(context.state.setLabel).font(.caption)
                        Link("Open workout", destination: context.attributes.url)
                    }
                }
            } compactLeading: { Image(systemName: context.state.restStart == nil ? "dumbbell.fill" : "timer").foregroundStyle(StrandPalette.accent) }
            compactTrailing: { StrengthActivityClock(state: context.state, start: context.attributes.startedAt).monospacedDigit().frame(maxWidth: 58) }
            minimal: { StrengthActivityClock(state: context.state, start: context.attributes.startedAt).font(.caption2.monospacedDigit()) }
            .widgetURL(context.attributes.url)
        }
    }
}

private struct StrengthActivityClock: View {
    let state: StrengthActivityAttributes.ContentState
    let start: Date
    var body: some View {
        if let begin = state.restStart, let end = state.restEnd, end >= begin {
            Text(timerInterval: begin...end, countsDown: true, showsHours: false).monospacedDigit()
        } else { Text(start, style: .timer).monospacedDigit() }
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

struct PassCardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PassActivityAttributes.self) { context in
            lockScreenView(context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(context.attributes.kindLabel, systemImage: context.state.symbolName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownView(context.state, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.primary)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.secondary.isEmpty {
                        Text(context.state.secondary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .font(.system(size: 14, weight: .semibold))
            } compactTrailing: {
                if let start = context.state.countdownStart, let end = context.state.countdownEnd {
                    Text(timerInterval: start...end, countsDown: true, showsHours: true)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(context.state.primary)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    private func lockScreenView(_ state: PassActivityAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: state.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(state.primary)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if !state.secondary.isEmpty {
                    Text(state.secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            countdownView(state, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    private func countdownView(_ state: PassActivityAttributes.ContentState,
                               alignment: HorizontalAlignment) -> some View {
        if let start = state.countdownStart, let end = state.countdownEnd {
            VStack(alignment: alignment, spacing: 1) {
                if let verb = state.countdownVerb {
                    Text("距\(verb)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(timerInterval: start...end, countsDown: true, showsHours: true)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            }
        } else {
            EmptyView()
        }
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ApexCardioLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ApexCardioLiveActivity()
    }
}

struct ApexCardioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: ApexCardioRecordingAttributes.self
        ) { context in
            ApexCardioLockScreenView(
                context: context
            )
            .activityBackgroundTint(
                Color.black.opacity(0.92)
            )
            .activitySystemActionForegroundColor(
                .white
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(
                        spacing: 7
                    ) {
                        Image(
                            systemName: "waveform.path.ecg"
                        )
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            .mint
                        )

                        Text("APEX")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                .primary
                            )
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ApexCardioConnectionIndicator(
                        connected:
                            context.state.isConnected
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(
                        spacing: 3
                    ) {
                        Text(
                            context.attributes.recordingName
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .lineLimit(1)

                        Text(
                            timerInterval:
                                context.attributes.startedAt...Date.distantFuture,
                            countsDown: false
                        )
                        .font(
                            .system(
                                size: 22,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .monospacedDigit()
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ApexCardioActivityControls(
                        isPaused:
                            context.state.isPaused,
                        compact: true
                    )
                    .padding(
                        .top,
                        4
                    )
                }
            } compactLeading: {
                Image(
                    systemName: "waveform.path.ecg"
                )
                .foregroundStyle(
                    .mint
                )
            } compactTrailing: {
                ApexCardioCompactStatus(
                    state: context.state
                )
            } minimal: {
                Circle()
                    .fill(
                        ApexCardioStatusStyle.color(
                            for: context.state
                        )
                    )
                    .frame(
                        width: 10,
                        height: 10
                    )
            }
            .keylineTint(
                .mint
            )
        }
    }
}

private struct ApexCardioLockScreenView: View {
    let context:
        ActivityViewContext<ApexCardioRecordingAttributes>

    var body: some View {
        VStack(
            spacing: 14
        ) {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .fill(
                        Color.mint.opacity(0.14)
                    )

                    Image(
                        systemName: "waveform.path.ecg"
                    )
                    .font(
                        .system(
                            size: 23,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        .mint
                    )
                }
                .frame(
                    width: 48,
                    height: 48
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("APEX CARDIO")
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .tracking(1.1)

                    Text(
                        context.attributes.recordingName
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)
                }

                Spacer(
                    minLength: 8
                )

                ApexCardioConnectionIndicator(
                    connected:
                        context.state.isConnected
                )
            }

            HStack(
                alignment: .center
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    HStack(
                        spacing: 7
                    ) {
                        Circle()
                            .fill(
                                ApexCardioStatusStyle.color(
                                    for: context.state
                                )
                            )
                            .frame(
                                width: 8,
                                height: 8
                            )

                        Text(
                            context.state.statusText
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .medium
                            )
                        )
                    }

                    Text(
                        context.state.isConnected
                            ? "ECG + Respiration"
                            : "Waiting for ApexCardio"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Text(
                    timerInterval:
                        context.attributes.startedAt...Date.distantFuture,
                    countsDown: false
                )
                .font(
                    .system(
                        size: 27,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .monospacedDigit()
                .contentTransition(
                    .numericText()
                )
            }

            ApexCardioActivityControls(
                isPaused: context.state.isPaused,
                compact: false
            )
        }
        .padding(
            16
        )
    }
}

private struct ApexCardioConnectionIndicator: View {
    let connected: Bool

    var body: some View {
        HStack(
            spacing: 5
        ) {
            Image(
                systemName:
                    connected
                    ? "bluetooth"
                    : "bluetooth.slash"
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )

            Text(
                connected
                    ? "Connected"
                    : "Disconnected"
            )
            .font(
                .system(
                    size: 11,
                    weight: .medium
                )
            )
        }
        .foregroundStyle(
            connected
                ? Color.mint
                : Color.orange
        )
    }
}

private struct ApexCardioCompactStatus: View {
    let state:
        ApexCardioRecordingAttributes.ContentState

    var body: some View {
        HStack(
            spacing: 4
        ) {
            Circle()
                .fill(
                    ApexCardioStatusStyle.color(
                        for: state
                    )
                )
                .frame(
                    width: 7,
                    height: 7
                )

            Image(
                systemName:
                    state.isPaused
                    ? "pause.fill"
                    : state.isConnected
                        ? "record.circle.fill"
                        : "exclamationmark"
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
        }
    }
}

private struct ApexCardioActivityControls: View {
    let isPaused: Bool
    let compact: Bool

    var body: some View {
        if #available(
            iOSApplicationExtension 17.0,
            *
        ) {
            HStack(
                spacing: compact ? 18 : 12
            ) {
                if isPaused {
                    Button(
                        intent:
                            ApexCardioResumeRecordingIntent()
                    ) {
                        ApexCardioControlLabel(
                            systemName: "play.fill",
                            title: "Resume",
                            compact: compact
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(
                        intent:
                            ApexCardioPauseRecordingIntent()
                    ) {
                        ApexCardioControlLabel(
                            systemName: "pause.fill",
                            title: "Pause",
                            compact: compact
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(
                    intent:
                        ApexCardioStopRecordingIntent()
                ) {
                    ApexCardioControlLabel(
                        systemName: "stop.fill",
                        title: "Stop",
                        compact: compact
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(
                spacing: 8
            ) {
                Image(
                    systemName:
                        isPaused
                        ? "pause.circle.fill"
                        : "record.circle.fill"
                )

                Text(
                    isPaused
                        ? "Recording paused"
                        : "Recording active"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .medium
                    )
                )
            }
            .foregroundStyle(
                .secondary
            )
        }
    }
}

private struct ApexCardioControlLabel: View {
    let systemName: String
    let title: String
    let compact: Bool

    var body: some View {
        HStack(
            spacing: 7
        ) {
            Image(
                systemName: systemName
            )
            .font(
                .system(
                    size: compact ? 14 : 15,
                    weight: .semibold
                )
            )

            if !compact {
                Text(title)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
            }
        }
        .frame(
            maxWidth:
                compact
                ? nil
                : .infinity
        )
        .padding(
            .horizontal,
            compact ? 10 : 14
        )
        .padding(
            .vertical,
            compact ? 7 : 10
        )
        .background(
            Capsule()
                .fill(
                    Color.white.opacity(0.11)
                )
        )
        .contentShape(
            Capsule()
        )
    }
}

private enum ApexCardioStatusStyle {
    static func color(
        for state:
            ApexCardioRecordingAttributes.ContentState
    ) -> Color {
        if state.isPaused {
            return .yellow
        }

        if !state.isConnected {
            return .orange
        }

        return .red
    }
}
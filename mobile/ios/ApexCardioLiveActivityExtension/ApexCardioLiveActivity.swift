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
                Color(
                    red: 0.035,
                    green: 0.055,
                    blue: 0.065
                )
            )
            .activitySystemActionForegroundColor(
                .white
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(
                        spacing: 6
                    ) {
                        ApexCardioRecordingDot(
                            state: context.state,
                            size: 9
                        )

                        Text(
                            context.state.isPaused
                                ? "PAUSED"
                                : context.state.isConnected
                                    ? "REC"
                                    : "GAP"
                        )
                        .font(
                            .system(
                                size: 12,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(
                        context.attributes.startedAt,
                        style: .timer
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        .white
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(
                        spacing: 3
                    ) {
                        Text("APEX CARDIO")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .tracking(0.8)
                            .foregroundStyle(
                                Color.mint
                            )

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
                        .foregroundStyle(
                            .white
                        )
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(
                        spacing: 8
                    ) {
                        HStack {
                            Text(
                                context.state.statusText
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(0.82)
                            )

                            Spacer()

                            Text(
                                context.state.isConnected
                                    ? "ECG + RESP"
                                    : "Waiting for signal"
                            )
                            .font(
                                .system(
                                    size: 11,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(
                                context.state.isConnected
                                    ? Color.mint
                                    : Color.orange
                            )
                        }

                        ApexCardioActivityControls(
                            isPaused:
                                context.state.isPaused,
                            compact: true
                        )
                    }
                    .padding(
                        .top,
                        3
                    )
                }
            } compactLeading: {
                HStack(
                    spacing: 4
                ) {
                    ApexCardioRecordingDot(
                        state: context.state,
                        size: 8
                    )

                    Text(
                        context.state.isPaused
                            ? "PAUSE"
                            : context.state.isConnected
                                ? "REC"
                                : "GAP"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                }
            } compactTrailing: {
                Image(
                    systemName:
                        context.state.isConnected
                            ? "waveform.path.ecg"
                            : "exclamationmark"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    context.state.isConnected
                        ? Color.mint
                        : Color.orange
                )
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.22),
                            lineWidth: 1
                        )

                    ApexCardioRecordingDot(
                        state: context.state,
                        size: 8
                    )
                }
                .frame(
                    width: 16,
                    height: 16
                )
            }
            .keylineTint(
                ApexCardioStatusStyle.color(
                    for: context.state
                )
            )
        }
    }
}

private struct ApexCardioLockScreenView: View {
    let context:
        ActivityViewContext<ApexCardioRecordingAttributes>

    var body: some View {
        VStack(
            spacing: 13
        ) {
            HStack(
                alignment: .center,
                spacing: 10
            ) {
                HStack(
                    spacing: 7
                ) {
                    ApexCardioRecordingDot(
                        state: context.state,
                        size: 10
                    )

                    Text("APEX CARDIO")
                        .font(
                            .system(
                                size: 12,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .tracking(0.8)
                        .foregroundStyle(
                            .white
                        )
                }

                Spacer()

                Text(
                    context.state.isConnected
                        ? "CONNECTED"
                        : "SIGNAL GAP"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    context.state.isConnected
                        ? Color.mint
                        : Color.orange
                )
            }

            HStack(
                alignment: .center
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
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
                    .foregroundStyle(
                        .white
                    )

                    Text(
                        context.state.statusText
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.62)
                    )
                }

                Spacer(
                    minLength: 14
                )

                Text(
                    context.attributes.startedAt,
                    style: .timer
                )
                .font(
                    .system(
                        size: 26,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    .white
                )
            }

            HStack(
                spacing: 8
            ) {
                ApexCardioSignalBadge(
                    title: "ECG",
                    active:
                        context.state.isConnected
                )

                ApexCardioSignalBadge(
                    title: "RESP",
                    active:
                        context.state.isConnected
                )

                Spacer()

                Text("250 Hz")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.48)
                    )
            }

            ApexCardioActivityControls(
                isPaused:
                    context.state.isPaused,
                compact: false
            )
        }
        .padding(
            16
        )
    }
}

private struct ApexCardioSignalBadge: View {
    let title: String
    let active: Bool

    var body: some View {
        Text(title)
            .font(
                .system(
                    size: 10,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .foregroundStyle(
                active
                    ? Color.mint
                    : Color.white.opacity(0.38)
            )
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                4
            )
            .background(
                Capsule()
                    .fill(
                        Color.white.opacity(0.08)
                    )
            )
    }
}

private struct ApexCardioRecordingDot: View {
    let state:
        ApexCardioRecordingAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                ApexCardioStatusStyle.color(
                    for: state
                )
            )
            .frame(
                width: size,
                height: size
            )
            .shadow(
                color:
                    ApexCardioStatusStyle.color(
                        for: state
                    ).opacity(0.45),
                radius: 3
            )
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
                spacing: 9
            ) {
                if isPaused {
                    Button(
                        intent:
                            ApexCardioResumeRecordingIntent()
                    ) {
                        ApexCardioControlLabel(
                            title: "Resume",
                            systemName: "play.fill",
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
                            title: "Pause",
                            systemName: "pause.fill",
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
                        title: "Stop",
                        systemName: "stop.fill",
                        compact: compact
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(
                spacing: 6
            ) {
                ApexCardioRecordingDot(
                    state:
                        ApexCardioRecordingAttributes
                            .ContentState(
                                isPaused: isPaused,
                                isConnected: true,
                                statusText:
                                    isPaused
                                        ? "Paused"
                                        : "Recording",
                                updatedAt: Date()
                            ),
                    size: 8
                )

                Text(
                    isPaused
                        ? "Recording paused"
                        : "Recording active"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.65)
                )
            }
        }
    }
}

private struct ApexCardioControlLabel: View {
    let title: String
    let systemName: String
    let compact: Bool

    var body: some View {
        HStack(
            spacing: 6
        ) {
            Image(
                systemName: systemName
            )
            .font(
                .system(
                    size: 12,
                    weight: .bold
                )
            )

            Text(title)
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
        }
        .foregroundStyle(
            .white
        )
        .frame(
            maxWidth:
                compact
                    ? nil
                    : .infinity
        )
        .padding(
            .horizontal,
            compact ? 11 : 14
        )
        .padding(
            .vertical,
            compact ? 7 : 9
        )
        .background(
            Capsule()
                .fill(
                    Color.white.opacity(0.11)
                )
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

        return Color(
            red: 0.95,
            green: 0.20,
            blue: 0.22
        )
    }
}
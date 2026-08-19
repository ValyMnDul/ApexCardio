import ActivityKit
import Flutter
import Foundation

@MainActor
final class ApexCardioLiveActivityBridge {
    static let channelName = "apexcardio/live_activity"

    private static var channel: FlutterMethodChannel?

    static func register(
        messenger: FlutterBinaryMessenger
    ) {
        let methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )

        channel = methodChannel

        methodChannel.setMethodCallHandler {
            call,
            result in

            handle(
                call: call,
                result: result
            )
        }

        ApexCardioRecordingCommandCenter.shared.bind {
            command in

            channel?.invokeMethod(
                "recordingCommand",
                arguments: command.rawValue
            )
        }
    }

    private static func handle(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "isSupported":
            result(
                isSupported
            )

        case "start":
            guard
                let arguments =
                    call.arguments as? [String: Any],
                let recordingId =
                    intValue(arguments["recordingId"]),
                let recordingName =
                    arguments["recordingName"] as? String,
                let startedAtMs =
                    intValue(arguments["startedAtMs"]),
                let isPaused =
                    arguments["isPaused"] as? Bool,
                let isConnected =
                    arguments["isConnected"] as? Bool,
                let statusText =
                    arguments["statusText"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid Live Activity start arguments.",
                        details: nil
                    )
                )
                return
            }

            Task { @MainActor in
                do {
                    guard #available(iOS 16.1, *) else {
                        result(
                            FlutterError(
                                code: "NOT_SUPPORTED",
                                message: "Live Activities require iOS 16.1 or later.",
                                details: nil
                            )
                        )
                        return
                    }

                    let activityId = try await start(
                        recordingId: recordingId,
                        recordingName: recordingName,
                        startedAtMs: startedAtMs,
                        isPaused: isPaused,
                        isConnected: isConnected,
                        statusText: statusText
                    )

                    result(activityId)
                } catch {
                    result(
                        flutterError(
                            code: "START_FAILED",
                            error: error
                        )
                    )
                }
            }

        case "update":
            guard
                let arguments =
                    call.arguments as? [String: Any],
                let recordingId =
                    intValue(arguments["recordingId"]),
                let isPaused =
                    arguments["isPaused"] as? Bool,
                let isConnected =
                    arguments["isConnected"] as? Bool,
                let statusText =
                    arguments["statusText"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid Live Activity update arguments.",
                        details: nil
                    )
                )
                return
            }

            Task { @MainActor in
                do {
                    guard #available(iOS 16.1, *) else {
                        result(
                            FlutterError(
                                code: "NOT_SUPPORTED",
                                message: "Live Activities require iOS 16.1 or later.",
                                details: nil
                            )
                        )
                        return
                    }

                    let updated = try await update(
                        recordingId: recordingId,
                        isPaused: isPaused,
                        isConnected: isConnected,
                        statusText: statusText
                    )

                    result(updated)
                } catch {
                    result(
                        flutterError(
                            code: "UPDATE_FAILED",
                            error: error
                        )
                    )
                }
            }

        case "end":
            guard
                let arguments =
                    call.arguments as? [String: Any],
                let recordingId =
                    intValue(arguments["recordingId"])
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid Live Activity end arguments.",
                        details: nil
                    )
                )
                return
            }

            let finalStatus =
                arguments["finalStatus"] as? String
                ?? "Saved"

            Task { @MainActor in
                do {
                    guard #available(iOS 16.1, *) else {
                        result(
                            FlutterError(
                                code: "NOT_SUPPORTED",
                                message: "Live Activities require iOS 16.1 or later.",
                                details: nil
                            )
                        )
                        return
                    }

                    let ended = try await end(
                        recordingId: recordingId,
                        finalStatus: finalStatus
                    )

                    result(ended)
                } catch {
                    result(
                        flutterError(
                            code: "END_FAILED",
                            error: error
                        )
                    )
                }
            }

        case "endAll":
            Task { @MainActor in
                do {
                    guard #available(iOS 16.1, *) else {
                        result(
                            FlutterError(
                                code: "NOT_SUPPORTED",
                                message: "Live Activities require iOS 16.1 or later.",
                                details: nil
                            )
                        )
                        return
                    }

                    let count = try await endAll()
                    result(count)
                } catch {
                    result(
                        flutterError(
                            code: "END_ALL_FAILED",
                            error: error
                        )
                    )
                }
            }

        default:
            result(
                FlutterMethodNotImplemented
            )
        }
    }

    static var isSupported: Bool {
        guard #available(iOS 16.1, *) else {
            return false
        }

        return ActivityAuthorizationInfo()
            .areActivitiesEnabled
    }

    @available(iOS 16.1, *)
    private static func start(
        recordingId: Int,
        recordingName: String,
        startedAtMs: Int,
        isPaused: Bool,
        isConnected: Bool,
        statusText: String
    ) async throws -> String {
        guard ActivityAuthorizationInfo()
            .areActivitiesEnabled
        else {
            throw ApexCardioLiveActivityError.disabled
        }

        let state =
            ApexCardioRecordingAttributes.ContentState(
                isPaused: isPaused,
                isConnected: isConnected,
                statusText: statusText,
                updatedAt: Date()
            )

        if let existing = activity(
            recordingId: recordingId
        ) {
            try await updateActivity(
                existing,
                state: state
            )

            return existing.id
        }

        let otherActivities =
            Activity<ApexCardioRecordingAttributes>
                .activities
                .filter {
                    $0.attributes.recordingId !=
                        recordingId
                }

        for activity in otherActivities {
            try await endActivity(
                activity,
                finalState:
                    ApexCardioRecordingAttributes
                        .ContentState(
                            isPaused: true,
                            isConnected: false,
                            statusText: "Ended",
                            updatedAt: Date()
                        )
            )
        }

        let attributes =
            ApexCardioRecordingAttributes(
                recordingId: recordingId,
                recordingName: recordingName,
                startedAt: Date(
                    timeIntervalSince1970:
                        Double(startedAtMs) / 1000.0
                )
            )

        if #available(iOS 16.2, *) {
            let content =
                ActivityContent(
                    state: state,
                    staleDate: nil
                )

            let activity =
                try Activity<
                    ApexCardioRecordingAttributes
                >.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )

            return activity.id
        }

        let activity =
            try Activity<
                ApexCardioRecordingAttributes
            >.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )

        return activity.id
    }

    @available(iOS 16.1, *)
    private static func update(
        recordingId: Int,
        isPaused: Bool,
        isConnected: Bool,
        statusText: String
    ) async throws -> Bool {
        guard let activity = activity(
            recordingId: recordingId
        ) else {
            return false
        }

        let state =
            ApexCardioRecordingAttributes.ContentState(
                isPaused: isPaused,
                isConnected: isConnected,
                statusText: statusText,
                updatedAt: Date()
            )

        try await updateActivity(
            activity,
            state: state
        )

        return true
    }

    @available(iOS 16.1, *)
    private static func end(
        recordingId: Int,
        finalStatus: String
    ) async throws -> Bool {
        guard let activity = activity(
            recordingId: recordingId
        ) else {
            return false
        }

        let currentState =
            currentState(
                activity
            )

        let finalState =
            ApexCardioRecordingAttributes.ContentState(
                isPaused: true,
                isConnected:
                    currentState?.isConnected
                    ?? false,
                statusText: finalStatus,
                updatedAt: Date()
            )

        try await endActivity(
            activity,
            finalState: finalState
        )

        return true
    }

    @available(iOS 16.1, *)
    private static func endAll() async throws -> Int {
        let activities =
            Activity<ApexCardioRecordingAttributes>
                .activities

        for activity in activities {
            let current =
                currentState(
                    activity
                )

            let finalState =
                ApexCardioRecordingAttributes
                    .ContentState(
                        isPaused: true,
                        isConnected:
                            current?.isConnected
                            ?? false,
                        statusText: "Ended",
                        updatedAt: Date()
                    )

            try await endActivity(
                activity,
                finalState: finalState
            )
        }

        return activities.count
    }

    @available(iOS 16.1, *)
    private static func activity(
        recordingId: Int
    ) -> Activity<ApexCardioRecordingAttributes>? {
        Activity<ApexCardioRecordingAttributes>
            .activities
            .first {
                $0.attributes.recordingId ==
                    recordingId
            }
    }

    @available(iOS 16.1, *)
    private static func currentState(
        _ activity:
            Activity<ApexCardioRecordingAttributes>
    ) -> ApexCardioRecordingAttributes.ContentState? {
        if #available(iOS 16.2, *) {
            return activity.content.state
        }

        return activity.contentState
    }

    @available(iOS 16.1, *)
    private static func updateActivity(
        _ activity:
            Activity<ApexCardioRecordingAttributes>,
        state:
            ApexCardioRecordingAttributes.ContentState
    ) async throws {
        if #available(iOS 16.2, *) {
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: nil
                )
            )

            return
        }

        await activity.update(
            using: state
        )
    }

    @available(iOS 16.1, *)
    private static func endActivity(
        _ activity:
            Activity<ApexCardioRecordingAttributes>,
        finalState:
            ApexCardioRecordingAttributes.ContentState
    ) async throws {
        if #available(iOS 16.2, *) {
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )

            return
        }

        await activity.end(
            using: finalState,
            dismissalPolicy: .immediate
        )
    }

    private static func intValue(
        _ value: Any?
    ) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private static func flutterError(
        code: String,
        error: Error
    ) -> FlutterError {
        FlutterError(
            code: code,
            message: String(
                describing: error
            ),
            details: nil
        )
    }
}

enum ApexCardioLiveActivityError: Error {
    case disabled
}
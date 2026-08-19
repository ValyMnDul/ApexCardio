import ActivityKit
import AppIntents
import Foundation

struct ApexCardioRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        var isConnected: Bool
        var statusText: String
        var updatedAt: Date
    }

    var recordingId: Int
    var recordingName: String
    var startedAt: Date
}

enum ApexCardioRecordingCommand: String, Codable {
    case pause
    case resume
    case stop
}

@MainActor
final class ApexCardioRecordingCommandCenter {
    static let shared = ApexCardioRecordingCommandCenter()

    private let pendingCommandKey = "apexcardio.pendingRecordingCommand"
    private let pendingCommandTimestampKey = "apexcardio.pendingRecordingCommandTimestamp"

    private var handler: ((ApexCardioRecordingCommand) -> Void)?

    private init() {}

    func bind(
        _ handler: @escaping (ApexCardioRecordingCommand) -> Void
    ) {
        self.handler = handler
        deliverPendingCommandIfNeeded()
    }

    func unbind() {
        handler = nil
    }

    func send(
        _ command: ApexCardioRecordingCommand
    ) {
        UserDefaults.standard.set(
            command.rawValue,
            forKey: pendingCommandKey
        )

        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: pendingCommandTimestampKey
        )

        if let handler {
            handler(command)
            clearPendingCommand()
        }
    }

    func deliverPendingCommandIfNeeded() {
        guard
            let rawValue = UserDefaults.standard.string(
                forKey: pendingCommandKey
            ),
            let command = ApexCardioRecordingCommand(
                rawValue: rawValue
            )
        else {
            return
        }

        let timestamp = UserDefaults.standard.double(
            forKey: pendingCommandTimestampKey
        )

        if timestamp > 0 {
            let age = Date().timeIntervalSince1970 - timestamp

            if age > 120 {
                clearPendingCommand()
                return
            }
        }

        guard let handler else {
            return
        }

        handler(command)
        clearPendingCommand()
    }

    private func clearPendingCommand() {
        UserDefaults.standard.removeObject(
            forKey: pendingCommandKey
        )

        UserDefaults.standard.removeObject(
            forKey: pendingCommandTimestampKey
        )
    }
}

@available(iOS 17.0, *)
struct ApexCardioPauseRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause ApexCardio Recording"
    static var description = IntentDescription(
        "Pauses the active ApexCardio recording."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            ApexCardioRecordingCommandCenter.shared.send(
                .pause
            )
        }

        return .result()
    }
}

@available(iOS 17.0, *)
struct ApexCardioResumeRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume ApexCardio Recording"
    static var description = IntentDescription(
        "Resumes the active ApexCardio recording."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            ApexCardioRecordingCommandCenter.shared.send(
                .resume
            )
        }

        return .result()
    }
}

@available(iOS 17.0, *)
struct ApexCardioStopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop ApexCardio Recording"
    static var description = IntentDescription(
        "Stops and saves the active ApexCardio recording."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            ApexCardioRecordingCommandCenter.shared.send(
                .stop
            )
        }

        return .result()
    }
}
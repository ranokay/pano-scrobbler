import Foundation
import Core
import UserNotifications

public final class MacNotificationPresenter: NotificationPresenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notify(_ notification: ScrobbleNotification) async {
        let content = UNMutableNotificationContent()
        content.sound = nil

        switch notification {
        case let .nowPlaying(data):
            content.title = data.track
            content.body = "Now playing by \(data.artist)"
        case let .scrobbled(data):
            content.title = "Scrobbled"
            content.body = "\(data.track) by \(data.artist)"
        case let .failed(data, message):
            content.title = "Scrobble failed"
            content.body = "\(data.track) by \(data.artist)\n\(message)"
        case let .blocked(data, reason):
            content.title = "Scrobble blocked"
            content.body = "\(data.track) by \(data.artist)\n\(reason)"
        case let .appDetected(appID, appName):
            content.title = "Music app detected"
            content.body = "\(appName) (\(appID))"
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}

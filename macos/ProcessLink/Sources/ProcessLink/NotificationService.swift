import Foundation
import UserNotifications

/// Local notifications for a sync that actually added something. Asked at the
/// moment the switch is turned on, never at launch.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postSyncSummary(newOpportunities: Int) {
        guard UserDefaults.standard.bool(forKey: "notifications.enabled") else { return }
        let content = UNMutableNotificationContent()
        content.title = "New discoveries in ProcessLink"
        content.body = "\(newOpportunities) new opportunit\(newOpportunities == 1 ? "y" : "ies") from KYP.ai, ranked and ready for review."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// A banner while the app is frontmost, so a sync is not silent.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

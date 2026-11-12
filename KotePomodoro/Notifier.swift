import Foundation
import UserNotifications
import OSLog
#if canImport(AppKit)
import AppKit
#endif

/// 앱이 앞에 떠 있을 때도 알림 배너를 보여준다. 소리 옵션은 넣지 않는다.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// 무음 mac 알림
enum Notifier {
    private static let delegate = NotificationDelegate()
    private static let endID = "phase-end"

    private static let log = Logger(subsystem: "KotePomodoro", category: "notification")

    static func setup() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// 알림 권한을 요청한다 (처음 한 번은 허용 창이 뜬다). .sound 권한은 요청하지 않는다.
    @discardableResult
    static func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            log.info("알림 권한 요청 결과: \(granted)")
            return granted
        } catch {
            log.error("알림 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 알림이 꺼져 있는지 (거부했거나 배너·알림 스타일이 '없음')
    static func isBlocked() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        log.info("알림 상태: \(settings.authorizationStatus.rawValue), alert: \(settings.alertSetting.rawValue)")
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting != .enabled
        default:
            return true
        }
    }

    /// '알림 켜기' 버튼: 아직 물어본 적 없으면 허용 창을 띄우고, 이미 거부했으면 시스템 설정을 연다
    static func enable() async {
        if await authorizationStatus() == .notDetermined {
            await requestPermission()
        } else {
            openSystemSettings()
        }
    }

    /// 시스템 설정의 알림 화면 열기
    static func openSystemSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// `after`초 뒤에 무음 알림을 예약한다. 이전 예약은 대체된다.
    static func schedule(title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: endID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [endID])
        center.add(request)
    }

    static func cancelScheduled() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [endID])
    }

    /// 시간이 끝났을 때 Dock 아이콘을 튀게 하고 앱을 앞으로 가져온다 (소리 없음)
    static func requestAttention() {
        #if canImport(AppKit)
        NSApplication.shared.requestUserAttention(.criticalRequest)
        NSApplication.shared.activate()
        #endif
    }
}

import Foundation
import EventKit
import OSLog
#if canImport(AppKit)
import AppKit
#endif

/// 아이폰(·애플워치) 알림. '미리 알림'에 끝나는 시각 알람이 달린 항목을 만들면
/// iCloud로 동기화되어 같은 Apple ID의 아이폰에서 그 시각에 울린다.
/// 예약·취소는 Notifier가 mac 알림과 함께 부른다.
enum PhoneAlert {
    static let enabledKey = "phoneAlertEnabled"
    static let listTitle = "취준 포모도로"
    private static let currentIDKey = "phoneAlertReminderID"

    private static let store = EKEventStore()
    private static let log = Logger(subsystem: "JobPomodoro", category: "phone-alert")

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    static var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .denied, .restricted, .writeOnly: true
        default: false
        }
    }

    /// 미리 알림 접근 허용 요청 (처음 한 번 허용 창이 뜬다)
    @discardableResult
    static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            log.error("미리 알림 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 시스템 설정의 미리 알림 개인정보 화면 열기
    static func openPrivacySettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// `date`에 울리는 미리 알림을 만든다. 이전 예약은 지운다.
    static func schedule(title: String, body: String, at date: Date) {
        cancel()
        guard isEnabled, isAuthorized, let list = reminderList() else { return }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = body
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        do {
            try store.save(reminder, commit: true)
            UserDefaults.standard.set(reminder.calendarItemIdentifier, forKey: currentIDKey)
        } catch {
            log.error("미리 알림 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
        cleanUpPast()
    }

    /// 예약한 미리 알림을 지운다 (일시정지·그만두기·추가 시간 등)
    static func cancel() {
        guard let id = UserDefaults.standard.string(forKey: currentIDKey) else { return }
        UserDefaults.standard.removeObject(forKey: currentIDKey)
        guard isAuthorized, let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        do {
            try store.remove(item, commit: true)
        } catch {
            log.error("미리 알림 삭제 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 이미 울린 지 1분 넘은 항목을 지워서 목록이 쌓이지 않게 한다
    static func cleanUpPast() {
        guard isAuthorized, let list = existingList() else { return }
        let predicate = store.predicateForReminders(in: [list])
        // 결과는 EventKit 백그라운드 스레드로 온다: 거기선 id만 뽑고, 지우기는 메인에서 한다
        store.fetchReminders(matching: predicate) { @Sendable reminders in
            let cutoff = Date.now.addingTimeInterval(-60)
            let ids = (reminders ?? []).filter { reminder in
                let alarmDate = reminder.alarms?.compactMap(\.absoluteDate).max()
                return reminder.isCompleted || (alarmDate.map { $0 < cutoff } ?? false)
            }.map(\.calendarItemIdentifier)
            guard !ids.isEmpty else { return }
            Task { @MainActor in
                for id in ids {
                    if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                        try? store.remove(reminder, commit: false)
                    }
                }
                try? store.commit()
            }
        }
    }

    private static func existingList() -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == listTitle }
    }

    /// '취준 포모도로' 목록. 없으면 iCloud(기본 미리 알림 계정)에 만든다
    private static func reminderList() -> EKCalendar? {
        if let list = existingList() { return list }
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            log.error("미리 알림 기본 계정을 찾을 수 없음")
            return nil
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = listTitle
        list.source = source
        do {
            try store.saveCalendar(list, commit: true)
            return list
        } catch {
            log.error("미리 알림 목록 만들기 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

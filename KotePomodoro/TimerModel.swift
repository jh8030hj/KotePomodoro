import Foundation
import Observation

enum TimerPhase: Equatable {
    case idle
    case focus
    case rest
}

enum SettingsKey {
    static let focusMinutes = "focusMinutes"
    static let restMinutes = "restMinutes"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [focusMinutes: 40, restMinutes: 10])
    }
}

/// 타이머 상태. 남은 시간은 실제 시각(Date) 기준으로 계산하므로 맥이 잠자기에 들어가도 정확하다.
///
/// 축구처럼 동작한다: 푸는 시간이 끝나면 멈추고, 추가 시간을 줄지 휴식할지 고른다.
/// 추가 시간이 끝나도 다시 고른다.
@Observable
final class TimerModel {
    private(set) var phase: TimerPhase = .idle
    private(set) var isRunning = false
    private(set) var phaseLength: TimeInterval = 0
    private(set) var now = Date()
    /// 지금까지 준 추가 시간 합계 (푸는 중일 때만)
    private(set) var extraTime: TimeInterval = 0
    /// 앱 화면 위에 띄울 안내 문구
    var alertMessage: String?
    /// 메인 창을 다시 열거나 앞으로 가져오는 동작 (ContentView가 설정)
    var openMainWindow: (() -> Void)?

    /// 시간이 끝나 휴식하러 갔을 때, 풀던 문제의 상태
    private struct SuspendedFocus {
        let accumulated: TimeInterval
        let phaseLength: TimeInterval
        let extraTime: TimeInterval
    }
    private var suspended: SuspendedFocus?

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var ticker: Task<Void, Never>?
    /// 실행 중에 App Nap으로 타이머가 늦어지지 않게 막는다
    private var activity: NSObjectProtocol?

    /// 이번 문제(또는 휴식)에서 실제로 흐른 시간 (일시정지 제외)
    var elapsed: TimeInterval {
        accumulated + (segmentStart.map { now.timeIntervalSince($0) } ?? 0)
    }

    var remaining: TimeInterval { max(phaseLength - elapsed, 0) }

    /// 푸는 시간(또는 추가 시간)이 끝나서 다음 선택을 기다리는 중
    var isTimeUp: Bool { phase == .focus && !isRunning && phaseLength > 0 && elapsed >= phaseLength }

    /// 추가 시간을 진행하는 중인지
    var isInExtraTime: Bool { phase == .focus && extraTime > 0 }

    var progress: Double {
        guard phaseLength > 0 else { return 0 }
        return min(max(elapsed / phaseLength, 0), 1)
    }

    /// 휴식 중인데 돌아갈 문제가 있으면, 그 문제를 푼 시간
    var suspendedElapsed: TimeInterval? { suspended?.accumulated }

    // MARK: - 사용자 동작

    func startFocus() {
        suspended = nil
        begin(.focus, minutes: UserDefaults.standard.integer(forKey: SettingsKey.focusMinutes))
    }

    func startRest() {
        suspended = nil
        begin(.rest, minutes: UserDefaults.standard.integer(forKey: SettingsKey.restMinutes))
    }

    /// 시간이 끝났을 때 추가 시간 주기
    func addExtraTime(minutes: Int) {
        guard isTimeUp, minutes > 0 else { return }
        let extra = TimeInterval(minutes * 60)
        phaseLength += extra
        extraTime += extra
        alertMessage = nil
        resume()
    }

    /// 시간이 끝났을 때 휴식하기. 푼 시간은 보관되고, 휴식 후 돌아와 다시 고를 수 있다.
    func takeBreak() {
        guard phase == .focus else { return }
        pause()
        suspended = SuspendedFocus(accumulated: accumulated, phaseLength: phaseLength, extraTime: extraTime)
        begin(.rest, minutes: UserDefaults.standard.integer(forKey: SettingsKey.restMinutes))
    }

    /// 휴식을 끝내고 풀던 문제로 돌아가기
    func returnToProblem() {
        guard phase == .rest, restoreSuspended() else { return }
        Notifier.cancelScheduled()
        alertMessage = nil
        resume()
    }

    func pause() {
        stopTicking()
        Notifier.cancelScheduled()
    }

    func resume() {
        guard phase != .idle, !isRunning, elapsed < phaseLength else { return }
        now = Date()
        segmentStart = now
        isRunning = true
        startTicking()
        scheduleEndNotification()
    }

    func reset() {
        pause()
        clear()
        suspended = nil
        alertMessage = nil
    }

    // MARK: - 내부

    private func begin(_ newPhase: TimerPhase, minutes: Int) {
        pause()
        phase = newPhase
        phaseLength = TimeInterval(max(minutes, 1) * 60)
        accumulated = 0
        extraTime = 0
        alertMessage = nil
        resume()
    }

    private func clear() {
        phase = .idle
        accumulated = 0
        phaseLength = 0
        extraTime = 0
    }

    @discardableResult
    private func restoreSuspended() -> Bool {
        guard let saved = suspended else { return false }
        // 예약 알림은 건드리지 않는다 (휴식이 자연스럽게 끝날 때 막 뜨려는 알림을 지우지 않도록)
        stopTicking()
        phase = .focus
        phaseLength = saved.phaseLength
        accumulated = saved.accumulated
        extraTime = saved.extraTime
        suspended = nil
        return true
    }

    /// 끝나는 시각에 맞춰 mac 알림을 미리 예약한다. 앱이 뒤에 있어도 제시간에 뜬다.
    private func scheduleEndNotification() {
        guard remaining > 0 else { return }
        switch phase {
        case .focus:
            let title = extraTime > 0 ? "⏰ 추가 시간 종료" : "⏰ 풀이 시간 종료"
            Notifier.schedule(title: title, body: "추가 시간을 줄지, 휴식할지 골라 주세요.", after: remaining)
        case .rest:
            let body = suspended == nil ? "다음 문제를 시작해 볼까요?" : "풀던 문제로 돌아갈 시간이에요."
            Notifier.schedule(title: "☕️ 휴식 끝", body: body, after: remaining)
        case .idle:
            break
        }
    }

    private func stopTicking() {
        if isRunning {
            now = Date()
            accumulated = elapsed
        }
        segmentStart = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func startTicking() {
        ticker?.cancel()
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "포모도로 타이머 실행 중"
            )
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                // 멈춘 뒤에 남은 타이머가 한 번 더 도는 것을 막는다
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        now = Date()
        guard isRunning, elapsed >= phaseLength else { return }

        // mac 알림은 이미 예약돼 있으므로 여기서는 타이머를 멈추고 앱 안 표시만 처리한다
        stopTicking()
        accumulated = phaseLength

        switch phase {
        case .focus:
            alertMessage = nil  // 타이머 화면에 선택 패널이 뜬다
        case .rest:
            if restoreSuspended() {
                alertMessage = "휴식이 끝났어요. 추가 시간을 주고 이어서 풀어 보세요."
            } else {
                clear()
                alertMessage = "휴식이 끝났어요. 다음 문제를 시작해 볼까요?"
            }
        case .idle:
            return
        }
        Notifier.requestAttention()
        openMainWindow?()
    }
}

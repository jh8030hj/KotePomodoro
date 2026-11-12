import SwiftUI
import AppKit
import UserNotifications

struct TimerView: View {
    @Environment(TimerModel.self) private var timer
    @AppStorage(SettingsKey.focusMinutes) private var focusMinutes = 40
    @State private var pending: PendingRecord?
    @State private var notificationsBlocked = false
    @State private var customExtra = 20

    struct PendingRecord: Identifiable {
        let id = UUID()
        let duration: TimeInterval
        let result: SolveResult
    }

    private var tint: Color {
        switch timer.phase {
        case .rest: .green
        case .focus: timer.isTimeUp || timer.isInExtraTime ? .orange : .red
        case .idle: .secondary
        }
    }

    private var title: String {
        let base = switch timer.phase {
        case .idle: "준비"
        case .focus where timer.isTimeUp: timer.isInExtraTime ? "추가 시간 종료" : "풀이 시간 종료"
        case .focus: timer.isInExtraTime ? "추가 시간" : "문제 푸는 중"
        case .rest: "휴식 중"
        }
        let paused = timer.phase != .idle && !timer.isRunning && !timer.isTimeUp
        return paused ? "\(base) (일시정지)" : base
    }

    private var timeText: String {
        switch timer.phase {
        case .idle: clockString(TimeInterval(max(focusMinutes, 1) * 60))
        default: clockString(timer.remaining)
        }
    }

    private var subtitle: String {
        switch timer.phase {
        case .idle:
            "풀이 \(focusMinutes)분"
        case .focus:
            if timer.isInExtraTime {
                "추가 +\(Int(timer.extraTime / 60))분 · 푼 시간 " + durationString(timer.elapsed)
            } else {
                "푼 시간 " + durationString(timer.elapsed)
            }
        case .rest:
            if let solved = timer.suspendedElapsed {
                "풀던 문제 " + durationString(solved) + " 진행"
            } else {
                "잠깐 쉬어요"
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("시간 설정")
            }

            if notificationsBlocked {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                    Text("mac 알림이 꺼져 있어서 시간이 끝나도 알림이 안 떠요.")
                        .font(.callout)
                    Spacer(minLength: 0)
                    Button("알림 켜기") {
                        Task {
                            await Notifier.enable()
                            notificationsBlocked = await Notifier.isBlocked()
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            ring
                .frame(width: timer.isTimeUp ? 150 : 210, height: timer.isTimeUp ? 150 : 210)
                .animation(.easeInOut(duration: 0.25), value: timer.isTimeUp)

            Spacer(minLength: 0)

            controls
        }
        .padding(20)
        .overlay(alignment: .top) {
            if let message = timer.alertMessage {
                AlertBanner(message: message, tint: tint) {
                    timer.alertMessage = nil
                }
                .padding(12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: timer.alertMessage)
        .task {
            if await Notifier.authorizationStatus() == .notDetermined {
                await Notifier.requestPermission()
            }
            notificationsBlocked = await Notifier.isBlocked()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { notificationsBlocked = await Notifier.isBlocked() }
        }
        .sheet(item: $pending) { item in
            RecordSheet(
                duration: item.duration,
                initialResult: item.result,
                onSave: {
                    pending = nil
                    timer.reset()
                },
                onCancel: { pending = nil }
            )
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: timer.phase == .idle ? 0 : timer.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            VStack(spacing: 6) {
                Text(timeText)
                    .font(.system(size: timer.isTimeUp ? 32 : 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            VStack(spacing: 10) {
                Button {
                    timer.startFocus()
                } label: {
                    Label("문제 풀기 시작", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    timer.startRest()
                } label: {
                    Label("휴식 시작", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)

        case .focus where timer.isTimeUp:
            timeUpPanel

        case .focus:
            VStack(spacing: 10) {
                finishButtons
                HStack(spacing: 10) {
                    pauseButton
                    Button {
                        timer.reset()
                    } label: {
                        Text("기록 없이 그만두기").frame(maxWidth: .infinity)
                    }
                }
            }
            .controlSize(.large)

        case .rest:
            HStack(spacing: 10) {
                pauseButton
                if timer.suspendedElapsed != nil {
                    Button {
                        timer.returnToProblem()
                    } label: {
                        Label("문제로 돌아가기", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        timer.reset()
                    } label: {
                        Text("휴식 건너뛰기").frame(maxWidth: .infinity)
                    }
                }
            }
            .controlSize(.large)
        }
    }

    /// 시간이 끝났을 때: 추가 시간 / 휴식 / 기록 중에서 고르기
    private var timeUpPanel: some View {
        VStack(spacing: 10) {
            Text("추가 시간을 줄까요, 휴식할까요?")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach([5, 10, 15], id: \.self) { minutes in
                    Button {
                        timer.addExtraTime(minutes: minutes)
                    } label: {
                        Text("+\(minutes)분").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            HStack(spacing: 6) {
                TextField("분", value: $customExtra, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .onSubmit(addCustomExtra)
                Text("분")
                Button {
                    addCustomExtra()
                } label: {
                    Text("직접 입력해서 추가").frame(maxWidth: .infinity)
                }
                .disabled(customExtra < 1)
            }

            Button {
                timer.takeBreak()
            } label: {
                Label("휴식하기", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            finishButtons

            Button("기록 없이 그만두기") {
                timer.reset()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .controlSize(.large)
    }

    private var finishButtons: some View {
        HStack(spacing: 10) {
            Button {
                finish(.success)
            } label: {
                Label("다 풀었어요", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.green)

            Button {
                finish(.fail)
            } label: {
                Label("포기", systemImage: "xmark").frame(maxWidth: .infinity)
            }
        }
    }

    private var pauseButton: some View {
        Button {
            timer.isRunning ? timer.pause() : timer.resume()
        } label: {
            Label(timer.isRunning ? "일시정지" : "계속", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.space, modifiers: [])
    }

    private func addCustomExtra() {
        let minutes = min(max(customExtra, 1), 180)
        customExtra = minutes
        timer.addExtraTime(minutes: minutes)
    }

    private func finish(_ result: SolveResult) {
        timer.pause()
        timer.alertMessage = nil
        pending = PendingRecord(duration: timer.elapsed, result: result)
    }
}

private struct AlertBanner: View {
    let message: String
    let tint: Color
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill").foregroundStyle(tint)
            Text(message).font(.callout.weight(.medium))
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.5)))
        .shadow(radius: 4, y: 2)
    }
}

#Preview {
    TimerView()
        .environment(TimerModel())
        .frame(width: 420, height: 620)
}

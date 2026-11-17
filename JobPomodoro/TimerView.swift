import SwiftUI
import SwiftData
import AppKit
import UserNotifications

struct TimerView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(AppState.self) private var appState
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]
    @Query(filter: #Predicate<TodoItem> { !$0.isDone }, sort: \TodoItem.createdAt) private var openTodos: [TodoItem]
    @Query private var sessions: [WorkSession]

    @State private var pending: SessionDraft?
    @State private var notificationsBlocked = false
    @State private var customExtra = 20

    /// 타이머 전: 고른 카테고리 / 타이머 중: 재고 있는 카테고리
    private var category: TaskCategory? {
        if let key = timer.categoryKey { return categories.category(key) }
        return categories.active.category(appState.selectedCategoryKey) ?? categories.active.first
    }

    private var form: CategoryForm { category?.form ?? CategoryKind.custom.form }
    private var isStopwatchCategory: Bool { form.timerMode == .stopwatch }
    private var restMinutes: Int { max(category?.restMinutes ?? 5, 1) }

    private var tint: Color {
        switch timer.phase {
        case .rest: .green
        case .focus: timer.isTimeUp || timer.isInExtraTime ? .orange : (category?.color ?? .red)
        case .idle: category?.color ?? .secondary
        }
    }

    private var title: String {
        let base = switch timer.phase {
        case .idle: "준비"
        case .focus where timer.isTimeUp: timer.isInExtraTime ? "추가 시간 종료" : "시간 종료"
        case .focus: timer.isInExtraTime ? "추가 시간" : form.runningTitle
        case .rest: "휴식 중"
        }
        let paused = timer.phase != .idle && !timer.isRunning && !timer.isTimeUp
        return paused ? "\(base) (일시정지)" : base
    }

    private var timeText: String {
        switch timer.phase {
        case .idle: isStopwatchCategory ? clockString(0) : clockString(TimeInterval(max(category?.focusMinutes ?? 25, 1) * 60))
        case .focus where timer.isStopwatch: clockString(timer.elapsed.rounded(.down))
        default: clockString(timer.remaining)
        }
    }

    private var subtitle: String {
        switch timer.phase {
        case .idle:
            isStopwatchCategory ? "스톱워치" : "집중 \(category?.focusMinutes ?? 25)분 · 휴식 \(restMinutes)분"
        case .focus:
            if timer.isStopwatch {
                timer.isRunning ? "끝나면 기록을 눌러 주세요" : "멈춤"
            } else if timer.isInExtraTime {
                "추가 +\(Int(timer.extraTime / 60))분 · 한 시간 " + durationString(timer.elapsed)
            } else {
                "한 시간 " + durationString(timer.elapsed)
            }
        case .rest:
            if let done = timer.suspendedElapsed {
                "하던 일 " + durationString(done) + " 진행"
            } else {
                "잠깐 쉬어요"
            }
        }
    }

    /// 오늘 집중한 시간 (전체, 지금 카테고리)
    private var todayTotals: (all: TimeInterval, category: TimeInterval) {
        let today = sessions.filter { Calendar.current.isDateInToday($0.date) }
        let all = today.map(\.duration).reduce(0, +)
        let mine = today.filter { $0.categoryKey == category?.key }.map(\.duration).reduce(0, +)
        return (all, mine)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("카테고리·타이머 설정")
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

            if timer.phase == .idle {
                categoryPicker
            } else {
                activeHeader
            }

            todaySummary

            Spacer(minLength: 0)

            ring
                .frame(width: timer.isTimeUp ? 140 : 200, height: timer.isTimeUp ? 140 : 200)
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
            SessionSheet(
                draft: item,
                onSave: {
                    if !item.isManual {
                        timer.reset()
                        appState.selectedTodoID = nil
                    }
                    pending = nil
                },
                onCancel: { pending = nil }
            )
        }
    }

    // MARK: - 위쪽

    private var categoryPicker: some View {
        @Bindable var appState = appState
        let todos = openTodos.filter { $0.categoryKey == category?.key }
        let categoryBinding = Binding<String>(
            get: { category?.key ?? appState.selectedCategoryKey },
            set: {
                appState.selectedCategoryKey = $0
                appState.selectedTodoID = nil
            }
        )
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("카테고리").foregroundStyle(.secondary)
                Picker("카테고리", selection: categoryBinding) {
                    ForEach(categories.active) { item in
                        Label(item.name, systemImage: item.symbol).tag(item.key)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !todos.isEmpty {
                GridRow {
                    Text("할 일").foregroundStyle(.secondary)
                    Picker("할 일", selection: $appState.selectedTodoID) {
                        Text("선택 안 함").tag(UUID?.none)
                        ForEach(todos) { todo in
                            Text(todo.title).tag(Optional(todo.uid))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 타이머가 도는 중: 카테고리와 할 일 표시
    private var activeHeader: some View {
        HStack(spacing: 8) {
            CategoryBadge(category: category, font: .callout.weight(.semibold))
            if let id = timer.todoID, let todo = openTodos.first(where: { $0.uid == id }) {
                Text("· " + todo.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var todaySummary: some View {
        let totals = todayTotals
        let goal = TimeInterval((category?.todayGoalMinutes ?? 0) * 60)
        return HStack(spacing: 6) {
            Text("오늘 " + durationString(totals.all))
            if let category {
                Text("·")
                Text("\(category.name) " + durationString(totals.category) + (goal > 0 ? " / " + durationString(goal) : ""))
                if goal > 0 {
                    ProgressView(value: min(totals.category / goal, 1))
                        .tint(category.color)
                        .frame(width: 60)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
                    .font(.system(size: timer.isTimeUp ? 30 : 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 버튼

    @ViewBuilder
    private var controls: some View {
        switch timer.phase {
        case .idle:
            VStack(spacing: 10) {
                Button(action: start) {
                    Label(form.startTitle, systemImage: isStopwatchCategory ? "stopwatch" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(category?.color ?? .red)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(category == nil)

                HStack(spacing: 10) {
                    Button {
                        timer.startRest(minutes: restMinutes)
                    } label: {
                        Label("휴식 시작", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
                    }
                    Button {
                        guard let category else { return }
                        pending = SessionDraft(categoryKey: category.key, duration: 0,
                                               todoID: appState.selectedTodoID, isManual: true)
                    } label: {
                        Label("직접 기록", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .disabled(category == nil)
                }
            }
            .controlSize(.large)

        case .focus where timer.isTimeUp:
            timeUpPanel

        case .focus:
            VStack(spacing: 10) {
                finishButtons
                if !timer.isRunning && !timer.isStopwatch {
                    // 일시정지 중: 이어서 하거나, 바로 휴식으로 넘어가기
                    HStack(spacing: 10) {
                        pauseButton
                        Button {
                            timer.takeBreak(minutes: restMinutes)
                        } label: {
                            Label("휴식하기 (\(restMinutes)분)", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    Button("기록 없이 그만두기") {
                        timer.reset()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        pauseButton
                        Button {
                            timer.reset()
                        } label: {
                            Text("기록 없이 그만두기").frame(maxWidth: .infinity)
                        }
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
                        Label("하던 일로 돌아가기", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(category?.color ?? .red)
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
                timer.takeBreak(minutes: restMinutes)
            } label: {
                Label("휴식하기 (\(restMinutes)분)", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
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

    /// 코테는 성공/포기, 나머지는 끝내고 기록
    @ViewBuilder
    private var finishButtons: some View {
        if form.outcomes == ["성공", "실패"] {
            HStack(spacing: 10) {
                Button {
                    finish(outcome: "성공")
                } label: {
                    Label("다 풀었어요", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(.green)

                Button {
                    finish(outcome: "실패")
                } label: {
                    Label("포기", systemImage: "xmark").frame(maxWidth: .infinity)
                }
            }
        } else {
            Button {
                finish(outcome: nil)
            } label: {
                Label("끝내고 기록", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.green)
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

    private func start() {
        guard let category else { return }
        timer.start(category, todoID: appState.selectedTodoID)
    }

    private func addCustomExtra() {
        let minutes = min(max(customExtra, 1), 180)
        customExtra = minutes
        timer.addExtraTime(minutes: minutes)
    }

    private func finish(outcome: String?) {
        guard let key = timer.categoryKey else { return }
        timer.pause()
        timer.alertMessage = nil
        pending = SessionDraft(categoryKey: key, duration: timer.elapsed, outcome: outcome, todoID: timer.todoID)
    }
}

extension TimerModel {
    /// 카테고리 방식에 맞춰 포모도로 또는 스톱워치 시작
    func start(_ category: TaskCategory, todoID: UUID?) {
        if category.form.timerMode == .stopwatch {
            startStopwatch(categoryKey: category.key, categoryName: category.name, todoID: todoID)
        } else {
            startFocus(categoryKey: category.key, categoryName: category.name,
                       minutes: category.focusMinutes, todoID: todoID)
        }
    }

    /// 지금 상태를 사람이 읽을 수 있게 (할 일 탭 안내용)
    var statusText: String {
        switch phase {
        case .idle: "대기 중"
        case .rest: "휴식 중"
        case .focus where isTimeUp: "\(categoryName) 시간이 끝나 다음 선택을 기다리는 중"
        case .focus: isRunning ? "\(categoryName) 타이머가 진행 중" : "\(categoryName) 타이머가 일시정지된 상태"
        }
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
        .environment(AppState())
        .modelContainer(for: AppSchema.models, inMemory: true)
        .frame(width: 440, height: 640)
}

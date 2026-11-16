import SwiftData
import SwiftUI
import WidgetKit

// MARK: - 시작

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var showPermissions = false
    @State private var working = false

    var body: some View {
        VStack {
            if showPermissions { permissions } else { start }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tone.bg)
    }

    private var start: some View {
        VStack {
            Spacer()
            Text("POCKET").font(.system(size: 64, weight: .bold)).foregroundStyle(Tone.ink)
            Text("말하면 할 일과 일정으로 정리해요").font(.pBody).foregroundStyle(Tone.ink2)
            Spacer()
            ActionButton(title: "시작하기", fullWidth: true) { showPermissions = true }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이 권한을 쓸게요").font(.pDisplay).foregroundStyle(Tone.ink).padding(.top, 16)
            Text("거부해도 다른 기능은 그대로 쓸 수 있어요.").font(.pBody).foregroundStyle(Tone.ink2)
            row("mic", "마이크", "말로 할 일과 메모를 입력해요")
            row("sparkle", "음성 인식", "말을 글자로 바꿔요")
            row("calendar", "캘린더", "일정을 iOS 캘린더에도 넣어요")
            row("bell", "알림", "정해 둔 시간에 알려 드려요")
            Spacer()
            ActionButton(title: "계속", fullWidth: true) {
                guard !working else { return }
                working = true
                Task {
                    _ = await SpeechService.requestPermissions()
                    _ = await CalendarService.requestAccess()
                    _ = await NotificationService.requestAccess()
                    onFinish()
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Tone.ink).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.pBodyMedium).foregroundStyle(Tone.ink)
                Text(detail).font(.pCaption).foregroundStyle(Tone.ink2)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - 집중

struct FocusView: View {
    let todoID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingKey.defaultTimer) private var defaultTimer = 25
    @State private var todo: TodoItem?
    @State private var clock = FocusClock(mode: .stopwatch)
    @State private var isTimer = true
    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            header
            VStack(spacing: 4) {
                Text(todo?.title ?? "").font(.pHeadline).foregroundStyle(Tone.ink).multilineTextAlignment(.center)
                Text(hint).font(.pCaption).foregroundStyle(Tone.ink2)
            }
            ring
            controls
            subtasks
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Tone.bg)
        .onAppear(perform: load)
        .onReceive(ticker) { date in
            now = date
            clock.tick(at: date)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now; clock.tick(at: now) }
        }
    }

    private var header: some View {
        HStack {
            IconButton(symbol: "xmark", label: "닫기") {
                recordFocus()
                try? context.save()
                NotificationService.cancelTimerEnd()
                dismiss()
            }
            Spacer()
            HStack(spacing: 0) {
                segment("타이머", active: isTimer) { switchMode(timer: true) }
                segment("스톱워치", active: !isTimer) { switchMode(timer: false) }
            }
            .padding(4)
            .background(Tone.surface, in: Capsule())
            Spacer()
            ActionButton(title: "완료", kind: .secondary, action: complete)
        }
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pBodyMedium)
                .foregroundStyle(active ? Tone.ink : Tone.ink3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(active ? Tone.accentSoft : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(clock.phase == .ended ? Tone.ink : Tone.line, lineWidth: 14)
            if isTimer, clock.phase == .running || clock.phase == .paused {
                Circle()
                    .trim(from: 0, to: clock.progress(at: now))
                    .stroke(Tone.ink, lineWidth: 14)
                    .rotationEffect(.degrees(-90))
            }
            Text(Format.timer(seconds: clock.displaySeconds(at: now)))
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Tone.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 24)
        }
        .frame(width: 256, height: 256)
        .padding(7)
    }

    @ViewBuilder private var controls: some View {
        switch clock.phase {
        case .idle:
            ActionButton(title: "시작", action: start).frame(width: 180)
        case .running:
            ActionButton(title: "일시정지", symbol: "pause") {
                clock.pause(at: .now)
                NotificationService.cancelTimerEnd()
            }
            .frame(width: 180)
        case .paused:
            HStack(spacing: 8) {
                ActionButton(title: "처음부터", kind: .secondary, fullWidth: true) {
                    recordFocus()
                    clock.reset()
                }
                ActionButton(title: "계속", symbol: "play", fullWidth: true, action: start)
            }
            .frame(maxWidth: 328)
        case .ended:
            HStack(spacing: 8) {
                ActionButton(title: "10분 더", kind: .secondary, fullWidth: true) {
                    clock.extend(seconds: 600, at: .now)
                    NotificationService.scheduleTimerEnd(title: todo?.title ?? "", after: 600)
                }
                ActionButton(title: "완료하기", fullWidth: true, action: complete)
            }
            .frame(maxWidth: 328)
        }
    }

    @ViewBuilder private var subtasks: some View {
        if let todo, !todo.subtasks.isEmpty {
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Text("하위 작업").font(.pBodyMedium).foregroundStyle(Tone.ink)
                        Spacer()
                        Text("\(todo.subtasks.filter(\.isDone).count) / \(todo.subtasks.count)")
                            .font(.pCaption).foregroundStyle(Tone.ink3)
                    }
                    ForEach(todo.orderedSubtasks) { sub in
                        HStack {
                            Text(sub.title).font(.pBody)
                                .strikethrough(sub.isDone)
                                .foregroundStyle(sub.isDone ? Tone.ink3 : Tone.ink)
                            Spacer()
                            CheckCircle(isOn: sub.isDone) {
                                sub.isDone.toggle()
                                try? context.save()
                            }
                        }
                        .card()
                    }
                }
            }
        }
    }

    private var hint: String {
        switch clock.phase {
        case .idle:
            guard isTimer, let end = clock.endDate(at: now) else { return "시간 제한 없이 집중한 만큼 기록해요" }
            return "지금 시작하면 \(Format.clock(end))에 끝나요"
        case .running:
            guard isTimer, let end = clock.endDate(at: now) else { return "집중한 시간을 기록하는 중이에요" }
            return "\(Format.clock(end))에 끝나요"
        case .paused: return "일시정지 중이에요"
        case .ended: return "시간이 다 됐어요"
        }
    }

    private var timerSeconds: Int { (todo?.estimateMinutes ?? defaultTimer) * 60 }

    private func load() {
        let id = todoID
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
        todo = try? context.fetch(descriptor).first
        clock = FocusClock(mode: .timer(total: timerSeconds))
    }

    private func start() {
        clock.start(at: .now)
        if isTimer, let end = clock.endDate(at: .now) {
            NotificationService.scheduleTimerEnd(title: todo?.title ?? "", after: Int(end.timeIntervalSinceNow))
        }
    }

    private func switchMode(timer: Bool) {
        guard timer != isTimer, clock.phase == .idle else { return }
        isTimer = timer
        clock = FocusClock(mode: timer ? .timer(total: timerSeconds) : .stopwatch)
    }

    /// 지난 시간을 할 일에 쌓는다. 시계를 닫거나 처음으로 돌릴 때 한 번씩만 부른다.
    private func recordFocus() {
        todo?.focusedSeconds += clock.elapsed(at: .now)
    }

    /// "완료"는 시간 기록만 끝내지 않고 할 일까지 완료 처리한다.
    private func complete() {
        recordFocus()
        NotificationService.cancelTimerEnd()
        if let todo {
            todo.setDone(true)
            Task { await TodoSync.afterChange(todo, in: context) }
        }
        dismiss()
    }
}

// MARK: - 설정

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.calendar) private var calendarEnabled = true
    @AppStorage(SettingKey.notifications) private var notificationsEnabled = true
    @AppStorage(SettingKey.defaultTimer) private var defaultTimer = 25
    @State private var editingKey = false
    @State private var keySet = KeychainStore.apiKey != nil

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("설정").font(.pDisplay).foregroundStyle(Tone.ink)
                Spacer()
                IconButton(symbol: "xmark", label: "닫기") { dismiss() }
            }
            VStack(spacing: 0) {
                FieldRow(label: "Claude API 키", value: keySet ? "설정됨" : "없음") { editingKey = true }
                    .frame(minHeight: 46)
                toggle("iOS 캘린더에 넣기", $calendarEnabled)
                toggle("알림", $notificationsEnabled)
                HStack {
                    Text("기본 타이머").font(.pBody).foregroundStyle(Tone.ink)
                    Spacer()
                    Menu {
                        ForEach([15, 25, 30, 45, 60], id: \.self) { minutes in
                            Button("\(minutes)분") { defaultTimer = minutes }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(defaultTimer)분").font(.pBody).foregroundStyle(Tone.ink2)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink3)
                        }
                    }
                }
                .frame(minHeight: 46)
            }
            .card(padding: 16)
            HStack {
                Text("버전").font(.pBody).foregroundStyle(Tone.ink)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").font(.pBody).foregroundStyle(Tone.ink2)
            }
            .card()
            if !PocketStore.isShared {
                Text("위젯과 데이터를 나눌 수 없는 계정이에요. 위젯에 할 일이 보이지 않을 수 있어요.")
                    .font(.pCaption).foregroundStyle(Tone.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(16)
        .background(Tone.bg)
        .presentationCornerRadius(20)
        .sheet(isPresented: $editingKey, onDismiss: { keySet = KeychainStore.apiKey != nil }) { ApiKeySheet() }
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { Text(title).font(.pBody).foregroundStyle(Tone.ink) }
            .tint(Tone.ink)
            .frame(minHeight: 46)
    }
}

struct ApiKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = KeychainStore.apiKey != nil
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: 12) {
            SheetHeader(title: "Claude API 키", onClose: { dismiss() }) {
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { dismiss(); return }
                if KeychainStore.save(trimmed) { dismiss() } else { saveFailed = true }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("API 키").font(.pCaption).foregroundStyle(Tone.ink2)
                SecureField(hasKey ? "저장된 키가 있어요. 입력하면 바꿔요" : "sk-ant-...", text: $key)
                    .font(.pBody)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .card()
            Text(saveFailed ? "저장하지 못했어요. 다시 시도해 주세요." : "키는 이 폰의 키체인에만 저장돼요. 폰을 잃어버리면 Anthropic 콘솔에서 키를 폐기하세요.")
                .font(.pCaption).foregroundStyle(Tone.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hasKey {
                ActionButton(title: "키 지우기", kind: .secondary, fullWidth: true) {
                    KeychainStore.delete()
                    dismiss()
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Tone.bg)
        .presentationDetents([.medium])
        .presentationCornerRadius(20)
    }
}

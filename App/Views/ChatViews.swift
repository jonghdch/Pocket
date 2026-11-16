import SwiftData
import SwiftUI
import WidgetKit

struct ChatView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]
    @StateObject private var speech = SpeechService()
    @State private var input = ""
    @State private var loading = false
    @State private var failure: Failure?
    @FocusState private var inputFocused: Bool

    private struct Failure: Equatable {
        var message: String
        var retry: Retry
    }

    private enum Retry: Equatable {
        case send(String), breakdown(UUID), voice
    }

    private var composerVisible: Bool { speech.isListening || speech.failure == .noSpeech }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !network.isOnline { Banner() }
                        if messages.isEmpty && !loading && failure == nil {
                            EmptyState(symbol: "bubble.left", title: "무엇이든 말해 보세요", caption: "\"내일 3시 치과 예약\"처럼 말하면 일정으로 넣어요")
                        }
                        ForEach(messages) { message in
                            ChatRow(message: message, todos: todos, onMore: moreSteps)
                        }
                        if loading { TypingBubble() }
                        if let failure {
                            NoticeCard(message: failure.message) { retry(failure.retry) }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: loading) { withAnimation { proxy.scrollTo("bottom") } }
                .onAppear { proxy.scrollTo("bottom") }
            }
            bottomBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, inputFocused ? 8 : tabBarClearance)
        }
        .onAppear(perform: consumeRequests)
        .onChange(of: router.chatVoicePending) { consumeRequests() }
        .onChange(of: router.chatText) { consumeRequests() }
        .onChange(of: router.breakdownRequest) { consumeRequests() }
        .onChange(of: speech.failure) { _, failure in
            if failure == .denied {
                router.permission = .microphone
                speech.failure = nil
            } else if failure == .unavailable {
                self.failure = Failure(message: "지금은 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요.", retry: .voice)
                speech.failure = nil
            }
        }
        .onChange(of: speech.transcript) { _, text in
            guard speech.isListening, let remainder = MemoTrigger.remainder(in: text) else { return }
            speech.discard()
            router.voiceMemo = .new(initial: remainder)
        }
        .onChange(of: inputFocused) { _, focused in router.hidesTabBar = focused }
        .onDisappear {
            speech.discard()
            router.hidesTabBar = false
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if composerVisible {
            VoiceComposer(speech: speech, onDiscard: { speech.discard() }, onSend: sendVoice, onRetry: startVoice)
        } else {
            HStack(spacing: 8) {
                TextField("말하거나 입력해 보세요", text: $input, axis: .vertical)
                    .font(.pBody)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                RoundButton(symbol: hasText ? "arrow.up" : "mic", size: 40, label: hasText ? "보내기" : "말하기") {
                    if hasText {
                        let text = input
                        input = ""
                        inputFocused = false
                        send(text)
                    } else {
                        startVoice()
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Tone.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Tone.ink, lineWidth: 1))
        }
    }

    private func consumeRequests() {
        if router.chatVoicePending {
            router.chatVoicePending = false
            startVoice()
        }
        if let text = router.chatText {
            router.chatText = nil
            send(text)
        }
        if let id = router.breakdownRequest {
            router.breakdownRequest = nil
            breakdown(id)
        }
    }

    private func startVoice() {
        inputFocused = false
        failure = nil
        Task { await speech.start() }
    }

    private func sendVoice() {
        let text = speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return } // noSpeech 상태로 남아 다시 말하기를 보여 준다.
        speech.failure = nil
        send(text)
    }

    private func send(_ text: String) {
        context.insert(ChatMessage(isMine: true, text: text))
        try? context.save()
        run(text)
    }

    private func run(_ text: String) {
        failure = nil
        loading = true
        Task {
            defer { loading = false }
            do {
                let plan = try await ClaudeClient().plan(text: text, todos: PlanApplier.describe(todos))
                let (result, changed) = try PlanApplier.apply(plan, in: context)
                var calendarOK = true
                for todo in changed {
                    let ok = await TodoSync.afterChange(todo, in: context)
                    calendarOK = calendarOK && ok
                }
                let hasResult = !result.created.isEmpty || !result.touched.isEmpty
                var previews = SeriesPlanner.drafts(from: plan).map { ChatPayload.series(.init(draft: $0, created: [], undone: false)) }
                let buys = BuyPlanner.clean(plan.buys ?? [])
                if !buys.isEmpty { previews.append(.buys(.init(items: buys, created: [], undone: false))) }
                let first: ChatPayload? = hasResult ? .result(result) : (previews.isEmpty ? nil : previews.removeFirst())
                context.insert(ChatMessage(isMine: false, text: plan.reply, payload: first?.encoded))
                for payload in previews {
                    let text: String
                    switch payload {
                    case .series(let preview): text = "\(preview.draft.title)도 확인해 주세요."
                    default: text = "살 것도 확인해 주세요."
                    }
                    context.insert(ChatMessage(isMine: false, text: text, payload: payload.encoded))
                }
                try? context.save()
                if !calendarOK && CalendarService.isDenied { router.permission = .calendar }
            } catch {
                failure = Failure(message: (error as? AIError ?? .badResponse).message, retry: .send(text))
            }
        }
    }

    private func breakdown(_ id: UUID) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        context.insert(ChatMessage(isMine: true, text: "\(todo.title) 나눠 줘"))
        try? context.save()
        requestSteps(id)
    }

    private func requestSteps(_ id: UUID, extra: [String] = []) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        failure = nil
        loading = true
        let title = todo.title
        let existing = todo.orderedSubtasks.map(\.title) + extra
        Task {
            defer { loading = false }
            do {
                let steps = try await ClaudeClient().breakDown(title: title, existing: existing)
                let payload = ChatPayload.breakdown(.init(todoID: id, steps: steps, saved: false))
                context.insert(ChatMessage(
                    isMine: false, text: "이렇게 나눠 봤어요. 확인하고 고쳐 주시면 하위 작업으로 저장할게요.",
                    payload: payload.encoded))
                try? context.save()
            } catch {
                failure = Failure(message: (error as? AIError ?? .badResponse).message, retry: .breakdown(id))
            }
        }
    }

    private func moreSteps(_ id: UUID, _ steps: [String]) { requestSteps(id, extra: steps) }

    private func retry(_ action: Retry) {
        switch action {
        case .send(let text): run(text)
        case .breakdown(let id): requestSteps(id)
        case .voice: startVoice()
        }
    }
}

struct ChatRow: View {
    let message: ChatMessage
    let todos: [TodoItem]
    let onMore: (UUID, [String]) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ChatBubble(text: message.text, isMine: message.isMine)
            switch ChatPayload.decode(message.payload) {
            case .result(let result): ResultCard(message: message, result: result, todos: todos)
            case .breakdown(let breakdown): BreakdownCard(message: message, breakdown: breakdown, todos: todos, onMore: onMore)
            case .series(let series): SeriesCard(message: message, series: series)
            case .buys(let buys): BuyCard(message: message, buys: buys)
            case nil: EmptyView()
            }
        }
    }
}

struct ChatBubble: View {
    let text: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 68) }
            Text(text)
                .font(.pBody)
                .foregroundStyle(isMine ? Tone.onAccent : Tone.ink)
                .padding(16)
                .frame(maxWidth: isMine ? nil : .infinity, alignment: .leading)
                .background(isMine ? Tone.ink : Tone.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct TypingBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([1.0, 0.6, 0.3], id: \.self) { opacity in
                Circle().fill(Tone.ink2).opacity(opacity).frame(width: 6, height: 6)
            }
            Text("정리하는 중이에요").font(.pBody).foregroundStyle(Tone.ink2)
        }
        .padding(16)
        .background(Tone.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoticeCard: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 20)).foregroundStyle(Tone.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("정리하지 못했어요").font(.pTitle).foregroundStyle(Tone.ink)
                    Text(message).font(.pCaption).foregroundStyle(Tone.ink2)
                }
            }
            ActionButton(title: "다시 시도", kind: .soft, symbol: "arrow.clockwise", fullWidth: true, action: retry)
        }
        .card()
    }
}

struct ResultCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    let message: ChatMessage
    let result: ChatPayload.Result
    let todos: [TodoItem]

    private var items: [TodoItem] {
        let ids = Set(result.created + result.touched)
        return todos.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.undone {
                Text("되돌렸어요").font(.pBody).foregroundStyle(Tone.ink2)
            } else {
                ForEach(items) { todo in
                    Button { router.edit = .existing(todo.id) } label: { row(todo) }
                        .buttonStyle(.plain)
                }
                HStack {
                    CheckMark(isOn: true)
                    Text("저장됨").font(.pCaption).foregroundStyle(Tone.ink2)
                    Spacer()
                    Button(action: undo) { Chip(text: "되돌리기", symbol: "arrow.uturn.backward") }
                        .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func row(_ todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: todo.isEvent ? "calendar" : "checkmark.square")
                    .frame(width: 40, height: 40)
                    .background(Tone.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(todo.title).font(.pTitle).foregroundStyle(Tone.ink).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            if let start = todo.scheduledAt {
                field("calendar", "날짜", Format.day(start))
                if todo.hasTime { field("clock", "시간", Format.range(start, todo.endAt)) }
            }
        }
        .contentShape(Rectangle())
    }

    private func field(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Tone.ink2).frame(width: 18)
            Text(label).font(.pBody).foregroundStyle(Tone.ink2)
            Text(value).font(.pBodyMedium).foregroundStyle(Tone.ink).padding(.leading, 16)
        }
    }

    private func undo() {
        guard let restored = try? PlanApplier.undo(result, in: context) else { return }
        var updated = result
        updated.undone = true
        message.payload = ChatPayload.result(updated).encoded
        try? context.save()
        Task { for todo in restored { await TodoSync.afterChange(todo, in: context) } }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct BreakdownCard: View {
    @Environment(\.modelContext) private var context
    let message: ChatMessage
    let breakdown: ChatPayload.Breakdown
    let todos: [TodoItem]
    let onMore: (UUID, [String]) -> Void
    @State private var editingIndex: Int?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(breakdown.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Text(step).font(.pBody).foregroundStyle(Tone.ink)
                    Spacer()
                    if !breakdown.saved {
                        Button {
                            editText = step
                            editingIndex = index
                        } label: {
                            Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Tone.ink3).frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("\(step) 고치기")
                    }
                }
            }
            if breakdown.saved {
                HStack {
                    CheckMark(isOn: true)
                    Text("하위 작업에 저장됨").font(.pCaption).foregroundStyle(Tone.ink2)
                    Spacer()
                }
            } else {
                ActionButton(title: "저장하기", fullWidth: true, action: save)
                Button { onMore(breakdown.todoID, breakdown.steps) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle").font(.system(size: 12))
                        Text("더 쪼개기").font(.pCaption)
                    }
                    .foregroundStyle(Tone.ink2)
                    .frame(minHeight: 32)
                }
            }
        }
        .card()
        .alert("하위 작업 고치기", isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            TextField("이름", text: $editText)
            Button("취소", role: .cancel) {}
            Button("확인", action: applyEdit)
        }
    }

    private func store(_ updated: ChatPayload.Breakdown) {
        message.payload = ChatPayload.breakdown(updated).encoded
        try? context.save()
    }

    private func applyEdit() {
        guard let index = editingIndex, !editText.isEmpty else { return }
        var updated = breakdown
        updated.steps[index] = editText
        store(updated)
    }

    private func save() {
        guard let todo = todos.first(where: { $0.id == breakdown.todoID }) else { return }
        var order = (todo.subtasks.map(\.order).max() ?? -1) + 1
        for step in breakdown.steps {
            todo.subtasks.append(Subtask(title: step, order: order))
            order += 1
        }
        var updated = breakdown
        updated.saved = true
        store(updated)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct SeriesCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: Router
    let message: ChatMessage
    let series: ChatPayload.Series
    @State private var showAll = false

    private static let preview = 7
    private var saved: Bool { !series.created.isEmpty }
    private var days: [SeriesDraft.Day] { series.draft.days }
    private var visible: ArraySlice<SeriesDraft.Day> { showAll ? days[...] : days.prefix(Self.preview) }

    private var span: String {
        guard let first = days.first.flatMap({ PlanDate.make(date: $0.date, time: nil) }),
              let last = days.last.flatMap({ PlanDate.make(date: $0.date, time: nil) }) else { return "" }
        return "\(Format.day(first)) ~ \(Format.day(last)) · \(days.count)개"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if series.undone {
                Text("되돌렸어요").font(.pBody).foregroundStyle(Tone.ink2)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "repeat")
                        .frame(width: 40, height: 40)
                        .background(Tone.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.draft.title).font(.pTitle).foregroundStyle(Tone.ink)
                        Text(span).font(.pCaption).foregroundStyle(Tone.ink2)
                    }
                }
                ForEach(Array(visible.enumerated()), id: \.offset) { index, day in row(day, index: index) }
                if days.count > Self.preview {
                    Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                        Text(showAll ? "접기" : "\(days.count - Self.preview)개 더 보기")
                            .font(.pCaption).foregroundStyle(Tone.ink2).frame(minHeight: 32)
                    }
                }
                if saved {
                    HStack {
                        CheckMark(isOn: true)
                        Text("\(series.created.count)개 저장됨").font(.pCaption).foregroundStyle(Tone.ink2)
                        Spacer()
                        Button(action: undo) { Chip(text: "되돌리기", symbol: "arrow.uturn.backward") }
                            .buttonStyle(.plain)
                    }
                } else {
                    ActionButton(title: "\(days.count)개 추가하기", fullWidth: true, action: save)
                }
            }
        }
        .card()
    }

    private func row(_ day: SeriesDraft.Day, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(PlanDate.make(date: day.date, time: nil).map(Format.day) ?? day.date)
                .font(.pCaption).foregroundStyle(Tone.ink2)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title).font(.pBody).foregroundStyle(Tone.ink)
                if let time = day.start_time {
                    Text([time, day.end_time].compactMap { $0 }.joined(separator: " ~ "))
                        .font(.pCaption).foregroundStyle(Tone.ink2)
                }
            }
            Spacer(minLength: 0)
            if !saved && days.count > 1 {
                Button { remove(at: index) } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Tone.ink3).frame(width: 32, height: 32)
                }
                .accessibilityLabel("\(day.title) 빼기")
            }
        }
    }

    private func store(_ updated: ChatPayload.Series) {
        message.payload = ChatPayload.series(updated).encoded
        try? context.save()
    }

    private func remove(at index: Int) {
        var updated = series
        updated.draft.days.remove(at: index)
        store(updated)
    }

    private func save() {
        guard let created = try? SeriesApplier.save(series.draft, in: context), !created.isEmpty else { return }
        var updated = series
        updated.created = created.map(\.id)
        store(updated)
        Task {
            var calendarOK = true
            for todo in created {
                let ok = await TodoSync.afterChange(todo, in: context)
                calendarOK = calendarOK && ok
            }
            if !calendarOK && CalendarService.isDenied { router.permission = .calendar }
        }
    }

    private func undo() {
        let result = ChatPayload.Result(created: series.created, before: [], touched: [], undone: false)
        guard (try? PlanApplier.undo(result, in: context)) != nil else { return }
        var updated = series
        updated.undone = true
        store(updated)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct BuyCard: View {
    @Environment(\.modelContext) private var context
    let message: ChatMessage
    let buys: ChatPayload.Buys

    private var saved: Bool { !buys.created.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if buys.undone {
                Text("되돌렸어요").font(.pBody).foregroundStyle(Tone.ink2)
            } else {
                ForEach(Array(buys.items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Text(BuyPlanner.label(item)).font(.pBody).foregroundStyle(Tone.ink)
                        Spacer(minLength: 0)
                        if !saved && buys.items.count > 1 {
                            Button { remove(at: index) } label: {
                                Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Tone.ink3).frame(width: 32, height: 32)
                            }
                            .accessibilityLabel("\(item.name) 빼기")
                        }
                    }
                }
                if saved {
                    HStack {
                        CheckMark(isOn: true)
                        Text("Buy에 \(buys.created.count)개 저장됨").font(.pCaption).foregroundStyle(Tone.ink2)
                        Spacer()
                        Button(action: undo) { Chip(text: "되돌리기", symbol: "arrow.uturn.backward") }
                            .buttonStyle(.plain)
                    }
                } else {
                    ActionButton(title: "\(buys.items.count)개 추가하기", fullWidth: true, action: save)
                }
            }
        }
        .card()
    }

    private func store(_ updated: ChatPayload.Buys) {
        message.payload = ChatPayload.buys(updated).encoded
        try? context.save()
    }

    private func remove(at index: Int) {
        var updated = buys
        updated.items.remove(at: index)
        store(updated)
    }

    private func save() {
        guard let saved = try? BuyApplier.save(buys.items, in: context), !saved.isEmpty else { return }
        var updated = buys
        updated.created = saved.map(\.id)
        store(updated)
    }

    private func undo() {
        guard (try? BuyApplier.undo(buys.created, in: context)) != nil else { return }
        var updated = buys
        updated.undone = true
        store(updated)
    }
}

struct VoiceComposer: View {
    @ObservedObject var speech: SpeechService
    var onDiscard: () -> Void
    var onSend: () -> Void
    var onRetry: () -> Void

    private var failed: Bool { speech.failure == .noSpeech && !speech.isListening }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let seconds = speech.startedAt.map { Int(timeline.date.timeIntervalSince($0)) } ?? 0
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))").font(.pBodyMedium).foregroundStyle(Tone.ink)
                }
                if failed {
                    Text("잘 못 들었어요").font(.pCaption).foregroundStyle(Tone.ink2)
                } else {
                    Waveform(level: speech.level)
                }
                Spacer(minLength: 0)
            }
            Text(failed ? "다시 말해 주세요" : speech.transcript)
                .font(.pBody)
                .foregroundStyle(Tone.ink)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .lineLimit(4)
            HStack {
                IconButton(symbol: "trash", label: "버리기", action: onDiscard)
                Spacer()
                if failed {
                    RoundButton(symbol: "mic", size: 44, label: "다시 말하기", action: onRetry)
                } else {
                    RoundButton(symbol: "arrow.up", size: 44, label: "보내기", action: onSend)
                }
            }
        }
        .padding(16)
        .background(Tone.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Tone.ink, lineWidth: 1))
    }
}

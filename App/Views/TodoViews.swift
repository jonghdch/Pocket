import SwiftData
import SwiftUI

struct TodoListView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]
    @State private var searching = false
    @State private var query = ""
    @State private var showDone = false

    private var open: [TodoItem] { todos.filter { !$0.isDone && TodoSeries.showsInList($0) } }
    private var done: [TodoItem] {
        todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private var results: [TodoItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return todos.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.note.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if searching { searchHeader } else { header }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if searching { searchContent } else { listContent }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, tabBarClearance + 76)
                }
            }
            if !searching {
                RoundButton(symbol: "mic", label: "말하기") { router.startChatVoice() }
                    .padding(.trailing, 16)
                    .padding(.bottom, tabBarClearance)
            }
        }
    }

    private var header: some View {
        TabHeader(title: "Todo") {
            IconButton(symbol: "slider.horizontal.3", label: "설정") { router.showSettings = true }
            IconButton(symbol: "magnifyingglass", label: "검색") { searching = true }
            IconButton(symbol: "plus", label: "할 일 추가") { router.edit = .new(on: nil, focusTitle: true) }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            SearchField(text: $query)
            IconButton(symbol: "xmark", label: "검색 닫기") {
                searching = false
                query = ""
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    @ViewBuilder private var listContent: some View {
        if open.isEmpty && done.isEmpty {
            EmptyState(symbol: "checkmark.square", title: "아직 할 일이 없어요", caption: "말하거나 + 를 눌러 추가해 보세요")
        }
        ForEach(open) { TodoCard(todo: $0) }
        if !done.isEmpty {
            Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                HStack(spacing: 4) {
                    Text("완료 \(done.count)").font(.pBodyMedium)
                    Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Tone.ink2)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDone { ForEach(done) { TodoCard(todo: $0) } }
        }
    }

    @ViewBuilder private var searchContent: some View {
        if results.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "검색 결과가 없어요", caption: "다른 말로 찾아보세요")
        }
        ForEach(results) { TodoCard(todo: $0) }
    }
}

struct TodoCard: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    let todo: TodoItem
    @State private var expanded = true

    private var meta: String {
        var schedule: String?
        if let start = todo.scheduledAt {
            schedule = todo.hasTime ? "\(Format.day(start)) \(Format.clock(start))" : Format.day(start)
        }
        if todo.isDone, let finished = todo.completedAt {
            schedule = "\(Format.day(finished)) 완료"
        }
        return TodoMeta.text(
            estimate: todo.estimateMinutes, schedule: schedule,
            doneCount: todo.subtasks.filter(\.isDone).count, total: todo.subtasks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(isOn: todo.isDone) { toggle() }
                Button { router.edit = .existing(todo.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todo.title)
                            .font(.pTitle)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? Tone.ink3 : Tone.ink)
                            .multilineTextAlignment(.leading)
                        if !meta.isEmpty {
                            HStack(spacing: 4) {
                                if !todo.isDone { Image(systemName: todo.seriesID == nil ? "clock" : "repeat").font(.system(size: 11)) }
                                Text(meta).font(.pCaption)
                            }
                            .foregroundStyle(todo.isDone ? Tone.ink3 : Tone.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !todo.subtasks.isEmpty && !todo.isDone {
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Tone.ink2)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(expanded ? "하위 작업 접기" : "하위 작업 펼치기")
                }
            }
            if expanded && !todo.subtasks.isEmpty && !todo.isDone {
                Rectangle().fill(Tone.line).frame(height: 1)
                ForEach(todo.orderedSubtasks) { sub in
                    HStack(spacing: 12) {
                        CheckCircle(isOn: sub.isDone) {
                            sub.isDone.toggle()
                            try? context.save()
                        }
                        Text(sub.title).font(.pBody)
                            .strikethrough(sub.isDone)
                            .foregroundStyle(sub.isDone ? Tone.ink3 : Tone.ink)
                    }
                    .padding(.leading, 36)
                }
            }
        }
        .card()
    }

    private func toggle() {
        withAnimation(.snappy) { todo.setDone(!todo.isDone) }
        Task { await TodoSync.afterChange(todo, in: context) }
    }
}

// MARK: - 수정

struct TodoDraft {
    struct Step: Identifiable, Equatable {
        var id = UUID()
        var title: String
        var isDone = false
    }

    var title = ""
    var note = ""
    var isDone = false
    var day: Date?
    var start: Date?
    var end: Date?
    var alert: Int?
    var estimate: Int?
    var steps: [Step] = []

    init(on day: Date? = nil) { self.day = day }

    init(_ todo: TodoItem) {
        title = todo.title
        note = todo.note
        isDone = todo.isDone
        day = todo.scheduledAt
        start = todo.hasTime ? todo.scheduledAt : nil
        end = todo.endAt
        alert = todo.alertMinutesBefore
        estimate = todo.estimateMinutes
        steps = todo.orderedSubtasks.map { Step(id: $0.id, title: $0.title, isDone: $0.isDone) }
    }

    /// 날짜와 시간을 한 값으로 합친다.
    var scheduledAt: Date? {
        guard let day else { return nil }
        guard let start else { return Calendar.current.startOfDay(for: day) }
        return Self.combine(day: day, time: start)
    }

    var endAt: Date? {
        guard let day, start != nil, let end else { return nil }
        return Self.combine(day: day, time: end)
    }

    static func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    func apply(to todo: TodoItem, in context: ModelContext) {
        todo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.note = note
        todo.scheduledAt = scheduledAt
        todo.hasTime = day != nil && start != nil
        todo.endAt = endAt
        todo.alertMinutesBefore = alert
        todo.estimateMinutes = estimate
        if todo.isDone != isDone { todo.setDone(isDone) }

        let keep = Set(steps.map(\.id))
        for sub in todo.subtasks where !keep.contains(sub.id) {
            context.delete(sub)
        }
        todo.subtasks.removeAll { !keep.contains($0.id) }
        for (index, step) in steps.enumerated() {
            if let sub = todo.subtasks.first(where: { $0.id == step.id }) {
                sub.title = step.title
                sub.isDone = step.isDone
                sub.order = index
            } else {
                let sub = Subtask(id: step.id, title: step.title, order: index)
                sub.isDone = step.isDone
                todo.subtasks.append(sub)
            }
        }
    }
}

enum TodoPicker: String, Identifiable {
    case date, time, end, alert, estimate
    var id: String { rawValue }
}

struct TodoEditView: View {
    let route: EditRoute

    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TodoDraft()
    @State private var todo: TodoItem?
    @State private var loaded = false
    @State private var picker: TodoPicker?
    @State private var dialog: ConfirmDialog?
    @State private var addingStep = false
    @State private var newStep = ""
    @State private var renaming: TodoDraft.Step?
    @State private var renameText = ""
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { todo == nil }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SheetHeader(title: isNew ? "새 할 일" : "할 일 수정", onClose: { dismiss() }, onConfirm: save)
                titleCard
                scheduleCard
                subtaskCard
                noteCard
                footer
            }
            .padding(16)
        }
        .background(Tone.bg)
        .presentationCornerRadius(20)
        .onAppear(perform: load)
        .sheet(item: $picker) { kind in
            PickerSheet(kind: kind, draft: $draft)
        }
        .confirmDialog($dialog, onSecondary: { _ in deleteFollowing() }) { _ in delete() }
        .alert("하위 작업 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("확인") {
                if let renaming, let index = draft.steps.firstIndex(of: renaming), !renameText.isEmpty {
                    draft.steps[index].title = renameText
                }
            }
        }
    }

    private var titleCard: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: draft.isDone) { draft.isDone.toggle() }
            TextField("할 일을 입력하세요", text: $draft.title, axis: .vertical)
                .font(.pTitle)
                .focused($titleFocused)
        }
        .card()
    }

    private var scheduleCard: some View {
        VStack(spacing: 12) {
            FieldRow(label: "날짜", value: draft.day.map(Format.day) ?? "없음") { picker = .date }
            FieldRow(label: "시간", value: timeText) { picker = .time }
            FieldRow(label: "알림", value: AlertOption.text(draft.alert)) { picker = .alert }
            HStack {
                Text("예상 시간").font(.pBody).foregroundStyle(Tone.ink)
                Spacer()
                Button { picker = .estimate } label: {
                    Chip(text: draft.estimate.map(Format.duration(minutes:)) ?? "없음", symbol: "clock")
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var timeText: String {
        guard let start = draft.start else { return "없음" }
        return Format.range(start, draft.end)
    }

    private var subtaskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("하위 작업").font(.pBody).foregroundStyle(Tone.ink)
                Button {
                    if saveDraftIfPossible(), let id = todo?.id {
                        dismiss()
                        router.askBreakdown(id)
                    }
                } label: {
                    Chip(text: "AI로 나누기", symbol: "sparkle", soft: true)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                Spacer()
                Text("\(draft.steps.filter(\.isDone).count) / \(draft.steps.count)")
                    .font(.pCaption).foregroundStyle(Tone.ink3)
            }
            if addingStep {
                HStack(spacing: 12) {
                    Image(systemName: "plus").foregroundStyle(Tone.ink3)
                    TextField("하위 작업 추가", text: $newStep)
                        .font(.pBody)
                        .submitLabel(.done)
                        .onSubmit(addStep)
                }
            } else {
                Button { addingStep = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").foregroundStyle(Tone.ink2).frame(width: 24)
                        Text("하위 작업 추가").font(.pBody).foregroundStyle(Tone.ink2)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach($draft.steps) { $step in
                HStack(spacing: 12) {
                    CheckCircle(isOn: step.isDone) { step.isDone.toggle() }
                    Text(step.title).font(.pBody)
                        .strikethrough(step.isDone)
                        .foregroundStyle(step.isDone ? Tone.ink3 : Tone.ink)
                    Spacer()
                    Menu {
                        Button("이름 고치기", systemImage: "pencil") {
                            renameText = step.title
                            renaming = step
                        }
                        Button("삭제", systemImage: "trash", role: .destructive) {
                            let target = step.id
                            draft.steps.removeAll { $0.id == target }
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Tone.ink2).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("더보기")
                }
            }
        }
        .card()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("메모").font(.pCaption).foregroundStyle(Tone.ink2)
            TextField("여기에 메모를 남겨 보세요", text: $draft.note, axis: .vertical).font(.pBody)
        }
        .card()
    }

    private var footer: some View {
        HStack {
            if !isNew {
                IconButton(symbol: "trash", label: "삭제") { dialog = deleteDialog }
            }
            Spacer()
            if !isNew {
                ActionButton(title: "작업 시작") {
                    if saveDraftIfPossible(), let id = todo?.id { router.startFocus(id) }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch route {
        case .existing(let id):
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
            if let found = try? context.fetch(descriptor).first {
                todo = found
                draft = TodoDraft(found)
            }
        case .new(let on, let focus):
            draft = TodoDraft(on: on)
            titleFocused = focus
        }
    }

    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { draft.steps.append(.init(title: title)) }
        newStep = ""
        addingStep = false
    }

    /// 저장하고 성공 여부를 돌려준다. 제목이 없으면 저장하지 않는다.
    private func saveDraftIfPossible() -> Bool {
        addStep()
        guard canSave else {
            titleFocused = true
            return false
        }
        let target = todo ?? {
            let created = TodoItem(title: draft.title)
            context.insert(created)
            todo = created
            return created
        }()
        draft.apply(to: target, in: context)
        try? context.save()
        Task {
            let ok = await TodoSync.afterChange(target, in: context)
            if !ok && CalendarService.isDenied { router.permission = .calendar }
            if target.alertMinutesBefore != nil, await NotificationService.isDenied() { router.permission = .notifications }
        }
        return true
    }

    private func save() {
        if saveDraftIfPossible() { dismiss() }
    }

    private func delete() {
        if let todo { TodoSync.delete(todo, in: context) }
        dismiss()
    }

    /// 묶음에서 이 날 뒤로 남은 항목 (이 날 포함).
    private var following: [TodoItem] {
        guard let todo, todo.seriesID != nil else { return [] }
        let all = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        return TodoSeries.following(todo, in: all)
    }

    private var deleteDialog: ConfirmDialog {
        let count = following.count
        guard count > 1 else {
            return ConfirmDialog(title: "할 일을 삭제할까요?", message: "하위 작업과 메모도 함께 삭제돼요.", confirm: "삭제")
        }
        return ConfirmDialog(
            title: "반복 할 일을 삭제할까요?",
            message: "이 날만 지우거나, 이 날부터 \(count)개를 모두 지울 수 있어요. 지난 날짜는 그대로 남아요.",
            confirm: "이 날만 삭제", secondary: "이후 \(count)개 모두 삭제")
    }

    private func deleteFollowing() {
        for item in following { TodoSync.delete(item, in: context) }
        dismiss()
    }
}

struct FieldRow: View {
    let label: String
    let value: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label).font(.pBody).foregroundStyle(Tone.ink)
                Spacer()
                Text(value).font(.pBody).foregroundStyle(Tone.ink2)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum AlertOption {
    static let all: [(String, Int?)] = [("없음", nil), ("정시", 0), ("10분 전", 10), ("30분 전", 30), ("1시간 전", 60), ("하루 전", 1440)]
    static func text(_ value: Int?) -> String { all.first { $0.1 == value }?.0 ?? "없음" }
}

// MARK: - 선택 시트

struct PickerSheet: View {
    let kind: TodoPicker
    @Binding var draft: TodoDraft
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var time = Date()
    @State private var alert: Int?
    @State private var estimate: Int?
    @State private var customMinutes = ""
    @State private var pickedEnd: Date?

    var body: some View {
        VStack(spacing: 12) {
            SheetHeader(title: title, onClose: { dismiss() }, onConfirm: confirm)
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Tone.bg)
        .presentationDetents([kind == .date ? .height(520) : kind == .estimate ? .height(260) : .height(430)])
        .presentationCornerRadius(20)
        .onAppear(perform: load)
    }

    private var title: String {
        switch kind {
        case .date: "날짜"
        case .time: "시간"
        case .end: "끝나는 시간"
        case .alert: "알림"
        case .estimate: "예상 시간"
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .date:
            MonthCalendar(selection: $day).card()
            clearRow("날짜 없음") {
                draft.day = nil
                draft.start = nil
                draft.end = nil
            }
        case .time:
            DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity).frame(height: 150).clipped().card()
            VStack(spacing: 0) {
                DatePickerRow(label: "끝나는 시간", value: $pickedEnd, base: time)
                clearRow("시간 없음", card: false) {
                    draft.start = nil
                    draft.end = nil
                }
            }
            .card(padding: 12)
        case .end:
            EmptyView()
        case .alert:
            VStack(spacing: 0) {
                ForEach(AlertOption.all, id: \.0) { option in
                    Button { alert = option.1 } label: {
                        HStack {
                            Text(option.0).font(.pBody).foregroundStyle(Tone.ink)
                            Spacer()
                            if alert == option.1 { Image(systemName: "checkmark").foregroundStyle(Tone.ink) }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 12)
        case .estimate:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([15, 30, 60], id: \.self) { minutes in chip(minutes) }
                }
                HStack(spacing: 8) {
                    ForEach([120, 180], id: \.self) { minutes in chip(minutes) }
                    TextField("직접 입력(분)", text: $customMinutes)
                        .keyboardType(.numberPad)
                        .font(.pCaption)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Tone.bg, in: Capsule())
                        .onChange(of: customMinutes) { _, new in if let value = Int(new) { estimate = value } }
                }
                Button("없음으로") { estimate = nil; customMinutes = "" }
                    .font(.pCaption).foregroundStyle(Tone.ink2).padding(.top, 4)
            }
            .card()
        }
    }

    private func chip(_ minutes: Int) -> some View {
        Button {
            estimate = minutes
            customMinutes = ""
        } label: {
            Chip(text: Format.duration(minutes: minutes), soft: estimate == minutes)
        }
        .buttonStyle(.plain)
    }

    private func clearRow(_ label: String, card: Bool = true, clear: @escaping () -> Void) -> some View {
        let row = Button {
            clear()
            dismiss()
        } label: {
            HStack {
                Text(label).font(.pBody).foregroundStyle(Tone.ink)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        return Group {
            if card { row.card(padding: 12) } else { row }
        }
    }

    private func load() {
        day = draft.day ?? .now
        time = draft.start ?? Self.nextHour()
        alert = draft.alert
        estimate = draft.estimate
        pickedEnd = draft.end
    }

    static func nextHour(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        return calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: now) ?? now
    }

    private func confirm() {
        switch kind {
        case .date: draft.day = day
        case .time, .end:
            if draft.day == nil { draft.day = Calendar.current.startOfDay(for: .now) }
            draft.start = time
            draft.end = pickedEnd
        case .alert: draft.alert = alert
        case .estimate: draft.estimate = estimate
        }
        dismiss()
    }
}

struct DatePickerRow: View {
    let label: String
    @Binding var value: Date?
    let base: Date

    var body: some View {
        HStack {
            Text(label).font(.pBody).foregroundStyle(Tone.ink)
            Spacer()
            if let current = value {
                DatePicker("", selection: Binding(get: { current }, set: { value = $0 }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Button { value = nil } label: { Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Tone.ink3) }
                    .accessibilityLabel("끝나는 시간 지우기")
            } else {
                Button("없음") { value = base.addingTimeInterval(3600) }
                    .font(.pBody).foregroundStyle(Tone.ink2)
            }
        }
        .frame(minHeight: 44)
    }
}

struct MonthCalendar: View {
    @Binding var selection: Date
    @State private var month = Date()
    private let calendar = Calendar.current
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private var cells: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let lead = calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: lead) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                arrow("chevron.left", label: "이전 달", by: -1)
                Spacer()
                Text(Format.month(month)).font(.pTitle).foregroundStyle(Tone.ink)
                Spacer()
                arrow("chevron.right", label: "다음 달", by: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(weekdays, id: \.self) { Text($0).font(.pCaption).foregroundStyle(Tone.ink3) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let selected = calendar.isDate(date, inSameDayAs: selection)
                        Button { selection = date } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(selected ? .pBodyMedium : .pBody)
                                .foregroundStyle(selected ? Tone.onAccent : Tone.ink)
                                .frame(width: 36, height: 36)
                                .background(selected ? Tone.ink : .clear, in: Circle())
                                .frame(height: 40)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .onAppear { month = selection }
    }

    private func arrow(_ symbol: String, label: String, by value: Int) -> some View {
        Button {
            month = calendar.date(byAdding: .month, value: value, to: month) ?? month
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Tone.ink2).frame(width: 44, height: 32)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - 계획

struct PlanView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private let calendar = Calendar.current

    private var week: [Date] {
        let weekday = calendar.component(.weekday, from: selected)
        let offset = -((weekday + 5) % 7) // 월요일부터
        let monday = calendar.date(byAdding: .day, value: offset, to: selected) ?? selected
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var items: [TodoItem] {
        todos
            .filter { todo in todo.scheduledAt.map { calendar.isDate($0, inSameDayAs: selected) } ?? false }
            .sorted { a, b in
                switch (a.hasTime, b.hasTime) {
                case (true, false): true
                case (false, true): false
                default: (a.scheduledAt ?? .distantPast) < (b.scheduledAt ?? .distantPast)
                }
            }
    }

    /// 목록 보기와 시간표 보기. 마지막에 고른 쪽을 기억한다.
    @AppStorage("planTimeline") private var timeline = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TabHeader(title: Format.month(selected)) {
                    IconButton(symbol: timeline ? "list.bullet" : "calendar", label: timeline ? "목록 보기" : "시간표 보기") {
                        withAnimation(.snappy) { timeline.toggle() }
                    }
                    Menu {
                        Button { router.showSettings = true } label: { Label("설정", systemImage: "slider.horizontal.3") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Tone.ink)
                            .frame(width: 44, height: 44)
                            .background(Tone.surface, in: Circle())
                            .floatShadow()
                    }
                    .accessibilityLabel("더보기")
                    IconButton(symbol: "plus", label: "일정 추가") { router.edit = .new(on: selected, focusTitle: true) }
                }
                weekStrip.padding(.bottom, 8)
                if timeline {
                    PlanTimeline(day: selected, items: items)
                } else {
                    listView
                }
            }
            RoundButton(symbol: "mic", label: "말하기") { router.startChatVoice() }
                .padding(.trailing, 16)
                .padding(.bottom, tabBarClearance)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            let days = value.translation.width < 0 ? 7 : -7
            selected = calendar.date(byAdding: .day, value: days, to: selected) ?? selected
        })
    }

    private var listView: some View {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if items.isEmpty {
                            EmptyState(symbol: "calendar", title: "이 날은 활용할 시간이 많아요", caption: "말하거나 + 를 눌러 할 일을 넣어 보세요")
                        }
                        ForEach(items) { PlanRow(todo: $0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, tabBarClearance + 76)
                }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(week, id: \.self) { day in
                let active = calendar.isDate(day, inSameDayAs: selected)
                Button { selected = calendar.startOfDay(for: day) } label: {
                    VStack(spacing: 2) {
                        Text(Format.weekday(day)).font(.pCaption)
                        Text("\(calendar.component(.day, from: day))").font(.pTitle)
                    }
                    .foregroundStyle(active ? Tone.onAccent : Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 59)
                    .background(active ? Tone.ink : Tone.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// 시간표 보기. 한 시간 64pt, 시간 있는 일정만 블록으로 그리고 시간 없는 할 일은 위에 모은다.
struct PlanTimeline: View {
    @EnvironmentObject private var router: Router
    let day: Date
    let items: [TodoItem]

    static let hourHeight: CGFloat = 64
    private let labelWidth: CGFloat = 64
    private let calendar = Calendar.current

    private var timed: [TodoItem] { items.filter(\.isEvent) }
    private var untimed: [TodoItem] { items.filter { !$0.isEvent } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if !untimed.isEmpty {
                        VStack(spacing: 8) { ForEach(untimed) { PlanRow(todo: $0) } }
                            .padding(.horizontal, 16)
                    }
                    grid
                }
                .padding(.top, 4)
                .padding(.bottom, tabBarClearance + 76)
            }
            .onAppear {
                let hour = calendar.isDateInToday(day) ? max(0, calendar.component(.hour, from: .now) - 1) : 8
                proxy.scrollTo("hour-\(hour)", anchor: .top)
            }
        }
    }

    private var grid: some View {
        let blocks = TimelineLayout.blocks(
            timed.compactMap { todo in todo.scheduledAt.map { TimelineLayout.Item(id: todo.id, start: $0, end: todo.endAt) } },
            hourHeight: Self.hourHeight)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(hourLabel(hour)).font(.system(size: 12)).foregroundStyle(Tone.ink3)
                            .frame(width: labelWidth - 8, alignment: .leading)
                            .offset(y: -8)
                        Rectangle().fill(Tone.line).frame(height: 1)
                    }
                    .frame(height: Self.hourHeight, alignment: .top)
                    .id("hour-\(hour)")
                }
            }
            GeometryReader { geo in
                let width = geo.size.width - labelWidth - 4
                ForEach(blocks, id: \.id) { block in
                    if let todo = timed.first(where: { $0.id == block.id }) {
                        let columnWidth = width / CGFloat(block.columns)
                        Button { router.edit = .existing(todo.id) } label: { event(todo, height: block.height) }
                            .buttonStyle(.plain)
                            .frame(width: columnWidth - 4, height: block.height - 2)
                            .offset(x: labelWidth + CGFloat(block.column) * columnWidth, y: block.top + 1)
                    }
                }
                if calendar.isDateInToday(day) {
                    let y = TimelineLayout.offset(of: .now, hourHeight: Self.hourHeight)
                    HStack(spacing: 0) {
                        Circle().fill(Tone.ink).frame(width: 8, height: 8)
                        Rectangle().fill(Tone.ink).frame(height: 2)
                    }
                    .frame(width: width + 8)
                    .offset(x: labelWidth - 4, y: y - 4)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: Self.hourHeight * 24)
        .padding(.leading, 16)
        .padding(.trailing, 16)
    }

    private func event(_ todo: TodoItem, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(todo.title).font(.pBodyMedium).foregroundStyle(todo.isDone ? Tone.ink3 : Tone.ink)
                .strikethrough(todo.isDone).lineLimit(1)
            if height >= 44, let start = todo.scheduledAt {
                Text(Format.range(start, todo.endAt)).font(.pCaption).foregroundStyle(Tone.ink2).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, height >= 44 ? 8 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tone.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return Format.clock(date)
    }
}

struct PlanRow: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    let todo: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(todo.isEvent ? Format.clock24(todo.scheduledAt ?? .now) : "")
                .font(.pCaption).foregroundStyle(Tone.ink2)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 16)
            HStack(spacing: 12) {
                if !todo.isEvent {
                    CheckCircle(isOn: todo.isDone) {
                        todo.setDone(!todo.isDone)
                        Task { await TodoSync.afterChange(todo, in: context) }
                    }
                }
                Button { router.edit = .existing(todo.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todo.title).font(.pTitle)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? Tone.ink3 : Tone.ink)
                            .multilineTextAlignment(.leading)
                        if todo.isEvent, let start = todo.scheduledAt {
                            Text(Format.range(start, todo.endAt)).font(.pCaption).foregroundStyle(Tone.ink2)
                        }
                        if todo.calendarEventID != nil {
                            Chip(text: "iOS 캘린더", symbol: "calendar", soft: true).padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }
}

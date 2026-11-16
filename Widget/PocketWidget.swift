import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct WidgetTodo: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
    let time: Date?
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodo]
    /// App Group 을 못 쓰면 앱 데이터를 읽을 수 없다. 그때는 안내를 보여 준다.
    var isShared = true

    var open: Int { todos.filter { !$0.isDone }.count }
    var doneRatio: Double {
        todos.isEmpty ? 0 : Double(todos.count - open) / Double(todos.count)
    }
    var nextEvent: WidgetTodo? {
        todos.filter { !$0.isDone && ($0.time ?? .distantPast) > date }.min { ($0.time ?? .now) < ($1.time ?? .now) }
    }
}

struct TodayProvider: TimelineProvider {
    private let sample = TodayEntry(date: .now, todos: [
        WidgetTodo(id: UUID(), title: "보험 서류 제출하기", isDone: false, time: nil),
        WidgetTodo(id: UUID(), title: "디자인 리뷰", isDone: false, time: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now)),
    ])

    func placeholder(in context: Context) -> TodayEntry { sample }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? sample : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = load()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let next = min(calendar.date(byAdding: .minute, value: 30, to: .now) ?? midnight, midnight)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> TodayEntry {
        guard PocketStore.isShared, let container = try? PocketStore.makeContainer() else {
            return TodayEntry(date: .now, todos: [], isShared: false)
        }
        let all = (try? ModelContext(container).fetch(FetchDescriptor<TodoItem>())) ?? []
        return TodayEntry(date: .now, todos: Self.today(from: all, now: .now))
    }

    /// 오늘 일정과 날짜 없는 할 일, 오늘 끝낸 일. 시간 있는 항목을 뒤로 보낸다.
    static func today(from all: [TodoItem], now: Date) -> [WidgetTodo] {
        let calendar = Calendar.current
        return all
            .filter { todo in
                if todo.isDone { return todo.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
                guard let start = todo.scheduledAt else { return true }
                return calendar.isDate(start, inSameDayAs: now) || start < now
            }
            .sorted { a, b in
                if a.isDone != b.isDone { return a.isDone }
                switch (a.isEvent, b.isEvent) {
                case (false, true): return true
                case (true, false): return false
                default: return (a.scheduledAt ?? a.createdAt) < (b.scheduledAt ?? b.createdAt)
                }
            }
            .map { WidgetTodo(id: $0.id, title: $0.title, isDone: $0.isDone, time: $0.isEvent ? $0.scheduledAt : nil) }
    }
}

private struct TodoLine: View {
    let todo: WidgetTodo

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTodoIntent(todoID: todo.id)) { CircleMark(isOn: todo.isDone) }
                .buttonStyle(.plain)
            Link(destination: DeepLink.todo(todo.id).url) {
                HStack {
                    Text(todo.title)
                        .font(.pBody)
                        .foregroundStyle(todo.isDone ? Tone.ink3 : Tone.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let time = todo.time {
                        Text(Format.clock24(time)).font(.pCaption).foregroundStyle(Tone.ink2)
                    }
                }
            }
        }
    }
}

private struct CircleMark: View {
    let isOn: Bool
    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Tone.ink)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.onAccent)
            } else {
                Circle().strokeBorder(Tone.line, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct TodayTitle: View {
    let entry: TodayEntry
    var body: some View {
        HStack(spacing: 4) {
            Text("오늘").font(.pTitle).foregroundStyle(Tone.ink)
            Text("\(entry.open)").font(.pTitle).foregroundStyle(Tone.ink2)
        }
    }
}

private struct RoundLink: View {
    let link: DeepLink
    let symbol: String
    var size: CGFloat = 52
    var primary = true

    var body: some View {
        Link(destination: link.url) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(primary ? Tone.onAccent : Tone.ink)
                .frame(width: size, height: size)
                .background(primary ? Tone.ink : Tone.bg, in: Circle())
        }
    }
}

private struct WideLink: View {
    let link: DeepLink
    let symbol: String
    let title: String
    var primary = false

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.pBodyMedium)
            }
            .foregroundStyle(primary ? Tone.onAccent : Tone.ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(primary ? Tone.ink : Tone.bg, in: Capsule())
        }
    }
}

private struct NoShareNotice: View {
    var body: some View {
        Text("앱을 열어 확인해 주세요").font(.pCaption).foregroundStyle(Tone.ink2)
    }
}

struct MediumView: View {
    let entry: TodayEntry
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                TodayTitle(entry: entry)
                if !entry.isShared { NoShareNotice() }
                ForEach(entry.todos.prefix(3)) { TodoLine(todo: $0) }
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                RoundLink(link: .voice, symbol: "mic")
                RoundLink(link: .memo, symbol: "doc.text", primary: false)
            }
        }
    }
}

struct LargeView: View {
    let entry: TodayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayTitle(entry: entry)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tone.line)
                    Capsule().fill(Tone.ink).frame(width: geo.size.width * entry.doneRatio)
                }
            }
            .frame(height: 4)
            if !entry.isShared { NoShareNotice() }
            ForEach(entry.todos.prefix(6)) { TodoLine(todo: $0) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                WideLink(link: .voice, symbol: "mic", title: "말하기", primary: true)
                WideLink(link: .memo, symbol: "doc.text", title: "메모")
                WideLink(link: .newTodo, symbol: "plus", title: "할 일")
            }
        }
    }
}

struct SmallView: View {
    let entry: TodayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.nextEvent == nil ? "오늘" : "다음 일정").font(.pCaption).foregroundStyle(Tone.ink2)
            if let next = entry.nextEvent {
                Text(next.title).font(.pTitle).foregroundStyle(Tone.ink).lineLimit(2)
                if let time = next.time { Text(Format.clock(time)).font(.pCaption).foregroundStyle(Tone.ink2) }
            } else {
                Text(entry.isShared ? "남은 일 \(entry.open)개" : "앱을 열어 주세요").font(.pTitle).foregroundStyle(Tone.ink)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                RoundLink(link: .voice, symbol: "mic", size: 44)
                RoundLink(link: .newTodo, symbol: "plus", size: 44, primary: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            default: MediumView(entry: entry)
            }
        }
        .containerBackground(Tone.surface, for: .widget)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketToday", provider: TodayProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("오늘")
            .description("오늘 할 일과 일정을 보고 바로 처리해요.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct VoiceProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, todos: []) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

struct VoiceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketVoice", provider: VoiceProvider()) { _ in
            VStack(spacing: 8) {
                Image(systemName: "mic").font(.system(size: 36, weight: .medium))
                Text("눌러서 말하기").font(.pBodyMedium)
            }
            .foregroundStyle(Tone.onAccent)
            .containerBackground(Tone.ink, for: .widget)
            .widgetURL(DeepLink.voice.url)
        }
        .configurationDisplayName("말하기")
        .description("누르면 앱이 열리면서 바로 듣기 시작해요.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct PocketWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        VoiceWidget()
    }
}

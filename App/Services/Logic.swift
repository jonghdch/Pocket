import CoreGraphics
import Foundation

/// "메모에 넣어줘"를 말의 시작 부분에서만 찾는다. 대화 중 나온 "메모"로 잘못 넘어가지 않게 하기 위해서다.
enum MemoTrigger {
    static let phrases = ["메모에넣어줘", "메모에넣어주세요", "메모로넣어줘", "메모로남겨줘", "메모에적어줘"]
    /// 문구 앞에 올 수 있는 글자 수 (공백 제외). "음 그럼" 정도까지 허용한다.
    static let maxLeadingCharacters = 6

    /// 문구를 찾으면 문구 뒤에 이어진 말을 돌려준다. 없으면 nil.
    static func remainder(in transcript: String) -> String? {
        var compact = ""
        var map: [String.Index] = []
        for index in transcript.indices where !transcript[index].isWhitespace && !transcript[index].isPunctuation {
            compact.append(transcript[index])
            map.append(index)
        }
        for phrase in phrases {
            guard let range = compact.range(of: phrase) else { continue }
            let lead = compact.distance(from: compact.startIndex, to: range.lowerBound)
            guard lead <= maxLeadingCharacters else { continue }
            let last = compact.distance(from: compact.startIndex, to: range.upperBound) - 1
            let after = transcript[transcript.index(after: map[last])...]
            return after
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return nil
    }
}

/// 타이머와 스톱워치. 벽시계 기준이라 앱이 잠시 멈춰도 시간이 맞다.
struct FocusClock: Equatable {
    enum Mode: Equatable { case timer(total: Int), stopwatch }
    enum Phase: Equatable { case idle, running, paused, ended }

    var mode: Mode
    private(set) var phase: Phase = .idle
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?

    init(mode: Mode) { self.mode = mode }

    func elapsed(at now: Date) -> Int {
        var total = accumulated
        if let startedAt { total += now.timeIntervalSince(startedAt) }
        if case .timer(let limit) = mode { return min(Int(total), limit) }
        return Int(total)
    }

    /// 타이머는 남은 시간, 스톱워치는 지난 시간.
    func displaySeconds(at now: Date) -> Int {
        if case .timer(let limit) = mode { return max(0, limit - elapsed(at: now)) }
        return elapsed(at: now)
    }

    func progress(at now: Date) -> Double {
        guard case .timer(let limit) = mode, limit > 0, phase != .idle else { return 0 }
        return Double(limit - elapsed(at: now)) / Double(limit)
    }

    func endDate(at now: Date) -> Date? {
        guard case .timer(let limit) = mode else { return nil }
        return now.addingTimeInterval(TimeInterval(limit - elapsed(at: now)))
    }

    mutating func start(at now: Date) {
        guard phase == .idle || phase == .paused else { return }
        startedAt = now
        phase = .running
    }

    mutating func pause(at now: Date) {
        guard phase == .running, let startedAt else { return }
        accumulated += now.timeIntervalSince(startedAt)
        self.startedAt = nil
        phase = .paused
    }

    mutating func reset() {
        accumulated = 0
        startedAt = nil
        phase = .idle
    }

    mutating func tick(at now: Date) {
        guard phase == .running, case .timer(let limit) = mode, elapsed(at: now) >= limit else { return }
        accumulated = TimeInterval(limit)
        startedAt = nil
        phase = .ended
    }

    /// 끝난 타이머에 시간을 더해 바로 다시 돌린다.
    mutating func extend(seconds: Int, at now: Date) {
        guard case .timer(let limit) = mode else { return }
        mode = .timer(total: limit + seconds)
        startedAt = now
        phase = .running
    }
}

/// AI 가 돌려주는 정리 결과.
struct AIPlan: Codable, Equatable {
    struct NewTodo: Codable, Equatable {
        var title: String
        var date: String?
        var start_time: String?
        var end_time: String?
        var estimate_minutes: Int?
    }

    struct Change: Codable, Equatable {
        var id: String
        var title: String?
        var date: String?
        var start_time: String?
        var end_time: String?
        var done: Bool?
    }

    /// 기간 동안 같은 일을 반복한다. weekdays 는 1=월 … 7=일, 없으면 매일.
    struct Repeat: Codable, Equatable {
        var title: String
        var from: String
        var to: String
        var weekdays: [Int]?
        var start_time: String?
        var end_time: String?
        var estimate_minutes: Int?
    }

    /// 목표를 날짜별로 다른 할 일로 나눈다.
    struct Spread: Codable, Equatable {
        var title: String
        var days: [SeriesDraft.Day]
    }

    /// 살 것. 이름 말고는 말에 있을 때만 채운다.
    struct Buy: Codable, Equatable {
        var name: String
        var quantity: String?
        var due_date: String?
        var store: String?
    }

    var reply: String
    var create: [NewTodo]?
    var update: [Change]?
    var repeats: [Repeat]?
    var spreads: [Spread]?
    var buys: [Buy]?
}

enum BuyPlanner {
    /// 이름이 빈 품목은 버리고, 틀린 기한은 비운다.
    static func clean(_ items: [AIPlan.Buy]) -> [AIPlan.Buy] {
        items.compactMap { item in
            var item = item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.name.isEmpty else { return nil }
            if PlanDate.make(date: item.due_date, time: nil) == nil { item.due_date = nil }
            for key in [\AIPlan.Buy.quantity, \AIPlan.Buy.store] {
                let value = item[keyPath: key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                item[keyPath: key] = value?.isEmpty == false ? value : nil
            }
            return item
        }
    }

    /// 확인 카드 한 줄. "세제 · 1개 · 11월 22일까지 · 다이소"
    static func label(_ item: AIPlan.Buy) -> String {
        let due = PlanDate.make(date: item.due_date, time: nil).map { Format.monthDay($0) + "까지" }
        return ([item.name, item.quantity, due, item.store] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }
}

enum BuyRules {
    static let keepDays = 3

    /// 산 날부터 센 남은 날. 오늘 샀으면 3, 사지 않았으면 nil.
    static func daysLeft(_ item: BuyItem, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard item.isBought, let bought = item.boughtAt else { return nil }
        let passed = calendar.dateComponents([.day], from: calendar.startOfDay(for: bought), to: calendar.startOfDay(for: now)).day ?? 0
        return keepDays - passed
    }

    static func isExpired(_ item: BuyItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        (daysLeft(item, now: now, calendar: calendar) ?? 1) <= 0
    }

    /// 카드 아래 한 줄. 산 품목은 언제 샀고 며칠 뒤 지워지는지 보여 준다.
    static func meta(_ item: BuyItem, now: Date = .now, calendar: Calendar = .current) -> String {
        if let left = daysLeft(item, now: now, calendar: calendar), let bought = item.boughtAt {
            let when: String
            if calendar.isDate(bought, inSameDayAs: now) {
                when = "오늘"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(bought, inSameDayAs: yesterday) {
                when = "어제"
            } else {
                when = Format.monthDay(bought)
            }
            return "\(when) 삼 · \(max(left, 0))일 뒤 지워져요"
        }
        let due = item.dueDate.map { Format.monthDay($0) + "까지" }
        return ([item.quantity, due, item.store] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }

    /// 기한이 가까운 것부터, 기한이 없으면 넣은 순서대로.
    static func sortedOpen(_ items: [BuyItem]) -> [BuyItem] {
        items.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.createdAt < b.createdAt
            }
        }
    }
}

/// 여러 날에 걸친 할 일 묶음. 저장 전에 미리보기 카드로 보여 준다.
struct SeriesDraft: Codable, Equatable {
    struct Day: Codable, Equatable {
        var date: String
        var title: String
        var start_time: String?
        var end_time: String?
        var estimate_minutes: Int?
    }

    var title: String
    var days: [Day]
}

enum SeriesPlanner {
    static let maxDays = 90

    static func drafts(from plan: AIPlan) -> [SeriesDraft] {
        (plan.repeats ?? []).compactMap { expand($0) } + (plan.spreads ?? []).compactMap { clean($0) }
    }

    /// 반복을 날짜별로 펼친다. 기간이 틀리면 nil.
    static func expand(_ rule: AIPlan.Repeat, calendar: Calendar = .current) -> SeriesDraft? {
        let title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              var day = PlanDate.make(date: rule.from, time: nil, calendar: calendar),
              let last = PlanDate.make(date: rule.to, time: nil, calendar: calendar),
              day <= last else { return nil }
        let weekdays = Set(rule.weekdays ?? Array(1...7))
        var days: [SeriesDraft.Day] = []
        while day <= last && days.count < maxDays {
            let iso = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            if weekdays.contains(iso) {
                days.append(.init(
                    date: PlanDate.string(from: day, calendar: calendar), title: title,
                    start_time: rule.start_time, end_time: rule.end_time, estimate_minutes: rule.estimate_minutes))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days.isEmpty ? nil : SeriesDraft(title: title, days: days)
    }

    /// AI 가 짠 배분에서 날짜가 틀리거나 제목이 빈 줄을 버리고 날짜순으로 둔다.
    static func clean(_ spread: AIPlan.Spread) -> SeriesDraft? {
        let days = spread.days
            .map { day -> SeriesDraft.Day in
                var day = day
                day.title = day.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return day
            }
            .filter { !$0.title.isEmpty && PlanDate.make(date: $0.date, time: nil) != nil }
            .enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
            .prefix(maxDays)
        return days.isEmpty ? nil : SeriesDraft(title: spread.title, days: Array(days))
    }
}

enum TodoSeries {
    /// 할 일 목록에는 오늘까지의 묶음 항목만 보여 준다. 앞날의 항목은 계획 탭에서 본다.
    static func showsInList(_ todo: TodoItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard todo.seriesID != nil, let start = todo.scheduledAt,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return true }
        return start < tomorrow
    }

    /// 같은 묶음에서 이 할 일과 같은 날이거나 뒤에 있는 항목. 묶음이 아니면 자기 자신만.
    static func following(_ todo: TodoItem, in all: [TodoItem], calendar: Calendar = .current) -> [TodoItem] {
        guard let series = todo.seriesID, let start = todo.scheduledAt else { return [todo] }
        let from = calendar.startOfDay(for: start)
        return all
            .filter { $0.seriesID == series && ($0.scheduledAt ?? .distantPast) >= from }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }
}

enum PlanDate {
    /// "2026-11-11" 과 "15:00" 을 합친다. 시간이 없으면 그날 0시. 형식이 틀리면 nil.
    static func make(date: String?, time: String?, calendar: Calendar = .current) -> Date? {
        guard let date else { return nil }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        if let time {
            let t = time.split(separator: ":").compactMap { Int($0) }
            guard t.count == 2, (0..<24).contains(t[0]), (0..<60).contains(t[1]) else { return nil }
            comps.hour = t[0]
            comps.minute = t[1]
        }
        guard let result = calendar.date(from: comps),
              calendar.component(.day, from: result) == parts[2] else { return nil }
        return result
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 메모 제목을 AI 없이 만들 때 쓴다. 인터넷이 없거나 키가 없을 때의 대체 수단이다.
enum MemoTitle {
    static func fallback(from body: String, limit: Int = 20) -> String {
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "제목 없는 메모" }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }
}

/// 카드 아래쪽 한 줄. "2시간 · 하위 작업 0/1"
enum TodoMeta {
    static func text(estimate: Int?, schedule: String?, doneCount: Int, total: Int) -> String {
        var parts: [String] = []
        if let schedule { parts.append(schedule) }
        if let estimate { parts.append(Format.duration(minutes: estimate)) }
        if total > 0 { parts.append("하위 작업 \(doneCount)/\(total)") }
        return parts.joined(separator: " · ")
    }
}

/// 음성 인식이 실패했을 때 다시 할지 정한다. 아무 말도 못 받은 실패가 이어지면 멈춘다.
/// 기기 안 인식이 실패하면 서버 인식으로 한 번 바꾼다. 시뮬레이터처럼 기기 안 모델이 깨진 경우에 필요하다.
struct RecognitionRetry {
    enum Action: Equatable { case restart(onDevice: Bool), giveUp }

    private(set) var onDevice: Bool
    private var silentFailures = 0

    init(onDevice: Bool) { self.onDevice = onDevice }

    mutating func afterFailure(heardText: Bool) -> Action {
        if heardText {
            silentFailures = 0
            return .restart(onDevice: onDevice)
        }
        if onDevice {
            onDevice = false
            silentFailures = 0
            return .restart(onDevice: false)
        }
        silentFailures += 1
        return silentFailures >= 2 ? .giveUp : .restart(onDevice: false)
    }
}

/// Plan 시간표 보기에서 일정 블록의 위치. 겹치는 일정은 폭을 나눠 나란히 둔다.
enum TimelineLayout {
    struct Item { let id: UUID; let start: Date; let end: Date? }
    struct Block: Equatable { let id: UUID; let top: CGFloat; let height: CGFloat; let column: Int; let columns: Int }

    static let minHeight: CGFloat = 28

    static func offset(of date: Date, hourHeight: CGFloat, calendar: Calendar = .current) -> CGFloat {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (CGFloat(c.hour ?? 0) + CGFloat(c.minute ?? 0) / 60) * hourHeight
    }

    static func blocks(_ items: [Item], hourHeight: CGFloat, calendar: Calendar = .current) -> [Block] {
        let sorted = items.sorted { $0.start < $1.start }
        let ends = sorted.map { item -> Date in
            guard let end = item.end, end > item.start else { return item.start.addingTimeInterval(3600) }
            return end
        }
        // 겹치는 것끼리 묶고, 묶음 안에서 빈 칸에 차례로 넣는다.
        var result: [Block] = []
        var group: [(index: Int, column: Int)] = []
        var groupEnd = Date.distantPast
        var columnEnds: [Date] = []
        func flush() {
            let count = max(1, columnEnds.count)
            for (index, column) in group {
                let top = offset(of: sorted[index].start, hourHeight: hourHeight, calendar: calendar)
                let height = max(minHeight, CGFloat(ends[index].timeIntervalSince(sorted[index].start)) / 3600 * hourHeight)
                result.append(Block(id: sorted[index].id, top: top, height: height, column: column, columns: count))
            }
            group = []; columnEnds = []
        }
        for (index, item) in sorted.enumerated() {
            if item.start >= groupEnd { flush() }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(ends[index]) } else { columnEnds[column] = ends[index] }
            group.append((index, column))
            groupEnd = max(groupEnd, ends[index])
        }
        flush()
        return result
    }
}

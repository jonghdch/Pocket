import SwiftData
import XCTest
@testable import POCKET

final class MemoTriggerTests: XCTestCase {
    func testDetectsPhraseAtStartAndReturnsWhatFollows() {
        XCTAssertEqual(MemoTrigger.remainder(in: "메모에 넣어줘 내일 장볼 것 정리"), "내일 장볼 것 정리")
    }

    func testIgnoresSpacingAndPunctuation() {
        XCTAssertEqual(MemoTrigger.remainder(in: "메모에넣어 줘. 첫 화면 정리"), "첫 화면 정리")
    }

    func testAllowsShortLeadIn() {
        XCTAssertEqual(MemoTrigger.remainder(in: "음 그럼 메모에 넣어줘 아이디어"), "아이디어")
    }

    func testReturnsEmptyWhenNothingFollows() {
        XCTAssertEqual(MemoTrigger.remainder(in: "메모에 넣어줘"), "")
    }

    func testIgnoresPhraseLateInSpeech() {
        XCTAssertNil(MemoTrigger.remainder(in: "내일 회의 끝나고 팀장님이 말씀하신 내용을 메모에 넣어줘"))
    }

    func testIgnoresTheWordMemoAlone() {
        XCTAssertNil(MemoTrigger.remainder(in: "메모 앱 열어서 확인해야 해"))
    }
}

final class FocusClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testTimerCountsDownAndEnds() {
        var clock = FocusClock(mode: .timer(total: 60))
        clock.start(at: t0)
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(20)), 40)
        clock.tick(at: t0.addingTimeInterval(60))
        XCTAssertEqual(clock.phase, .ended)
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(500)), 0)
    }

    func testPauseStopsTimeAndResumeContinues() {
        var clock = FocusClock(mode: .timer(total: 60))
        clock.start(at: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(1000)), 50)
        clock.start(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(1005)), 45)
    }

    func testStopwatchCountsUp() {
        var clock = FocusClock(mode: .stopwatch)
        clock.start(at: t0)
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(90)), 90)
        clock.tick(at: t0.addingTimeInterval(100_000))
        XCTAssertEqual(clock.phase, .running)
    }

    func testExtendRestartsEndedTimer() {
        var clock = FocusClock(mode: .timer(total: 60))
        clock.start(at: t0)
        clock.tick(at: t0.addingTimeInterval(60))
        clock.extend(seconds: 600, at: t0.addingTimeInterval(70))
        XCTAssertEqual(clock.phase, .running)
        XCTAssertEqual(clock.displaySeconds(at: t0.addingTimeInterval(70)), 600)
    }

    func testEndDateIsStartPlusTotal() {
        var clock = FocusClock(mode: .timer(total: 7200))
        clock.start(at: t0)
        XCTAssertEqual(clock.endDate(at: t0), t0.addingTimeInterval(7200))
    }
}

final class PlanDateTests: XCTestCase {
    private var calendar: Calendar { .current }

    func testCombinesDateAndTime() throws {
        let date = try XCTUnwrap(PlanDate.make(date: "2026-11-11", time: "15:30"))
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 11, 11, 15, 30])
    }

    func testRejectsImpossibleValues() {
        XCTAssertNil(PlanDate.make(date: "2026-02-31", time: nil))
        XCTAssertNil(PlanDate.make(date: "2026-11-11", time: "25:00"))
        XCTAssertNil(PlanDate.make(date: nil, time: "10:00"))
        XCTAssertNil(PlanDate.make(date: "내일", time: nil))
    }
}

final class ClaudeParsingTests: XCTestCase {
    func testExtractsToolInput() throws {
        let json = #"{"content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"apply_plan","input":{"reply":"넣었어요","create":[{"title":"치과","date":"2026-11-06","start_time":"10:00"}]}}]}"#
        let plan = try JSONDecoder().decode(AIPlan.self, from: ClaudeClient.toolInput(from: Data(json.utf8)))
        XCTAssertEqual(plan.reply, "넣었어요")
        XCTAssertEqual(plan.create?.first?.title, "치과")
        XCTAssertNil(plan.update)
    }

    func testMissingToolUseIsBadResponse() {
        let json = #"{"content":[{"type":"text","text":"죄송해요"}]}"#
        XCTAssertThrowsError(try ClaudeClient.toolInput(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? AIError, .badResponse)
        }
    }

    func testNoKeyStopsBeforeNetwork() async {
        let client = ClaudeClient(key: { nil })
        do {
            _ = try await client.plan(text: "내일 치과", todos: "")
            XCTFail("키 없이 요청이 나갔습니다")
        } catch {
            XCTAssertEqual(error as? AIError, .noKey)
        }
    }
}

final class MemoTitleTests: XCTestCase {
    func testUsesFirstLineAndTruncates() {
        XCTAssertEqual(MemoTitle.fallback(from: "짧은 줄\n다음 줄"), "짧은 줄")
        XCTAssertEqual(MemoTitle.fallback(from: String(repeating: "가", count: 30)), String(repeating: "가", count: 20) + "…")
        XCTAssertEqual(MemoTitle.fallback(from: "   "), "제목 없는 메모")
    }
}

final class TodoDraftTests: XCTestCase {
    func testTodoWithDateAndTimeBecomesEvent() {
        let todo = TodoItem(title: "회의")
        XCTAssertFalse(todo.isEvent)
        todo.scheduledAt = .now
        XCTAssertFalse(todo.isEvent)
        todo.hasTime = true
        XCTAssertTrue(todo.isEvent)
    }

    func testDraftWithoutTimeUsesStartOfDay() throws {
        var draft = TodoDraft()
        draft.day = Date()
        let start = try XCTUnwrap(draft.scheduledAt)
        XCTAssertEqual(start, Calendar.current.startOfDay(for: start))
        XCTAssertNil(draft.endAt)
    }

    func testDraftCombinesDayAndTime() throws {
        let calendar = Calendar.current
        var draft = TodoDraft()
        draft.day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))
        draft.start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 9, minute: 30))
        let c = calendar.dateComponents([.year, .day, .hour, .minute], from: try XCTUnwrap(draft.scheduledAt))
        XCTAssertEqual([c.year, c.day, c.hour, c.minute], [2026, 14, 9, 30])
    }
}

@MainActor
final class PlanApplierTests: XCTestCase {
    private func context() throws -> ModelContext {
        ModelContext(try PocketStore.makeContainer(inMemory: true))
    }

    func testCreateThenUndoRemovesItem() throws {
        let context = try context()
        let plan = AIPlan(reply: "넣었어요", create: [.init(title: "치과", date: "2026-11-06", start_time: "10:00")])
        let (result, changed) = try PlanApplier.apply(plan, in: context)
        XCTAssertEqual(changed.first?.isEvent, true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoItem>()), 1)
        _ = try PlanApplier.undo(result, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoItem>()), 0)
    }

    func testTodoWithoutTimeStaysPlainTodo() throws {
        let context = try context()
        let plan = AIPlan(reply: "", create: [.init(title: "장보기")])
        let (_, changed) = try PlanApplier.apply(plan, in: context)
        XCTAssertEqual(changed.first?.isEvent, false)
        XCTAssertNil(changed.first?.scheduledAt)
    }

    func testUpdateThenUndoRestoresOriginal() throws {
        let context = try context()
        let todo = TodoItem(title: "회의")
        context.insert(todo)
        try context.save()
        let plan = AIPlan(reply: "", update: [.init(id: todo.id.uuidString, title: "팀 회의", date: "2026-11-06", start_time: "14:00", done: true)])
        let (result, _) = try PlanApplier.apply(plan, in: context)
        XCTAssertEqual(todo.title, "팀 회의")
        XCTAssertTrue(todo.isDone)
        XCTAssertTrue(todo.isEvent)
        _ = try PlanApplier.undo(result, in: context)
        XCTAssertEqual(todo.title, "회의")
        XCTAssertFalse(todo.isDone)
        XCTAssertFalse(todo.isEvent)
    }

    func testUnknownIDAndBlankTitleAreIgnored() throws {
        let context = try context()
        let plan = AIPlan(reply: "", create: [.init(title: "  ")], update: [.init(id: UUID().uuidString, title: "없음"), .init(id: "not-a-uuid", title: "없음")])
        let (result, changed) = try PlanApplier.apply(plan, in: context)
        XCTAssertTrue(changed.isEmpty)
        XCTAssertTrue(result.created.isEmpty)
    }
}

final class DeepLinkTests: XCTestCase {
    func testRoundTrip() {
        let id = UUID()
        for link in [DeepLink.voice, .memo, .newTodo, .todo(id)] {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com")!))
        XCTAssertNil(DeepLink(url: URL(string: "pocket://unknown")!))
    }
}

final class SeriesPlannerTests: XCTestCase {
    private func dates(_ draft: SeriesDraft?) -> [String] { draft?.days.map(\.date) ?? [] }

    func testRepeatExpandsEveryDayInclusive() {
        let draft = SeriesPlanner.expand(.init(title: "운동 30분", from: "2026-11-16", to: "2026-11-20"))
        XCTAssertEqual(dates(draft), ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20"])
        XCTAssertEqual(draft?.days.first?.title, "운동 30분")
    }

    func testRepeatKeepsOnlyChosenWeekdays() {
        // 2026-11-16 은 월요일. 1=월 … 7=일
        let draft = SeriesPlanner.expand(.init(title: "영어", from: "2026-11-16", to: "2026-11-23", weekdays: [1, 3, 5]))
        XCTAssertEqual(dates(draft), ["2026-11-16", "2026-11-18", "2026-11-20", "2026-11-23"])
    }

    func testRepeatCarriesTime() {
        let draft = SeriesPlanner.expand(.init(title: "러닝", from: "2026-11-16", to: "2026-11-17", start_time: "07:00", end_time: "07:30"))
        XCTAssertEqual(draft?.days.map(\.start_time), ["07:00", "07:00"])
        XCTAssertEqual(draft?.days.first?.end_time, "07:30")
    }

    func testRepeatRejectsBadRanges() {
        XCTAssertNil(SeriesPlanner.expand(.init(title: "x", from: "2026-11-20", to: "2026-11-16")))
        XCTAssertNil(SeriesPlanner.expand(.init(title: "x", from: "내일", to: "2026-11-16")))
        XCTAssertNil(SeriesPlanner.expand(.init(title: "  ", from: "2026-11-16", to: "2026-11-17")))
        XCTAssertNil(SeriesPlanner.expand(.init(title: "x", from: "2026-11-16", to: "2026-11-22", weekdays: [9])))
    }

    func testRepeatIsCappedAtMaxDays() {
        let draft = SeriesPlanner.expand(.init(title: "x", from: "2026-01-01", to: "2026-12-31"))
        XCTAssertEqual(draft?.days.count, SeriesPlanner.maxDays)
    }

    func testSpreadDropsInvalidRowsAndSortsByDate() {
        let spread = AIPlan.Spread(title: "포트폴리오", days: [
            .init(date: "2026-11-18", title: "사례 2 정리"),
            .init(date: "2026-11-17", title: "사례 1 정리"),
            .init(date: "2026-02-31", title: "없는 날"),
            .init(date: "2026-11-19", title: " "),
        ])
        let draft = SeriesPlanner.clean(spread)
        XCTAssertEqual(draft?.days.map(\.title), ["사례 1 정리", "사례 2 정리"])
    }

    func testEmptySpreadIsNil() {
        XCTAssertNil(SeriesPlanner.clean(.init(title: "x", days: [])))
    }

    func testDecodesRepeatsAndSpreadsFromTool() throws {
        let json = #"{"content":[{"type":"tool_use","name":"apply_plan","input":{"reply":"확인해 주세요","repeats":[{"title":"운동","from":"2026-11-16","to":"2026-11-18"}],"spreads":[{"title":"발표 준비","days":[{"date":"2026-11-16","title":"목차 짜기"}]}]}}]}"#
        let plan = try JSONDecoder().decode(AIPlan.self, from: ClaudeClient.toolInput(from: Data(json.utf8)))
        let drafts = SeriesPlanner.drafts(from: plan)
        XCTAssertEqual(drafts.map(\.title), ["운동", "발표 준비"])
        XCTAssertEqual(drafts.first?.days.count, 3)
    }
}

final class TodoSeriesTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func testFutureSeriesItemsStayOutOfList() {
        let now = day(16, hour: 9)
        let series = UUID()
        let today = TodoItem(title: "운동", scheduledAt: day(16))
        let tomorrow = TodoItem(title: "운동", scheduledAt: day(17))
        let overdue = TodoItem(title: "운동", scheduledAt: day(15))
        for todo in [today, tomorrow, overdue] { todo.seriesID = series }
        let plainFuture = TodoItem(title: "치과", scheduledAt: day(20))
        XCTAssertTrue(TodoSeries.showsInList(today, now: now))
        XCTAssertTrue(TodoSeries.showsInList(overdue, now: now))
        XCTAssertFalse(TodoSeries.showsInList(tomorrow, now: now))
        XCTAssertTrue(TodoSeries.showsInList(plainFuture, now: now))
    }

    func testFollowingIncludesSameDayAndLaterOfSameSeries() {
        let series = UUID()
        let items = (15...18).map { d -> TodoItem in
            let todo = TodoItem(title: "운동", scheduledAt: day(d))
            todo.seriesID = series
            return todo
        }
        let other = TodoItem(title: "다른 묶음", scheduledAt: day(18))
        other.seriesID = UUID()
        let following = TodoSeries.following(items[1], in: items + [other])
        XCTAssertEqual(following.map(\.id), [items[1].id, items[2].id, items[3].id])
    }

    func testFollowingOfPlainTodoIsItself() {
        let todo = TodoItem(title: "치과", scheduledAt: day(16))
        XCTAssertEqual(TodoSeries.following(todo, in: [todo]).map(\.id), [todo.id])
    }
}

@MainActor
final class SeriesApplierTests: XCTestCase {
    func testSaveCreatesLinkedItemsAndUndoRemovesThem() throws {
        let context = ModelContext(try PocketStore.makeContainer(inMemory: true))
        let draft = try XCTUnwrap(SeriesPlanner.expand(.init(title: "운동", from: "2026-11-16", to: "2026-11-18", start_time: "07:00")))
        let created = try SeriesApplier.save(draft, in: context)
        XCTAssertEqual(created.count, 3)
        XCTAssertEqual(Set(created.compactMap(\.seriesID)).count, 1)
        XCTAssertTrue(created.allSatisfy(\.isEvent))
        _ = try PlanApplier.undo(.init(created: created.map(\.id), before: [], touched: [], undone: false), in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoItem>()), 0)
    }

    func testDescribeOnlyListsNearSeriesItems() throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let draft = try XCTUnwrap(SeriesPlanner.expand(.init(title: "운동", from: "2026-11-16", to: "2026-12-31")))
        let context = ModelContext(try PocketStore.makeContainer(inMemory: true))
        let created = try SeriesApplier.save(draft, in: context)
        let text = PlanApplier.describe(created, now: now)
        XCTAssertEqual(text.split(separator: "\n").count, 8) // 오늘부터 7일 뒤까지
        XCTAssertTrue(text.contains("묶음="))
    }
}

final class BuyRulesTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func testBoughtItemCountsDownThreeDays() {
        let item = BuyItem(name: "휴지")
        XCTAssertNil(BuyRules.daysLeft(item, now: day(17)))
        item.setBought(true, now: day(17, hour: 23))
        XCTAssertEqual(BuyRules.daysLeft(item, now: day(17)), 3)
        XCTAssertEqual(BuyRules.daysLeft(item, now: day(18, hour: 1)), 2)
        XCTAssertFalse(BuyRules.isExpired(item, now: day(19)))
        XCTAssertTrue(BuyRules.isExpired(item, now: day(20, hour: 0)))
    }

    func testUnboughtItemNeverExpires() {
        let item = BuyItem(name: "우유", createdAt: day(1))
        XCTAssertFalse(BuyRules.isExpired(item, now: day(30)))
    }

    func testMetaJoinsOnlyKnownFields() {
        let item = BuyItem(name: "세제", quantity: "1개", dueDate: day(22), store: "다이소")
        XCTAssertEqual(BuyRules.meta(item, now: day(17)), "1개 · 11월 22일까지 · 다이소")
        XCTAssertEqual(BuyRules.meta(BuyItem(name: "밴드", store: "약국"), now: day(17)), "약국")
        XCTAssertEqual(BuyRules.meta(BuyItem(name: "물"), now: day(17)), "")
    }

    func testBoughtMetaSaysWhenItDisappears() {
        let item = BuyItem(name: "샴푸", quantity: "1개")
        item.setBought(true, now: day(16))
        XCTAssertEqual(BuyRules.meta(item, now: day(17)), "어제 삼 · 2일 뒤 지워져요")
        item.setBought(true, now: day(17, hour: 8))
        XCTAssertEqual(BuyRules.meta(item, now: day(17)), "오늘 삼 · 3일 뒤 지워져요")
    }

    func testOpenItemsSortByDueThenCreation() {
        let a = BuyItem(name: "a", createdAt: day(1))
        let b = BuyItem(name: "b", dueDate: day(25), createdAt: day(2))
        let c = BuyItem(name: "c", dueDate: day(20), createdAt: day(3))
        XCTAssertEqual(BuyRules.sortedOpen([a, b, c]).map(\.name), ["c", "b", "a"])
    }
}

final class BuyPlannerTests: XCTestCase {
    func testCleanTrimsDropsBlankAndInvalidDue() {
        let items = BuyPlanner.clean([
            .init(name: " 우유 ", quantity: "2개"),
            .init(name: "  "),
            .init(name: "세제", due_date: "2026-02-31", store: "다이소"),
        ])
        XCTAssertEqual(items.map(\.name), ["우유", "세제"])
        XCTAssertNil(items[1].due_date)
        XCTAssertEqual(items[1].store, "다이소")
    }

    func testLabelReadsLikeTheCard() {
        let item = AIPlan.Buy(name: "세제", quantity: "1개", due_date: "2026-11-22", store: "다이소")
        XCTAssertEqual(BuyPlanner.label(item), "세제 · 1개 · 11월 22일까지 · 다이소")
    }

    func testDecodesBuysFromTool() throws {
        let json = #"{"content":[{"type":"tool_use","name":"apply_plan","input":{"reply":"확인해 주세요","buys":[{"name":"우유","quantity":"2개"},{"name":"계란"}]}}]}"#
        let plan = try JSONDecoder().decode(AIPlan.self, from: ClaudeClient.toolInput(from: Data(json.utf8)))
        XCTAssertEqual(plan.buys?.map(\.name), ["우유", "계란"])
        XCTAssertNil(plan.create)
    }
}

@MainActor
final class BuyApplierTests: XCTestCase {
    private func context() throws -> ModelContext {
        ModelContext(try PocketStore.makeContainer(inMemory: true))
    }

    func testSaveThenUndo() throws {
        let context = try context()
        let saved = try BuyApplier.save([.init(name: "우유", quantity: "2개"), .init(name: "세제", due_date: "2026-11-22")], in: context)
        XCTAssertEqual(saved.count, 2)
        XCTAssertNotNil(saved[1].dueDate)
        try BuyApplier.undo(saved.map(\.id), in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuyItem>()), 0)
    }

    func testPurgeRemovesOnlyExpired() throws {
        let context = try context()
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9))!
        let old = BuyItem(name: "휴지")
        old.setBought(true, now: calendar.date(byAdding: .day, value: -3, to: now)!)
        let recent = BuyItem(name: "샴푸")
        recent.setBought(true, now: calendar.date(byAdding: .day, value: -1, to: now)!)
        let open = BuyItem(name: "우유")
        for item in [old, recent, open] { context.insert(item) }
        try context.save()
        XCTAssertEqual(try BuyApplier.purge(in: context, now: now), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BuyItem>()).map(\.name).sorted(), ["샴푸", "우유"])
    }
}

final class APIKeySourceTests: XCTestCase {
    func testKeychainWinsOverEnvironment() {
        XCTAssertEqual(APIKeySource.resolve(keychain: "from-keychain", environment: ["ANTHROPIC_API_KEY": "from-env"]), "from-keychain")
    }

    func testFallsBackToEnvironmentWhenKeychainEmpty() {
        XCTAssertEqual(APIKeySource.resolve(keychain: nil, environment: ["ANTHROPIC_API_KEY": " from-env\n"]), "from-env")
        XCTAssertEqual(APIKeySource.resolve(keychain: "", environment: ["ANTHROPIC_API_KEY": "from-env"]), "from-env")
    }

    func testNothingWhenBothEmpty() {
        XCTAssertNil(APIKeySource.resolve(keychain: nil, environment: [:]))
        XCTAssertNil(APIKeySource.resolve(keychain: nil, environment: ["ANTHROPIC_API_KEY": "  "]))
    }
}

final class RecognitionRetryTests: XCTestCase {
    func testOnDeviceFailureWithoutTextFallsBackToServer() {
        var retry = RecognitionRetry(onDevice: true)
        XCTAssertEqual(retry.afterFailure(heardText: false), .restart(onDevice: false))
    }

    func testRepeatedFailuresWithoutTextGiveUp() {
        var retry = RecognitionRetry(onDevice: false)
        XCTAssertEqual(retry.afterFailure(heardText: false), .restart(onDevice: false))
        XCTAssertEqual(retry.afterFailure(heardText: false), .giveUp)
    }

    func testFailureAfterHearingKeepsModeAndResetsCount() {
        var retry = RecognitionRetry(onDevice: true)
        XCTAssertEqual(retry.afterFailure(heardText: true), .restart(onDevice: true))
        XCTAssertEqual(retry.afterFailure(heardText: true), .restart(onDevice: true))
        XCTAssertEqual(retry.afterFailure(heardText: false), .restart(onDevice: false))
    }

    func testNeverLoopsForever() {
        var retry = RecognitionRetry(onDevice: true)
        var restarts = 0
        while case .restart = retry.afterFailure(heardText: false) { restarts += 1; if restarts > 10 { break } }
        XCTAssertLessThanOrEqual(restarts, 2)
    }
}

final class TimelineLayoutTests: XCTestCase {
    private let calendar = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: h, minute: m))! }

    func testBlockPositionFollowsStartAndEnd() {
        let blocks = TimelineLayout.blocks([.init(id: UUID(), start: at(10), end: at(11, 30))], hourHeight: 64)
        XCTAssertEqual(blocks.first?.top, 640)
        XCTAssertEqual(blocks.first?.height, 96)
        XCTAssertEqual(blocks.first?.columns, 1)
    }

    func testMissingEndUsesOneHourAndShortEventsKeepMinimumHeight() {
        let blocks = TimelineLayout.blocks([
            .init(id: UUID(), start: at(9), end: nil),
            .init(id: UUID(), start: at(12), end: at(12, 5)),
        ], hourHeight: 64)
        XCTAssertEqual(blocks[0].height, 64)
        XCTAssertEqual(blocks[1].height, TimelineLayout.minHeight)
    }

    func testOverlappingEventsShareWidth() {
        let a = UUID(), b = UUID(), c = UUID()
        let blocks = TimelineLayout.blocks([
            .init(id: a, start: at(10), end: at(11)),
            .init(id: b, start: at(10, 30), end: at(11, 30)),
            .init(id: c, start: at(13), end: at(14)),
        ], hourHeight: 64)
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        XCTAssertEqual(byID[a]?.columns, 2)
        XCTAssertEqual(byID[b]?.columns, 2)
        XCTAssertNotEqual(byID[a]?.column, byID[b]?.column)
        XCTAssertEqual(byID[c]?.columns, 1)
        XCTAssertEqual(byID[c]?.column, 0)
    }

    func testNowOffset() {
        XCTAssertEqual(TimelineLayout.offset(of: at(13, 30), hourHeight: 64), 864)
    }
}

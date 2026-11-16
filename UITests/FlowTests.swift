import XCTest

final class FlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// 카드와 줄 버튼은 제목과 값이 합쳐진 이름을 가져서 앞부분으로 찾는다.
    private func button(_ label: String) -> XCUIElement {
        let exact = app.buttons[label].firstMatch
        if exact.exists { return exact }
        let partial = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        return partial.waitForExistence(timeout: 3) ? partial : exact
    }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = button(label)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "버튼 없음: \(label)", file: file, line: line)
        target.tap()
    }

    private func see(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        // 버튼 안의 글자는 버튼 이름으로 합쳐지므로 모든 요소의 이름에서 찾는다.
        let target = shown(text)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "글자 없음: \(text)", file: file, line: line)
    }

    private func shown(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 시트가 닫히는 동안에는 뒤 화면과 함께 남아 있어 사라질 때까지 기다린다.
    private func disappears(_ text: String) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: shown(text))
        return XCTWaiter.wait(for: [gone], timeout: 5) == .completed
    }

    /// 휴지통 아이콘과 이름이 같아, 글자가 있는 넓은 쪽을 누른다.
    private func confirmDelete() {
        let buttons = app.buttons.matching(identifier: "삭제").allElementsBoundByIndex
        buttons.first { $0.frame.width > 44 }?.tap()
    }

    private func input(_ placeholder: String) -> XCUIElement {
        let predicate = NSPredicate(format: "placeholderValue == %@", placeholder)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func type(_ text: String, into placeholder: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = input(placeholder)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "입력칸 없음: \(placeholder)", file: file, line: line)
        field.tap()
        field.typeText(text)
    }

    func testOnboarding() {
        app.launchArguments = ["-onboarded", "NO"]
        app.launch()
        see("POCKET")
        shot("onboard-start")
        tap("시작하기")
        see("이 권한을 쓸게요")
        shot("onboard-permissions")
    }

    func testTodoAddEditFocusComplete() {
        app.launch()
        shot("todo-main")
        tap("할 일 추가")
        see("새 할 일")
        shot("todo-new")
        type("자동 테스트 할 일", into: "할 일을 입력하세요")
        tap("확인")
        shot("after-save")
        see("자동 테스트 할 일")

        button("자동 테스트 할 일").tap()
        see("할 일 수정")
        shot("todo-edit")

        tap("날짜")
        see("2026년 11월")
        shot("pick-date")
        tap("확인")
        tap("시간")
        shot("pick-time")
        tap("확인")
        tap("알림")
        shot("pick-alert")
        tap("닫기")

        tap("작업 시작")
        see("타이머")
        shot("focus-idle")
        tap("시작")
        see("일시정지")
        shot("focus-running")
        tap("일시정지")
        see("일시정지 중이에요")
        shot("focus-paused")
        tap("완료")
        see("완료 2")
    }

    func testTodoDeleteAsksFirst() {
        app.launch()
        button("치과 예약 전화하기").tap()
        tap("삭제")
        see("할 일을 삭제할까요?")
        shot("todo-delete")
        tap("취소")
        see("할 일 수정")
        tap("삭제")
        confirmDelete()
        XCTAssertTrue(disappears("치과 예약 전화하기"))
        XCTAssertTrue(shown("보험 서류 제출하기").exists)
    }

    func testSearch() {
        app.launch()
        tap("검색")
        app.typeText("이사")
        see("이사 준비")
        XCTAssertFalse(shown("보험 서류 제출하기").exists)
        shot("todo-search")
    }

    func testMemoAddAndDelete() {
        app.launch()
        tap("Memo")
        see("와이파이 비밀번호")
        tap("메모 추가")
        see("새 메모")
        shot("memo-new")
        type("장볼 것 우유와 계란", into: "내용을 입력하세요")
        tap("확인")
        see("장볼 것 우유와 계란")
        shot("memo-list")
        button("와이파이 비밀번호").tap()
        see("메모 수정")
        shot("memo-edit")
        tap("삭제")
        see("메모를 삭제할까요?")
        confirmDelete()
        XCTAssertTrue(disappears("와이파이 비밀번호"))
        XCTAssertTrue(shown("온보딩 흐름 정리").exists)
    }

    func testChatWithoutKeyKeepsTextAndOffersRetry() {
        app.launch()
        tap("Chat")
        type("내일 세 시 치과", into: "말하거나 입력해 보세요")
        tap("보내기")
        see("내일 세 시 치과")
        see("정리하지 못했어요")
        see("설정에서 Claude API 키를 넣어 주세요.")
        shot("chat-error")
    }

    func testSettingsAndKeySheet() {
        app.launch()
        tap("설정")
        see("Claude API 키")
        shot("settings")
        button("Claude API 키").tap()
        see("API 키")
        shot("settings-key")
    }

    func testBuyAddCheckAndDelete() {
        app.launch()
        tap("Buy")
        see("우유")
        see("1개 · ")
        shot("buy-main")
        tap("살 것 추가")
        see("새 살 것")
        type("자동 테스트 살 것", into: "살 것을 입력하세요")
        tap("확인")
        see("자동 테스트 살 것")
        tap("자동 테스트 살 것 샀어요")
        see("산 것 3")
        shot("buy-bought")
        // "계란 샀어요" 체크 버튼과 이름이 겹쳐 글자를 직접 누른다.
        app.staticTexts["계란"].firstMatch.tap()
        see("살 것 수정")
        shot("buy-edit")
        tap("삭제")
        see("살 것을 삭제할까요?")
        confirmDelete()
        XCTAssertTrue(disappears("계란"))
        XCTAssertTrue(shown("우유").exists)
    }

    func testBuyPreviewSavesFromChat() {
        app.launch()
        tap("Chat")
        app.swipeUp()
        see("세제 · 1개")
        tap("3개 추가하기")
        see("Buy에 3개 저장됨")
        shot("chat-buy-saved")
        tap("Buy")
        XCTAssertTrue(app.staticTexts.matching(identifier: "세제").count >= 2)
    }

    /// 입력 중에는 탭바가 입력칸을 가리지 않아야 한다. 화면 키보드든 하드웨어 키보드든 같다.
    func testTabBarDoesNotCoverChatInputWhileTyping() {
        app.launch()
        tap("Chat")
        let field = input("말하거나 입력해 보세요")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        sleep(1) // 여백과 키보드 애니메이션이 끝날 때까지
        shot("chat-typing")
        let chatTab = app.buttons["Chat"].firstMatch
        let covers = chatTab.exists && chatTab.isHittable && chatTab.frame.intersects(field.frame)
        XCTAssertFalse(covers, "탭바가 입력칸을 가림: tab=\(chatTab.frame) field=\(field.frame)")
    }

    func testPlanTab() {
        app.launch()
        tap("Plan")
        see("팀 주간 회의")
        shot("plan")
        tap("시간표 보기")
        see("오전 10:00")
        see("팀 주간 회의")
        shot("plan-timeline")
        tap("목록 보기")
        tap("더보기")
        see("설정")
        shot("plan-more")
    }
}

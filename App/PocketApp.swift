import SwiftData
import SwiftUI
import UIKit

@main
struct PocketApp: App {
    private let container: ModelContainer
    @StateObject private var router = Router()
    @StateObject private var network = NetworkMonitor()

    init() {
        do {
            #if DEBUG
            let demo = ProcessInfo.processInfo.arguments.contains("-demo")
            container = try PocketStore.makeContainer(inMemory: demo)
            if demo { DemoData.seed(container.mainContext) }
            #else
            container = try PocketStore.makeContainer()
            #endif
        } catch {
            // 저장소를 못 열면 새로 만들어 지우지 않는다. 사용자의 데이터를 지키는 쪽을 택한다.
            fatalError("저장소를 열지 못했습니다: \(error)")
        }
        UserDefaults.standard.register(defaults: [SettingKey.defaultTimer: 25])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(network)
                .tint(Tone.ink)
                .environment(\.locale, Format.locale)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { router.handle(link) }
                }
        }
        .modelContainer(container)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    // 순서가 곧 탭바 순서다.
    case todo, plan, chat, memo, buy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "Todo"
        case .plan: "Plan"
        case .chat: "Chat"
        case .memo: "Memo"
        case .buy: "Buy"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "checkmark.square"
        case .plan: "calendar"
        case .chat: "bubble.left"
        case .memo: "doc.text"
        case .buy: "bag"
        }
    }
}

enum EditRoute: Identifiable, Equatable {
    case existing(UUID)
    case new(on: Date?, focusTitle: Bool)

    var id: String {
        switch self {
        case .existing(let id): id.uuidString
        case .new: "new"
        }
    }
}

enum MemoRoute: Identifiable, Equatable {
    case existing(UUID), new
    var id: String {
        switch self {
        case .existing(let id): id.uuidString
        case .new: "new"
        }
    }
}

enum VoiceMemoRoute: Identifiable, Equatable {
    case new(initial: String), append(UUID)
    var id: String {
        switch self {
        case .new: "new"
        case .append(let id): id.uuidString
        }
    }
}

struct FocusRoute: Identifiable, Equatable { let id: UUID }

enum PermissionKind: Equatable { case microphone, calendar, notifications }

@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = {
        #if DEBUG
        // 화면 확인용: -tab memo 처럼 시작 탭을 고른다.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count,
           let tab = AppTab(rawValue: arguments[index + 1]) { return tab }
        #endif
        return .todo
    }()
    @Published var edit: EditRoute?
    @Published var memo: MemoRoute?
    @Published var buyEdit: BuyRoute?
    @Published var voiceMemo: VoiceMemoRoute?
    @Published var focus: FocusRoute?
    @Published var showSettings = false
    @Published var permission: PermissionKind?
    /// 채팅 입력 중에는 탭바를 숨긴다. 남아 있으면 입력칸을 가린다.
    @Published var hidesTabBar = false

    /// 채팅 탭이 듣기를 시작해야 하면 true. 탭을 다시 열어도 다시 듣지 않도록 처리 후 끈다.
    @Published var chatVoicePending = false
    @Published var chatText: String?
    @Published var breakdownRequest: UUID?

    /// 시트가 닫힌 뒤 열 전체 화면. 시트가 떠 있는 동안에는 띄울 수 없다.
    var afterDismiss: (() -> Void)?

    func runAfterDismiss() {
        let action = afterDismiss
        afterDismiss = nil
        action?()
    }

    func startChatVoice() {
        tab = .chat
        chatVoicePending = true
    }

    func startFocus(_ id: UUID) {
        if edit != nil {
            afterDismiss = { [weak self] in self?.focus = FocusRoute(id: id) }
            edit = nil
        } else {
            focus = FocusRoute(id: id)
        }
    }

    func sendToChat(_ text: String) {
        tab = .chat
        chatText = text
    }

    func askBreakdown(_ id: UUID) {
        tab = .chat
        breakdownRequest = id
    }

    func handle(_ link: DeepLink) {
        // 시트가 떠 있으면 닫힌 뒤에 연다. 닫히는 중에 띄우면 무시된다.
        if edit != nil || memo != nil || buyEdit != nil {
            afterDismiss = { [weak self] in self?.open(link) }
            edit = nil
            memo = nil
            buyEdit = nil
        } else {
            open(link)
        }
    }

    private func open(_ link: DeepLink) {
        switch link {
        case .voice: startChatVoice()
        case .memo:
            tab = .memo
            voiceMemo = .new(initial: "")
        case .newTodo:
            tab = .todo
            edit = .new(on: nil, focusTitle: true)
        case .todo(let id):
            tab = .todo
            edit = .existing(id)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var router: Router
    @AppStorage(SettingKey.onboarded) private var onboarded = false

    var body: some View {
        if onboarded || ProcessInfo.processInfo.arguments.contains("-demo") {
            MainView()
        } else {
            OnboardingView { onboarded = true }
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var dialog: ConfirmDialog?
    @State private var refresh = UUID()

    var body: some View {
        ZStack(alignment: .bottom) {
            Tone.bg.ignoresSafeArea()
            Group {
                switch router.tab {
                case .todo: TodoListView()
                case .plan: PlanView()
                case .chat: ChatView()
                case .memo: MemoListView()
                case .buy: BuyListView()
                }
            }
            .id(router.tab == .chat ? nil : refresh)
            if !router.hidesTabBar {
                TabBar(selection: $router.tab)
                    .ignoresSafeArea(.keyboard)
            }
        }
        .sheet(item: $router.edit, onDismiss: router.runAfterDismiss) { TodoEditView(route: $0) }
        .sheet(item: $router.memo, onDismiss: router.runAfterDismiss) { MemoEditView(route: $0) }
        .sheet(item: $router.buyEdit, onDismiss: router.runAfterDismiss) { BuyEditView(route: $0) }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .fullScreenCover(item: $router.voiceMemo) { VoiceMemoView(route: $0) }
        .fullScreenCover(item: $router.focus) { FocusView(todoID: $0.id) }
        .confirmDialog($dialog) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refresh = UUID() // 위젯에서 바꾼 내용을 다시 읽는다.
            reconcileWidgetChanges()
            try? BuyApplier.purge(in: context)
        }
        .onChange(of: router.permission) { _, kind in
            guard let kind else { return }
            dialog = Self.dialog(for: kind)
            router.permission = nil
        }
    }

    /// 위젯에서 완료한 일정은 캘린더에서 뺀다. 위젯에서는 캘린더를 건드리지 않는다.
    private func reconcileWidgetChanges() {
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.isDone && $0.calendarEventID != nil })
        guard let finished = try? context.fetch(descriptor) else { return }
        for todo in finished { CalendarService.remove(todo) }
        try? context.save()
    }

    static func dialog(for kind: PermissionKind) -> ConfirmDialog {
        switch kind {
        case .microphone:
            ConfirmDialog(title: "마이크를 쓸 수 없어요", message: "말로 입력하려면 설정에서 마이크와 음성 인식을 허용해 주세요.", cancel: "나중에", confirm: "설정 열기")
        case .calendar:
            ConfirmDialog(title: "캘린더에 넣지 못했어요", message: "일정은 POCKET에 저장됐어요. iOS 캘린더에도 넣으려면 설정에서 허용해 주세요.", cancel: "나중에", confirm: "설정 열기")
        case .notifications:
            ConfirmDialog(title: "알림을 보낼 수 없어요", message: "알림을 받으려면 설정에서 허용해 주세요.", cancel: "나중에", confirm: "설정 열기")
        }
    }
}

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let active = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol).font(.system(size: 18, weight: active ? .semibold : .regular))
                        Text(tab.title).font(.pTab)
                    }
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(active ? Tone.accentSoft : .clear, in: Capsule())
                }
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Tone.surface, in: Capsule())
        .floatShadow()
        .padding(.horizontal, 16)
        .padding(.bottom, -12)
    }
}

/// 탭바에 가려지지 않도록 목록 아래에 두는 여백.
let tabBarClearance: CGFloat = 76

#if DEBUG
enum DemoData {
    @MainActor
    static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ h: Int, _ m: Int = 0) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: today)! }

        context.insert(TodoItem(title: "보험 서류 제출하기", estimateMinutes: 15))
        context.insert(TodoItem(title: "치과 예약 전화하기", estimateMinutes: 5))
        let moving = TodoItem(title: "이사 준비", estimateMinutes: 120)
        moving.subtasks = [Subtask(title: "전입신고 서류 확인하기", order: 0)]
        context.insert(moving)
        let done = TodoItem(title: "장보기")
        done.setDone(true)
        context.insert(done)
        context.insert(TodoItem(title: "팀 주간 회의", scheduledAt: at(10), hasTime: true, endAt: at(11)))
        context.insert(TodoItem(title: "디자인 리뷰", scheduledAt: at(15), hasTime: true, endAt: at(17)))
        context.insert(Memo(title: "온보딩 흐름 정리", body: "첫 화면은 설명을 줄이고 바로 말해보게 하는 쪽이 낫겠다. 위젯 안내는 첫 메모를 남긴 다음에 보여주기.", isVoice: true))
        let inFive = calendar.date(byAdding: .day, value: 5, to: today)!
        context.insert(BuyItem(name: "우유", quantity: "2개", store: "마트"))
        context.insert(BuyItem(name: "계란", quantity: "2판", store: "마트"))
        context.insert(BuyItem(name: "세제", quantity: "1개", dueDate: inFive, store: "다이소"))
        context.insert(BuyItem(name: "밴드", store: "약국"))
        let tissue = BuyItem(name: "휴지")
        tissue.setBought(true)
        context.insert(tissue)
        let shampoo = BuyItem(name: "샴푸")
        shampoo.setBought(true, now: calendar.date(byAdding: .day, value: -1, to: .now)!)
        context.insert(shampoo)
        context.insert(Memo(title: "와이파이 비밀번호", body: "현관 옆 메모판에 적어두기", isVoice: false))
        context.insert(ChatMessage(isMine: true, text: "오후 세 시부터 다섯 시까지 디자인 리뷰 일정 넣어줘"))
        context.insert(ChatMessage(isMine: false, text: "디자인 리뷰를 일정에 넣고 iOS 캘린더에도 추가했어요."))
        let start = PlanDate.string(from: today)
        let end = PlanDate.string(from: calendar.date(byAdding: .day, value: 13, to: today)!)
        if let draft = SeriesPlanner.expand(.init(title: "아침 러닝", from: start, to: end, weekdays: [1, 3, 5], start_time: "07:00", end_time: "07:30")) {
            context.insert(ChatMessage(isMine: true, text: "앞으로 2주 동안 월수금 아침 7시에 러닝 넣어줘"))
            context.insert(ChatMessage(
                isMine: false, text: "2주 동안 월수금 아침 러닝을 잡아 봤어요. 확인해 주세요.",
                payload: ChatPayload.series(.init(draft: draft, created: [], undone: false)).encoded))
        }
        let due = PlanDate.string(from: inFive)
        context.insert(ChatMessage(isMine: true, text: "우유 두 개랑 계란 두 판, 다이소에서 세제 사야 해"))
        context.insert(ChatMessage(
            isMine: false, text: "살 것 3개로 정리했어요. 확인하고 추가해 주세요.",
            payload: ChatPayload.buys(.init(items: [
                .init(name: "우유", quantity: "2개"), .init(name: "계란", quantity: "2판"),
                .init(name: "세제", quantity: "1개", due_date: due, store: "다이소"),
            ], created: [], undone: false)).encoded))
        try? context.save()
    }
}
#endif

import SwiftData
import SwiftUI

struct MemoListView: View {
    @EnvironmentObject private var router: Router
    @Query(sort: \Memo.updatedAt, order: .reverse) private var memos: [Memo]
    @State private var searching = false
    @State private var query = ""

    private var shown: [Memo] {
        guard searching else { return memos }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return memos.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if searching {
                    HStack(spacing: 8) {
                        SearchField(text: $query)
                        IconButton(symbol: "xmark", label: "검색 닫기") {
                            searching = false
                            query = ""
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 60)
                } else {
                    TabHeader(title: "Memo") {
                        IconButton(symbol: "magnifyingglass", label: "검색") { searching = true }
                        IconButton(symbol: "plus", label: "메모 추가") { router.memo = .new }
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !searching && memos.isEmpty {
                            EmptyState(symbol: "doc.text", title: "아직 메모가 없어요", caption: "녹음 버튼을 눌러 말해 보세요")
                        }
                        if searching, shown.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            EmptyState(symbol: "magnifyingglass", title: "검색 결과가 없어요", caption: "다른 말로 찾아보세요")
                        }
                        ForEach(shown) { MemoCard(memo: $0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, tabBarClearance + 110)
                }
            }
            if !searching {
                VStack(spacing: 8) {
                    RoundButton(symbol: "mic", size: 72, label: "받아쓰기 시작") { router.voiceMemo = .new(initial: "") }
                    Text("눌러서 바로 받아쓰기").font(.pCaption).foregroundStyle(Tone.ink2)
                }
                .padding(.bottom, tabBarClearance)
            }
        }
    }
}

struct MemoCard: View {
    @EnvironmentObject private var router: Router
    let memo: Memo

    var body: some View {
        Button { router.memo = .existing(memo.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.title).font(.pTitle).foregroundStyle(Tone.ink).lineLimit(1)
                Text(memo.body).font(.pBody).foregroundStyle(Tone.ink2).lineLimit(3).multilineTextAlignment(.leading)
                MemoMeta(memo: memo).padding(.top, 4)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct MemoMeta: View {
    let memo: Memo
    var body: some View {
        HStack(spacing: 4) {
            if memo.isVoice { Image(systemName: "mic").font(.system(size: 11)) }
            Text("\(Format.day(memo.createdAt)) · \(memo.isVoice ? "음성" : "직접 입력")").font(.pCaption)
        }
        .foregroundStyle(Tone.ink3)
    }
}

struct MemoEditView: View {
    let route: MemoRoute

    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var memo: Memo?
    @State private var title = ""
    @State private var bodyText = ""
    @State private var loaded = false
    @State private var dialog: ConfirmDialog?

    private var isNew: Bool { memo == nil }
    private var hasContent: Bool { !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            SheetHeader(title: isNew ? "새 메모" : "메모 수정", onClose: { dismiss() }, onConfirm: save)
            VStack(alignment: .leading, spacing: 4) {
                Text("제목").font(.pCaption).foregroundStyle(Tone.ink2)
                TextField(isNew ? "비워 두면 AI가 지어요" : "제목", text: $title).font(.pHeadline)
            }
            .card()
            VStack(alignment: .leading, spacing: 12) {
                Text("내용").font(.pCaption).foregroundStyle(Tone.ink2)
                TextField("내용을 입력하세요", text: $bodyText, axis: .vertical).font(.pBody)
                if let memo { MemoMeta(memo: memo) }
                Spacer(minLength: 0)
            }
            .card()
            HStack(spacing: 8) {
                if !isNew {
                    IconButton(symbol: "trash", label: "삭제") {
                        dialog = ConfirmDialog(title: "메모를 삭제할까요?", message: "삭제한 메모는 되돌릴 수 없어요.", confirm: "삭제")
                    }
                    ActionButton(title: "할 일·일정으로", kind: .secondary, symbol: "sparkle", fullWidth: true) {
                        let text = bodyText
                        persist()
                        dismiss()
                        router.sendToChat(text)
                    }
                    .disabled(!hasContent)
                } else {
                    Spacer()
                }
                RoundButton(symbol: "mic", size: 44, label: "이어서 말하기") { continueByVoice() }
            }
        }
        .padding(16)
        .background(Tone.bg)
        .presentationCornerRadius(20)
        .onAppear(perform: load)
        .confirmDialog($dialog) { _ in
            if let memo {
                context.delete(memo)
                try? context.save()
            }
            dismiss()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .existing(let id) = route {
            let descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
            if let found = try? context.fetch(descriptor).first {
                memo = found
                title = found.title
                bodyText = found.body
            }
        }
    }

    private func persist() {
        guard hasContent else { return }
        if let memo {
            memo.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? MemoTitle.fallback(from: bodyText) : title
            memo.body = bodyText
            memo.updatedAt = .now
        } else {
            let created = Memo(title: title, body: bodyText, isVoice: false)
            if title.trimmingCharacters(in: .whitespaces).isEmpty {
                MemoTitler.fill(created, in: context)
            }
            context.insert(created)
            memo = created
        }
        try? context.save()
    }

    private func save() {
        persist()
        dismiss()
    }

    private func continueByVoice() {
        persist()
        if let id = memo?.id {
            router.afterDismiss = { [router] in router.voiceMemo = .append(id) }
        } else {
            router.afterDismiss = { [router] in router.voiceMemo = .new(initial: "") }
        }
        dismiss()
    }
}

/// 제목을 먼저 임시로 넣어 저장하고, AI 제목이 오면 바꾼다. AI 가 실패해도 메모는 남는다.
@MainActor
enum MemoTitler {
    static func fill(_ memo: Memo, in context: ModelContext) {
        let placeholder = MemoTitle.fallback(from: memo.body)
        memo.title = placeholder
        let body = memo.body
        Task {
            guard let title = try? await ClaudeClient().memoTitle(body: body), memo.title == placeholder else { return }
            memo.title = title
            try? context.save()
        }
    }
}

/// 긴 말을 받아쓰는 화면. 정지하면 제목을 붙여 저장한다.
struct VoiceMemoView: View {
    let route: VoiceMemoRoute

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: Router
    @StateObject private var speech = SpeechService()
    @State private var dialog: ConfirmDialog?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(symbol: "xmark", label: "닫기", action: close)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Chip(text: "메모에 넣는 중 · \(Format.timer(seconds: elapsed(at: timeline.date)))", soft: true)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)

            ScrollView {
                Text(speech.transcript.isEmpty ? "말씀하세요" : speech.transcript)
                    .font(.pHeadline)
                    .foregroundStyle(speech.transcript.isEmpty ? Tone.ink3 : Tone.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            VStack(spacing: 12) {
                Text(failureText ?? "멈추면 제목을 붙여 메모에 자동으로 저장해요")
                    .font(.pCaption)
                    .foregroundStyle(Tone.ink2)
                Waveform(level: speech.level, height: 40)
                RoundButton(symbol: "stop", size: 64, label: "정지하고 저장") { finish() }
            }
            .padding(.bottom, 24)
        }
        .background(Tone.surface)
        .confirmDialog($dialog) { current in
            if current.confirm == "버리기" {
                speech.discard()
                dismiss()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .task { await start() }
        .onChange(of: speech.failure) { _, failure in
            if failure == .denied { dialog = MainView.dialog(for: .microphone) }
        }
    }

    private var failureText: String? {
        switch speech.failure {
        case .unavailable: "지금은 음성 인식을 쓸 수 없어요"
        case .noSpeech: "잘 못 들었어요"
        default: nil
        }
    }

    private func elapsed(at now: Date) -> Int {
        guard let started = speech.startedAt else { return 0 }
        return Int(now.timeIntervalSince(started))
    }

    private func start() async {
        if case .new(let initial) = route {
            await speech.start(keeping: initial)
        } else {
            await speech.start()
        }
    }

    private func close() {
        if speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            speech.discard()
            dismiss()
        } else {
            dialog = ConfirmDialog(title: "받아쓴 내용을 버릴까요?", message: "지금까지 받아쓴 내용은 저장되지 않아요.", cancel: "계속 말하기", confirm: "버리기")
        }
    }

    private func finish() {
        let text = speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        speech.failure = nil
        guard !text.isEmpty else {
            dismiss()
            return
        }
        switch route {
        case .new:
            let memo = Memo(title: "", body: text, isVoice: true)
            MemoTitler.fill(memo, in: context)
            context.insert(memo)
        case .append(let id):
            let descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
            if let memo = try? context.fetch(descriptor).first {
                memo.body = memo.body.isEmpty ? text : memo.body + "\n" + text
                memo.updatedAt = .now
            }
        }
        try? context.save()
        dismiss()
    }
}

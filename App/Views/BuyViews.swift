import SwiftData
import SwiftUI

struct BuyListView: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Query(sort: \BuyItem.createdAt) private var items: [BuyItem]
    @State private var showBought = false

    private var open: [BuyItem] { BuyRules.sortedOpen(items.filter { !$0.isBought }) }
    private var bought: [BuyItem] {
        items.filter(\.isBought).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TabHeader(title: "Buy") {
                    IconButton(symbol: "plus", label: "살 것 추가") { router.buyEdit = .new }
                }
                ScrollView {
                    LazyVStack(spacing: 12) { content }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, tabBarClearance + 76)
                }
            }
            RoundButton(symbol: "mic", label: "말하기") { router.startChatVoice() }
                .padding(.trailing, 16)
                .padding(.bottom, tabBarClearance)
        }
        .onAppear { try? BuyApplier.purge(in: context) }
    }

    @ViewBuilder private var content: some View {
        if open.isEmpty && bought.isEmpty {
            EmptyState(symbol: "bag", title: "살 것이 없어요", caption: "\"우유랑 계란 사야 해\"처럼 말해 보세요")
        }
        ForEach(open) { BuyRow(item: $0) }
        if !bought.isEmpty {
            Button { withAnimation(.snappy) { showBought.toggle() } } label: {
                HStack(spacing: 4) {
                    Text("산 것 \(bought.count)").font(.pBodyMedium)
                    Image(systemName: showBought ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Tone.ink2)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showBought { ForEach(bought) { BuyRow(item: $0) } }
        }
    }
}

struct BuyRow: View {
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    let item: BuyItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(isOn: item.isBought) {
                withAnimation(.snappy) { item.setBought(!item.isBought) }
                try? context.save()
            }
            .accessibilityLabel(item.isBought ? "\(item.name) 산 것 취소" : "\(item.name) 샀어요")
            Button { router.buyEdit = .existing(item.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.pTitle)
                        .strikethrough(item.isBought)
                        .foregroundStyle(item.isBought ? Tone.ink3 : Tone.ink)
                        .multilineTextAlignment(.leading)
                    let meta = BuyRules.meta(item)
                    if !meta.isEmpty {
                        HStack(spacing: 4) {
                            if !item.isBought { Image(systemName: "bag").font(.system(size: 11)) }
                            Text(meta).font(.pCaption)
                        }
                        .foregroundStyle(item.isBought ? Tone.ink3 : Tone.ink2)
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

// MARK: - 수정

enum BuyRoute: Identifiable, Equatable {
    case existing(UUID), new
    var id: String {
        switch self {
        case .existing(let id): id.uuidString
        case .new: "new"
        }
    }
}

struct BuyEditView: View {
    let route: BuyRoute

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var item: BuyItem?
    @State private var loaded = false
    @State private var name = ""
    @State private var quantity = ""
    @State private var store = ""
    @State private var due: Date?
    @State private var isBought = false
    @State private var pickingDue = false
    @State private var dialog: ConfirmDialog?
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { item == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SheetHeader(title: isNew ? "새 살 것" : "살 것 수정", onClose: { dismiss() }, onConfirm: save)
                HStack(spacing: 12) {
                    CheckCircle(isOn: isBought) { isBought.toggle() }
                    TextField("살 것을 입력하세요", text: $name).font(.pTitle).focused($nameFocused)
                }
                .card()
                VStack(spacing: 12) {
                    textRow("수량", text: $quantity)
                    FieldRow(label: "언제까지", value: due.map(Format.day) ?? "없음") { pickingDue = true }
                    textRow("어디서", text: $store)
                }
                .card()
                if !isNew {
                    HStack {
                        IconButton(symbol: "trash", label: "삭제") {
                            dialog = ConfirmDialog(title: "살 것을 삭제할까요?", message: "목록에서 바로 지워져요.", confirm: "삭제")
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
        .background(Tone.bg)
        .presentationCornerRadius(20)
        .onAppear(perform: load)
        .sheet(isPresented: $pickingDue) { BuyDueSheet(due: $due) }
        .confirmDialog($dialog) { _ in delete() }
    }

    private func textRow(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.pBody).foregroundStyle(Tone.ink)
            Spacer()
            TextField("없음", text: text)
                .font(.pBody)
                .foregroundStyle(Tone.ink2)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard case .existing(let id) = route else {
            nameFocused = true
            return
        }
        let descriptor = FetchDescriptor<BuyItem>(predicate: #Predicate { $0.id == id })
        guard let found = try? context.fetch(descriptor).first else { return }
        item = found
        name = found.name
        quantity = found.quantity ?? ""
        store = found.store ?? ""
        due = found.dueDate
        isBought = found.isBought
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameFocused = true
            return
        }
        let target = item ?? {
            let created = BuyItem(name: trimmed)
            context.insert(created)
            return created
        }()
        target.name = trimmed
        target.quantity = Self.optional(quantity)
        target.store = Self.optional(store)
        target.dueDate = due
        if target.isBought != isBought { target.setBought(isBought) }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let item {
            context.delete(item)
            try? context.save()
        }
        dismiss()
    }

    private static func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct BuyDueSheet: View {
    @Binding var due: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()

    var body: some View {
        VStack(spacing: 12) {
            SheetHeader(title: "언제까지", onClose: { dismiss() }) {
                due = Calendar.current.startOfDay(for: day)
                dismiss()
            }
            MonthCalendar(selection: $day).card()
            Button {
                due = nil
                dismiss()
            } label: {
                HStack {
                    Text("기한 없음").font(.pBody).foregroundStyle(Tone.ink)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .card(padding: 12)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Tone.bg)
        .presentationDetents([.height(520)])
        .presentationCornerRadius(20)
        .onAppear { day = due ?? .now }
    }
}

import SwiftUI

struct FloatShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}

extension View {
    func floatShadow() -> some View { modifier(FloatShadow()) }

    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct IconButton: View {
    let symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Tone.ink)
                .frame(width: 44, height: 44)
                .background(Tone.surface, in: Circle())
                .floatShadow()
        }
        .accessibilityLabel(label)
    }
}

struct RoundButton: View {
    let symbol: String
    var size: CGFloat = 56
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(Tone.onAccent)
                .frame(width: size, height: size)
                .background(Tone.ink, in: Circle())
                .floatShadow()
        }
        .accessibilityLabel(label)
    }
}

struct ActionButton: View {
    enum Kind { case primary, secondary, soft }
    let title: String
    var kind: Kind = .primary
    var symbol: String?
    var fullWidth = false
    var action: () -> Void

    private var foreground: Color { kind == .primary ? Tone.onAccent : Tone.ink }
    private var background: Color {
        switch kind {
        case .primary: Tone.ink
        case .secondary: Tone.surface
        case .soft: Tone.accentSoft
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .medium)) }
                Text(title).font(.pBodyMedium)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 46)
            .background(background, in: Capsule())
        }
    }
}

struct CheckCircle: View {
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) { CheckMark(isOn: isOn) }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .padding(-10)
            .accessibilityLabel(isOn ? "완료 취소" : "완료")
    }
}

struct CheckMark: View {
    let isOn: Bool
    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Tone.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tone.onAccent)
            } else {
                Circle().strokeBorder(Tone.line, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var soft = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
            Text(text).font(.pCaption)
        }
        .foregroundStyle(Tone.ink)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(soft ? Tone.accentSoft : Tone.bg, in: Capsule())
    }
}

struct TabHeader<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack {
            Text(title).font(.pDisplay).foregroundStyle(Tone.ink)
            Spacer()
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }
}

struct SheetHeader: View {
    let title: String
    var onClose: () -> Void
    var onConfirm: (() -> Void)?

    var body: some View {
        HStack {
            IconButton(symbol: "xmark", label: "닫기", action: onClose)
            Spacer()
            Text(title).font(.pTitle).foregroundStyle(Tone.ink)
            Spacer()
            if let onConfirm {
                RoundButton(symbol: "checkmark", size: 44, label: "확인", action: onConfirm)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Tone.ink2)
                .frame(width: 56, height: 56)
                .background(Tone.accentSoft, in: Circle())
            Text(title).font(.pTitle).foregroundStyle(Tone.ink)
            Text(caption).font(.pCaption).foregroundStyle(Tone.ink2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tone.ink3)
            TextField("검색", text: $text)
                .font(.pBody)
                .focused($focused)
                .submitLabel(.search)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Tone.surface, in: Capsule())
        .onAppear { focused = true }
    }
}

struct Banner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 15))
            Text("인터넷에 연결되어 있지 않아요").font(.pCaption)
            Spacer()
        }
        .foregroundStyle(Tone.ink)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Tone.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Waveform: View {
    var level: CGFloat
    var bars = 28
    var height: CGFloat = 18
    @State private var history: [CGFloat] = []

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let value = i < history.count ? history[i] : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < history.count ? Tone.ink : Tone.ink3)
                    .frame(width: 3, height: max(2, value * height))
            }
        }
        .frame(height: height)
        .onChange(of: level) { _, new in
            history.append(max(0.15, new))
            if history.count > bars { history.removeFirst(history.count - bars) }
        }
        .accessibilityHidden(true)
    }
}

struct ConfirmDialog: Equatable {
    var title: String
    var message: String
    var cancel = "취소"
    var confirm: String
    /// 두 번째 선택지. 있으면 버튼을 세로로 쌓는다.
    var secondary: String?
}

extension View {
    /// Figma ConfirmDialog. 시스템 알림 대신 가운데 카드로 띄운다.
    func confirmDialog(
        _ dialog: Binding<ConfirmDialog?>,
        onSecondary: ((ConfirmDialog) -> Void)? = nil,
        onConfirm: @escaping (ConfirmDialog) -> Void
    ) -> some View {
        overlay {
            if let current = dialog.wrappedValue {
                ZStack {
                    Tone.scrim.opacity(0.6).ignoresSafeArea()
                        .onTapGesture { dialog.wrappedValue = nil }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.title).font(.pTitle).foregroundStyle(Tone.ink)
                        Text(current.message).font(.pBody).foregroundStyle(Tone.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let secondary = current.secondary {
                            VStack(spacing: 8) {
                                ActionButton(title: current.confirm, fullWidth: true) {
                                    dialog.wrappedValue = nil
                                    onConfirm(current)
                                }
                                ActionButton(title: secondary, kind: .secondary, fullWidth: true) {
                                    dialog.wrappedValue = nil
                                    onSecondary?(current)
                                }
                                ActionButton(title: current.cancel, kind: .soft, fullWidth: true) { dialog.wrappedValue = nil }
                            }
                            .padding(.top, 12)
                        } else {
                            HStack(spacing: 8) {
                                ActionButton(title: current.cancel, kind: .soft, fullWidth: true) { dialog.wrappedValue = nil }
                                ActionButton(title: current.confirm, fullWidth: true) {
                                    dialog.wrappedValue = nil
                                    onConfirm(current)
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(20)
                    .background(Tone.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 32)
                    .accessibilityAddTraits(.isModal)
                }
            }
        }
    }
}

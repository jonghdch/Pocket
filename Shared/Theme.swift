import SwiftUI

/// Figma Tokens 컬렉션 값. 무채색만 쓴다.
enum Tone {
    static let bg = Color(hex: 0xF5F5F5)
    static let surface = Color.white
    static let ink = Color(hex: 0x111111)
    static let ink2 = Color(hex: 0x5E5E5E)
    static let ink3 = Color(hex: 0x767676)
    static let line = Color(hex: 0xE4E4E4)
    static let accentSoft = Color(hex: 0xE8E8E8)
    static let danger = Color(hex: 0x444444)
    static let onAccent = Color.white
    static let scrim = Color(hex: 0x3A3A3A)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Figma 글자 스타일. 크기를 고정하지 않고 Dynamic Type 을 따른다.
extension Font {
    static let pDisplay = Font.system(size: 28, weight: .bold)
    static let pHeadline = Font.system(size: 20, weight: .bold)
    static let pTitle = Font.system(size: 16, weight: .bold)
    static let pBody = Font.system(size: 15)
    static let pBodyMedium = Font.system(size: 15, weight: .medium)
    static let pCaption = Font.system(size: 13)
    static let pTab = Font.system(size: 11, weight: .medium)
}

enum DeepLink: Equatable {
    case voice, memo, newTodo, todo(UUID)

    init?(url: URL) {
        guard url.scheme == "pocket", let host = url.host else { return nil }
        switch host {
        case "voice": self = .voice
        case "memo": self = .memo
        case "new": self = .newTodo
        case "todo":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .todo(id)
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .voice: URL(string: "pocket://voice")!
        case .memo: URL(string: "pocket://memo")!
        case .newTodo: URL(string: "pocket://new")!
        case .todo(let id): URL(string: "pocket://todo/\(id.uuidString)")!
        }
    }
}

enum Format {
    static let locale = Locale(identifier: "ko_KR")

    private static func string(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = template
        return f.string(from: date)
    }

    static func day(_ date: Date) -> String { string(date, "M월 d일 (E)") }
    static func monthDay(_ date: Date) -> String { string(date, "M월 d일") }
    static func dayTitle(_ date: Date) -> String { string(date, "M월 d일 EEEE") }
    static func month(_ date: Date) -> String { string(date, "yyyy년 M월") }
    static func clock(_ date: Date) -> String { string(date, "a h:mm") }
    static func clock24(_ date: Date) -> String { string(date, "HH:mm") }
    static func weekday(_ date: Date) -> String { string(date, "E") }

    static func range(_ start: Date, _ end: Date?) -> String {
        guard let end else { return clock(start) }
        return "\(clock(start)) ~ \(clock(end))"
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m)분"
        case (_, 0): return "\(h)시간"
        default: return "\(h)시간 \(m)분"
        }
    }

    static func timer(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, r)
            : String(format: "%02d:%02d", m, r)
    }
}

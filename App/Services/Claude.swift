import Foundation
import Security

/// API 키는 파일이 아니라 키체인에만 둔다.
enum KeychainStore {
    private static let account = "claude-api-key"
    private static let service = "com.jonghdch.pocket"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var apiKey: String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// 키는 키체인이 먼저다. 개발 빌드에서만 키체인이 비어 있을 때 환경 변수 ANTHROPIC_API_KEY 를 쓴다.
/// 환경 변수는 scripts/run-sim.sh 가 시뮬레이터에 넘긴다. 키 값은 저장소에 두지 않는다.
enum APIKeySource {
    static let environmentKey = "ANTHROPIC_API_KEY"

    static func resolve(keychain: String?, environment: [String: String]) -> String? {
        if let keychain, !keychain.isEmpty { return keychain }
        let value = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static var current: String? {
        #if DEBUG
        return resolve(keychain: KeychainStore.apiKey, environment: ProcessInfo.processInfo.environment)
        #else
        return KeychainStore.apiKey
        #endif
    }
}

enum AIError: Error, Equatable {
    case noKey, invalidKey, offline, server(Int), badResponse

    var message: String {
        switch self {
        case .noKey: "설정에서 Claude API 키를 넣어 주세요."
        case .invalidKey: "API 키가 맞지 않아요. 설정에서 확인해 주세요."
        case .offline: "인터넷에 연결되어 있지 않아요."
        case .server(429): "요청이 많아요. 잠시 뒤 다시 시도해 주세요."
        case .server: "말한 내용은 그대로 있어요. 다시 시도해 주세요."
        case .badResponse: "말한 내용은 그대로 있어요. 다시 시도해 주세요."
        }
    }
}

struct ClaudeClient {
    static let model = "claude-sonnet-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var session: URLSession = .shared
    var key: () -> String? = { APIKeySource.current }

    /// 도구 호출을 강제해 항상 같은 모양의 JSON 을 받는다.
    func callTool(system: String, user: String, tool: [String: Any], maxTokens: Int = 1500) async throws -> Data {
        guard let apiKey = key(), !apiKey.isEmpty else { throw AIError.noKey }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let name = tool["name"] as? String ?? ""
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": name],
            "messages": [["role": "user", "content": user]],
        ] as [String: Any])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw AIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 401 else { throw AIError.invalidKey }
        guard (200..<300).contains(status) else { throw AIError.server(status) }
        return try Self.toolInput(from: data)
    }

    static func toolInput(from data: Data) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]],
              let block = content.first(where: { $0["type"] as? String == "tool_use" }),
              let input = block["input"] else { throw AIError.badResponse }
        return try JSONSerialization.data(withJSONObject: input)
    }

    // MARK: - 정리

    static let planTool: [String: Any] = [
        "name": "apply_plan",
        "description": "사용자의 말을 처리한 결과를 돌려준다.",
        "input_schema": [
            "type": "object",
            "required": ["reply"],
            "properties": [
                "reply": ["type": "string", "description": "사용자에게 보여 줄 짧은 한국어 답. 해요체."],
                "create": ["type": "array", "items": [
                    "type": "object", "required": ["title"],
                    "properties": [
                        "title": ["type": "string"],
                        "date": ["type": "string", "description": "YYYY-MM-DD. 말에 날짜가 없으면 생략."],
                        "start_time": ["type": "string", "description": "HH:mm 24시간. 말에 시간이 없으면 생략."],
                        "end_time": ["type": "string", "description": "HH:mm 24시간."],
                        "estimate_minutes": ["type": "integer"],
                    ],
                ]],
                "update": ["type": "array", "items": [
                    "type": "object", "required": ["id"],
                    "properties": [
                        "id": ["type": "string"],
                        "title": ["type": "string"],
                        "date": ["type": "string"],
                        "start_time": ["type": "string"],
                        "end_time": ["type": "string"],
                        "done": ["type": "boolean"],
                    ],
                ]],
                "repeats": ["type": "array", "description": "기간 동안 같은 일을 반복할 때. 사용자가 확인한 뒤 저장된다.", "items": [
                    "type": "object", "required": ["title", "from", "to"],
                    "properties": [
                        "title": ["type": "string"],
                        "from": ["type": "string", "description": "YYYY-MM-DD. 첫날."],
                        "to": ["type": "string", "description": "YYYY-MM-DD. 마지막 날 (포함)."],
                        "weekdays": ["type": "array", "items": ["type": "integer"], "description": "1=월 … 7=일. 매일이면 생략."],
                        "start_time": ["type": "string"],
                        "end_time": ["type": "string"],
                        "estimate_minutes": ["type": "integer"],
                    ],
                ]],
                "buys": ["type": "array", "description": "살 물건. 사용자가 확인한 뒤 Buy 목록에 저장된다.", "items": [
                    "type": "object", "required": ["name"],
                    "properties": [
                        "name": ["type": "string", "description": "물건 이름만. 예: 우유"],
                        "quantity": ["type": "string", "description": "말한 그대로의 수량. 예: 2개, 1L, 두 판"],
                        "due_date": ["type": "string", "description": "YYYY-MM-DD. 언제까지 사야 하는지."],
                        "store": ["type": "string", "description": "어디서 살지. 예: 다이소"],
                    ],
                ]],
                "spreads": ["type": "array", "description": "목표를 기간 안에 날짜별로 나눌 때. 사용자가 확인한 뒤 저장된다.", "items": [
                    "type": "object", "required": ["title", "days"],
                    "properties": [
                        "title": ["type": "string", "description": "목표 이름."],
                        "days": ["type": "array", "items": [
                            "type": "object", "required": ["date", "title"],
                            "properties": [
                                "date": ["type": "string", "description": "YYYY-MM-DD"],
                                "title": ["type": "string"],
                                "start_time": ["type": "string"],
                                "end_time": ["type": "string"],
                                "estimate_minutes": ["type": "integer"],
                            ],
                        ]],
                    ],
                ]],
            ],
        ] as [String: Any],
    ]

    static func planSystem(now: Date, todos: String) -> String {
        let f = DateFormatter()
        f.locale = Format.locale
        f.dateFormat = "yyyy-MM-dd (EEEE) HH:mm"
        return """
        너는 할 일 앱 POCKET 의 비서다. 사용자의 말을 듣고 apply_plan 을 호출한다.
        지금 시각: \(f.string(from: now))
        규칙:
        - 할 일과 일정은 같은 것이다. 말에 날짜와 시간이 있으면 넣고, 없으면 지어내지 않는다.
        - 한 번에 여러 건을 말하면 나눠서 create 에 넣는다.
        - 이미 있는 항목을 고치거나 끝냈다고 하면 아래 목록의 id 로 update 한다. 어느 항목인지 불분명하면 고치지 말고 reply 로 되묻는다.
        - "이번 달 말까지 매일", "2주 동안 평일마다"처럼 기간 동안 같은 일을 하면 create 가 아니라 repeats 에 넣는다. 시작일이 없으면 오늘부터. 끝나는 날이 없으면 지어내지 말고 reply 로 언제까지인지 묻는다.
        - 목표를 기간 안에 나눠 달라고 하면 spreads 에 날짜마다 다른, 바로 할 수 있는 할 일을 넣는다. 하루에 여럿이면 같은 날짜로 여러 줄. 기간 밖의 날짜는 쓰지 않는다.
        - repeats 와 spreads 는 최대 90일이다. 사용자가 확인하고 저장하므로 reply 에서 확인해 달라고 말한다.
        - "우유랑 계란 사야 해", "세제 사 와야지"처럼 살 물건을 말하면 create 가 아니라 buys 에 물건마다 한 줄씩 넣는다. 수량·기한·살 곳은 말에 있을 때만 넣는다. 사용자가 확인하고 저장하므로 reply 에서 확인해 달라고 말한다.
        - 질문이면 create 와 update 없이 reply 로만 답한다.
        현재 항목:
        \(todos.isEmpty ? "(없음)" : todos)
        """
    }

    func plan(text: String, todos: String, now: Date = .now) async throws -> AIPlan {
        let data = try await callTool(
            system: Self.planSystem(now: now, todos: todos), user: text, tool: Self.planTool, maxTokens: 4000)
        do {
            return try JSONDecoder().decode(AIPlan.self, from: data)
        } catch {
            throw AIError.badResponse
        }
    }

    // MARK: - 나누기

    func breakDown(title: String, existing: [String]) async throws -> [String] {
        let tool: [String: Any] = [
            "name": "suggest_steps",
            "description": "할 일을 바로 시작할 수 있는 작은 단계로 나눈다.",
            "input_schema": [
                "type": "object", "required": ["steps"],
                "properties": ["steps": ["type": "array", "items": ["type": "string"]]],
            ] as [String: Any],
        ]
        let context = existing.isEmpty ? "" : "\n이미 있는 단계: " + existing.joined(separator: ", ")
        let data = try await callTool(
            system: "할 일을 3~6개의 짧고 구체적인 한국어 단계로 나눈다. 각 단계는 동사로 끝낸다.",
            user: "할 일: \(title)\(context)", tool: tool, maxTokens: 600)
        struct Steps: Decodable { var steps: [String] }
        guard let steps = try? JSONDecoder().decode(Steps.self, from: data), !steps.steps.isEmpty else {
            throw AIError.badResponse
        }
        return steps.steps
    }

    // MARK: - 메모 제목

    func memoTitle(body: String) async throws -> String {
        let tool: [String: Any] = [
            "name": "set_title",
            "description": "메모 제목을 정한다.",
            "input_schema": [
                "type": "object", "required": ["title"],
                "properties": ["title": ["type": "string"]],
            ] as [String: Any],
        ]
        let data = try await callTool(
            system: "메모 내용을 보고 15자 안쪽의 한국어 제목을 짓는다. 문장부호 없이 명사형으로 끝낸다.",
            user: body, tool: tool, maxTokens: 100)
        struct Title: Decodable { var title: String }
        guard let title = try? JSONDecoder().decode(Title.self, from: data), !title.title.isEmpty else {
            throw AIError.badResponse
        }
        return title.title
    }
}

import Foundation

enum HHAPIError: LocalizedError, Equatable {
    case invalidURL, invalidResponse, missingApplicationToken, placeholderApplicationToken, unauthorized
    case forbidden(requestID: String?)
    case rateLimited(retryAfterSeconds: Int?)
    case captchaRequired(requestID: String?)
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Не удалось сформировать URL запроса hh.ru."
        case .invalidResponse: return "hh.ru вернул неожиданный ответ."
        case .missingApplicationToken, .placeholderApplicationToken:
            return "Токен авторизации hh.ru не настроен. Укажите application token в HHAuthConfig.swift."
        case .unauthorized: return "hh.ru отклонил токен авторизации."
        case .forbidden(let id): return Self.withID("hh.ru отклонил запрос: 403 forbidden.", id)
        case .rateLimited(let seconds):
            return seconds.map { "hh.ru ограничил частоту запросов. Повторите через \($0) секунд." }
                ?? "hh.ru ограничил частоту запросов. Попробуйте позже."
        case .captchaRequired(let id): return Self.withID("hh.ru запросил CAPTCHA. Пройдите проверку и повторите позже.", id)
        case .requestFailed(let code, _): return "hh.ru вернул ошибку \(code)."
        }
    }

    var isNotFound: Bool {
        if case .requestFailed(statusCode: 404, message: _) = self { return true }
        return false
    }

    private static func withID(_ message: String, _ id: String?) -> String {
        guard let id = id?.nilIfBlank else { return message }
        return "\(message)\nRequest ID: \(id)"
    }
}

struct HHVacancySearchRequest: Equatable, Sendable {
    let employerID: String
    let areaID: String
    let page: Int
    let perPage: Int
    let dateFrom: Date?
    let dateTo: Date?
    let experience: String?
    let workFormat: String?
    let schedule: String?

    init(
        employerID: String,
        areaID: String = "113",
        page: Int = 0,
        perPage: Int = 100,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        experience: String? = nil,
        workFormat: String? = nil,
        schedule: String? = nil
    ) {
        self.employerID = employerID
        self.areaID = areaID
        self.page = page
        self.perPage = perPage
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.experience = experience
        self.workFormat = workFormat
        self.schedule = schedule
    }
}

protocol HHVacancyAPIClient: Sendable {
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse
    func vacancyDetails(id: String) async throws -> HHVacancyDetails
    func areaTree() async throws -> HHAreaNode
    func vacancyDictionaries() async throws -> HHVacancyDictionaries
    func validateVacanciesAccess() throws
}

struct HHAPIClient: HHVacancyAPIClient, Sendable {
    private static let baseURL = URL(string: "https://api.hh.ru")!
    private static let contact = "sergeyssimonov-max@users.noreply.github.com"
    private let session: URLSession
    private let accessTokenProvider: HHAccessTokenProviding
    private let requestGate: HHRequestGate
    private let maximumRateLimitRetries: Int
    private let retrySleep: @Sendable (UInt64) async throws -> Void
    private let retryNow: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        accessTokenProvider: HHAccessTokenProviding = HHDefaultAccessTokenProvider(),
        requestGate: HHRequestGate = .shared,
        maximumRateLimitRetries: Int = 2,
        retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        retryNow: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.accessTokenProvider = accessTokenProvider
        self.requestGate = requestGate
        self.maximumRateLimitRetries = min(2, max(0, maximumRateLimitRetries))
        self.retrySleep = retrySleep
        self.retryNow = retryNow
    }

    func searchVacancies(_ search: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        try validateVacanciesAccess()
        guard (1...100).contains(search.perPage), search.page >= 0, search.page * search.perPage < 2_000 else {
            throw HHAPIError.invalidURL
        }
        var items = [
            URLQueryItem(name: "employer_id", value: search.employerID),
            URLQueryItem(name: "area", value: search.areaID),
            URLQueryItem(name: "page", value: String(search.page)),
            URLQueryItem(name: "per_page", value: String(search.perPage))
        ]
        let formatter = ISO8601DateFormatter()
        if let value = search.dateFrom { items.append(.init(name: "date_from", value: formatter.string(from: value))) }
        if let value = search.dateTo { items.append(.init(name: "date_to", value: formatter.string(from: value))) }
        if let value = search.experience { items.append(.init(name: "experience", value: value)) }
        if let value = search.workFormat { items.append(.init(name: "work_format", value: value)) }
        if let value = search.schedule { items.append(.init(name: "schedule", value: value)) }
        return try await get(path: "vacancies", queryItems: items, as: HHVacancySearchResponse.self)
    }

    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        try validateVacanciesAccess()
        return try await get(path: "vacancies/\(id)", queryItems: [], as: HHVacancyDetails.self)
    }

    func areaTree() async throws -> HHAreaNode {
        try validateVacanciesAccess()
        let roots = try await get(path: "areas", queryItems: [], as: [HHAreaNode].self)
        guard let russia = roots.first(where: { $0.id == "113" }) else { throw AreaDirectoryError.invalidRoot }
        return russia
    }

    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        try validateVacanciesAccess()
        return try await get(path: "dictionaries", queryItems: [], as: HHVacancyDictionaries.self)
    }

    func validateVacanciesAccess() throws {
        guard let raw = accessTokenProvider.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw HHAPIError.missingApplicationToken
        }
        guard raw != HHAuthConfig.placeholderAccessToken else { throw HHAPIError.placeholderApplicationToken }
    }

    private func get<T: Decodable & Sendable>(path: String, queryItems: [URLQueryItem], as type: T.Type) async throws -> T {
        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw HHAPIError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw HHAPIError.invalidURL }
        let responseData = try await data(for: makeRequest(url: url))
        return try JSONDecoder().decode(type, from: responseData)
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let agent = "HHVacancySber/1.0 (\(Self.contact))"
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue(agent, forHTTPHeaderField: "HH-User-Agent")
        if let token = HHAuthConfig.normalizedAccessToken(accessTokenProvider.accessToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // A server delay above the automatic-wait ceiling stops the operation;
    // clamping it and retrying early would disregard Retry-After.
    static func rateLimitDelay(header: String?, now: Date, attempt: Int) -> TimeInterval? {
        let backoff = attempt == 0 ? 1.0 : 2.0
        guard let header else { return backoff }
        let value = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds: TimeInterval?
        if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            seconds = Double(value)
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            formatter.isLenient = false
            seconds = formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
        }
        guard let seconds else { return backoff }
        guard seconds.isFinite, seconds <= 60 else { return nil }
        return max(backoff, seconds)
    }

    private func data(for request: URLRequest) async throws -> Data {
        try await requestGate.perform {
            var retryCount = 0
            while true {
                try Task.checkCancellation()
                let data: Data
                let response: URLResponse
                do { (data, response) = try await session.data(for: request) }
                catch let error as URLError where error.code == .cancelled { throw CancellationError() }
                guard let http = response as? HTTPURLResponse else { throw HHAPIError.invalidResponse }
                if (200...299).contains(http.statusCode) { return data }
                let body = try? JSONDecoder().decode(HHErrorResponse.self, from: data)
                if body?.isCaptchaRequired == true { throw HHAPIError.captchaRequired(requestID: body?.requestID) }
                switch http.statusCode {
                case 401: throw HHAPIError.unauthorized
                case 403: throw HHAPIError.forbidden(requestID: body?.requestID)
                case 429:
                    let header = http.value(forHTTPHeaderField: "Retry-After")
                    guard retryCount < maximumRateLimitRetries,
                          let delay = Self.rateLimitDelay(header: header, now: retryNow(), attempt: retryCount) else {
                        throw HHAPIError.rateLimited(retryAfterSeconds: header.flatMap(Int.init))
                    }
                    retryCount += 1
                    // Keep the shared gate while waiting: queued work cannot overtake a retry.
                    try await retrySleep(UInt64(delay * 1_000_000_000))
                default: throw HHAPIError.requestFailed(statusCode: http.statusCode, message: body?.description)
                }
            }
        }
    }

}

actor HHRequestGate {
    static let shared = HHRequestGate()
    static let defaultMinimumDelayNanoseconds: UInt64 = 250_000_000
    private let delay: UInt64
    private var lastFinishedAt: UInt64?
    private var isPerforming = false
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []
    var queuedRequestCount: Int { waiters.count }

    init(minimumDelayNanoseconds: UInt64 = defaultMinimumDelayNanoseconds) { delay = minimumDelayNanoseconds }

    func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer {
            lastFinishedAt = DispatchTime.now().uptimeNanoseconds
            release()
        }
        try Task.checkCancellation()
        if let lastFinishedAt {
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = now > lastFinishedAt ? now - lastFinishedAt : 0
            if elapsed < delay { try await Task.sleep(nanoseconds: delay - elapsed) }
        }
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard isPerforming else {
            isPerforming = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Covers cancellation before the handler was installed/enqueued.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        guard !waiters.isEmpty else {
            isPerforming = false
            return
        }
        waiters.removeFirst().continuation.resume()
    }
}

private struct HHErrorResponse: Decodable {
    struct Item: Decodable { let type: String?; let value: String? }
    let description: String?
    let requestID: String?
    let errors: [Item]
    enum CodingKeys: String, CodingKey { case description, errors; case requestID = "request_id" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        requestID = try values.decodeIfPresent(String.self, forKey: .requestID)
        errors = try values.decodeIfPresent([Item].self, forKey: .errors) ?? []
    }
    var isCaptchaRequired: Bool {
        description?.localizedCaseInsensitiveContains("captcha") == true || errors.contains {
            $0.type?.localizedCaseInsensitiveContains("captcha") == true || $0.value?.localizedCaseInsensitiveContains("captcha") == true
        }
    }
}

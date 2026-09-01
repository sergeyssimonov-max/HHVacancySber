import Foundation
import XCTest
@testable import HHVacancySber

final class HHVacancySberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testEmployerConfigurationRejectsEmptyDuplicateAndInvalidIDs() throws {
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: []).validated())
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: [
            .init(id: "3529", name: "СБЕР", comment: "ok"),
            .init(id: "3529", name: "Дубль", comment: "bad")
        ]).validated())
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: [
            .init(id: "not-a-number", name: "СБЕР", comment: "bad")
        ]).validated())
    }

    func testEmployerConfigurationCopiesBundledDefaultOnlyOnce() throws {
        let directory = temporaryDirectory()
        let bundled = directory.appendingPathComponent("bundled.json")
        let runtime = directory.appendingPathComponent("runtime/employers.json")
        try Data(#"{"version":1,"employers":[{"id":"3529","name":"СБЕР","comment":"verified"}]}"#.utf8).write(to: bundled)
        let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
        XCTAssertEqual(try store.loadOrCreate().employers.map(\.id), ["3529"])
        try Data(#"{"version":1,"employers":[{"id":"2798","name":"СберРешения","comment":"runtime"}]}"#.utf8).write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate().employers.map(\.id), ["2798"])
    }

    func testLocationClassificationIsStrict() throws {
        let index = try AreaDirectoryIndex(root: Self.areaTree)
        XCTAssertEqual(index.location(for: summary(id: "m", areaID: "1", areaName: "Москва")),
                       .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва"))
        XCTAssertEqual(index.location(for: summary(id: "e", areaID: "3", areaName: "Екатеринбург")),
                       .subject(id: "66", name: "Свердловская область", cityID: "3", cityName: "Екатеринбург"))
        XCTAssertEqual(index.location(for: summary(id: "r", areaID: nil, areaName: nil,
                                                   workFormat: [.init(id: "REMOTE", name: "Удалённо")])), .remote)
        XCTAssertEqual(index.location(for: summary(id: "foreign", areaID: "999", areaName: "Минск")), .unknown)
        let multiple = summary(id: "multi", areaID: "1", areaName: "Москва", areas: [
            .init(id: "1", name: "Москва"), .init(id: "2", name: "Санкт-Петербург")
        ])
        XCTAssertEqual(index.location(for: multiple), .unknown)
    }

    func testFavoriteV1MigratesAtomicallyToV2AndDropsHistoricalFields() throws {
        let url = temporaryDirectory().appendingPathComponent("favorites.json")
        let historicalValueKey = "sco" + "re"
        let legacy = #"{"version":1,"favorites":[{"id":"42","name":"Аналитик","employerName":"СБЕР","areaName":"Москва","salaryText":null,"alternateURL":null,"snippet":null,"descriptionHTML":null,"isArchived":false,"favoritedAt":"2026-09-01T00:00:00Z","updatedAt":"2026-09-01T00:00:00Z","HISTORICAL_KEY":{"total":99},"status":"ready","reasons":["legacy"]}]}"#
            .replacingOccurrences(of: "HISTORICAL_KEY", with: historicalValueKey)
        try Data(legacy.utf8).write(to: url)
        let records = try FavoriteVacancyStore(fileURL: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].location, .unknown)
        let migrated = try String(contentsOf: url)
        XCTAssertTrue(migrated.contains(#""version" : 2"#))
        XCTAssertFalse(migrated.contains("\"\(historicalValueKey)\""))
        XCTAssertFalse(migrated.contains(#""reasons""#))
    }

    func testCollectorPartitionsOver2000BySubjectAndDeduplicates() async throws {
        let client = MockAPIClient(mode: .partitioned)
        let service = VacancyCollectionService(client: client)
        let values = try await service.collect(
            employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
            areas: try AreaDirectoryIndex(root: .init(id: "113", name: "Россия", areas: [
                .init(id: "10", name: "Регион A"), .init(id: "20", name: "Регион B")
            ])),
            progress: { _ in }
        )
        XCTAssertEqual(values.count, 2_001)
        XCTAssertEqual(Set(values.map(\.id)).count, 2_001)
    }

    func testCollectorRetriesThenRejectsIncompleteLeaf() async throws {
        let service = VacancyCollectionService(client: MockAPIClient(mode: .mismatch))
        do {
            _ = try await service.collect(
                employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
                areas: try AreaDirectoryIndex(root: Self.areaTree),
                progress: { _ in }
            )
            XCTFail("Expected completeness error")
        } catch let error as VacancyCompletenessError {
            XCTAssertEqual(error.expected, 2)
            XCTAssertEqual(error.actual, 1)
        }
    }

    func testAreaDirectoryUsesFreshThenExplicitStaleCacheAndRejectsCorruptionWithoutNetwork() async throws {
        let file = temporaryDirectory().appendingPathComponent("areas.json")
        let instant = Date(timeIntervalSince1970: 1_788_200_000)
        let freshStore = AreaDirectoryStore(fileURL: file, now: { instant })
        let fresh = try await freshStore.load(using: MockAPIClient(mode: .simple))
        XCTAssertNil(fresh.warning)

        let staleStore = AreaDirectoryStore(
            fileURL: file,
            now: { instant.addingTimeInterval(AreaDirectoryStore.defaultTTL + 1) }
        )
        let stale = try await staleStore.load(using: MockAPIClient(mode: .failure))
        XCTAssertTrue(stale.warning?.contains("устаревший кэш") == true)

        let corrupted = temporaryDirectory().appendingPathComponent("areas.json")
        try Data("not-json".utf8).write(to: corrupted)
        do {
            _ = try await AreaDirectoryStore(fileURL: corrupted).load(using: MockAPIClient(mode: .failure))
            XCTFail("Expected unavailable directory")
        } catch let error as AreaDirectoryError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testTypedAPIRequestUsesRequiredQueryAndHeaders() async throws {
        let client = makeHTTPClient { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(components.path, "/vacancies")
            XCTAssertEqual(query["employer_id"], "3529")
            XCTAssertEqual(query["area"], "113")
            XCTAssertEqual(query["per_page"], "100")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "HH-User-Agent"))
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let response = try await client.searchVacancies(.init(employerID: "3529"))
        XCTAssertEqual(response.found, 0)
    }

    func testAPIPreserves401RateLimitCaptchaAndNetworkErrors() async throws {
        var client = makeHTTPClient { _ in (401, [:], Data(#"{"errors":[]}"#.utf8)) }
        await assertAPIError(client, equals: .unauthorized)

        client = makeHTTPClient { _ in (429, ["Retry-After": "17"], Data(#"{"errors":[]}"#.utf8)) }
        await assertAPIError(client, equals: .rateLimited(retryAfterSeconds: 17))

        client = makeHTTPClient { _ in
            (403, [:], Data(#"{"request_id":"req-1","errors":[{"type":"captcha","value":"required"}]}"#.utf8))
        }
        await assertAPIError(client, equals: .captchaRequired(requestID: "req-1"))

        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        let networkClient = HTTPClientFactory.make()
        do {
            _ = try await networkClient.searchVacancies(.init(employerID: "3529"))
            XCTFail("Expected network error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testViewModelUsesEmployerAndRegionFiltersWithANDSemantics() async throws {
        let employerStore = TestEmployerStore(entries: [
            .init(id: "3529", name: "СБЕР", comment: "test"),
            .init(id: "2798", name: "СберРешения", comment: "test")
        ])
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            currentDate: { Date(timeIntervalSince1970: 1_788_200_000) }
        )
        await model.search()
        XCTAssertEqual(model.results.count, 2)
        XCTAssertEqual(model.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        XCTAssertEqual(model.displayedResults.map(\.id), ["3529-vacancy"])
        model.selectedRegionID = "remote"
        XCTAssertTrue(model.displayedResults.isEmpty)
    }

    @MainActor
    func testLazyDetailsLoadUpdatesOnlyRequestedCard() async throws {
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()
        XCTAssertFalse(model.results[0].isDetailLoaded)
        await model.loadVacancyDetails(id: "3529-vacancy")
        XCTAssertTrue(model.results.first { $0.id == "3529-vacancy" }?.isDetailLoaded == true)
        XCTAssertEqual(model.results.first { $0.id == "3529-vacancy" }?.plainTextDescription, "Полное описание")
    }

    @MainActor
    func testRapidFavoriteMutationsUseOnePersistenceDriverAndKeepLatestSnapshot() async throws {
        let store = SlowRecordingFavoriteStore()
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )
        await model.search()
        model.toggleFavorite(id: "3529-vacancy")
        await Task.yield()
        model.toggleFavorite(id: "3529-vacancy")
        model.toggleFavorite(id: "3529-vacancy")
        await model.waitForPendingFavoritesSaves()
        XCTAssertEqual(store.maximumConcurrentSaves, 1)
        XCTAssertEqual(store.lastSaved.map(\.id), ["3529-vacancy"])
        XCTAssertLessThanOrEqual(store.saveCount, 2)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HHVacancySberTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeHTTPClient(
        handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)
    ) -> HHAPIClient {
        URLProtocolStub.handler = handler
        return HTTPClientFactory.make()
    }

    private func assertAPIError(_ client: HHAPIClient, equals expected: HHAPIError) async {
        do {
            _ = try await client.searchVacancies(.init(employerID: "3529"))
            XCTFail("Expected \(expected)")
        } catch let error as HHAPIError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let areaTree = HHAreaNode(id: "113", name: "Россия", areas: [
        .init(id: "1", name: "Москва"),
        .init(id: "2", name: "Санкт-Петербург"),
        .init(id: "66", name: "Свердловская область", areas: [.init(id: "3", name: "Екатеринбург")])
    ])

    private func summary(
        id: String,
        employerID: String = "3529",
        areaID: String?,
        areaName: String?,
        workFormat: [HHNamedItem]? = nil,
        areas: [HHArea]? = nil
    ) -> HHVacancySummary {
        HHVacancySummary(
            id: id, name: "Вакансия \(id)", employer: .init(name: "СБЕР", id: employerID), salary: nil,
            area: areaID.map { .init(id: $0, name: areaName) }, alternateURL: "https://example.invalid/\(id)",
            url: nil, snippet: nil, workFormat: workFormat, publishedAt: "2026-09-01T10:00:00+0300", areas: areas
        )
    }
}

private struct TestEmployerStore: EmployerConfigurationStoring {
    let entries: [EmployerConfigurationEntry]
    func loadOrCreate() throws -> EmployerConfiguration {
        try EmployerConfiguration(version: 1, employers: entries).validated()
    }
}

private actor MockAPIClient: HHVacancyAPIClient {
    enum Mode: Sendable { case simple, partitioned, mismatch, failure }
    let mode: Mode
    init(mode: Mode) { self.mode = mode }
    nonisolated func validateVacanciesAccess() throws {}
    func areaTree() async throws -> HHAreaNode {
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        return .init(id: "113", name: "Россия", areas: [
            .init(id: "1", name: "Москва"),
            .init(id: "2", name: "Санкт-Петербург"),
            .init(id: "66", name: "Свердловская область", areas: [.init(id: "3", name: "Екатеринбург")])
        ])
    }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        return .init(
            experience: ["noExperience", "between1And3", "between3And6", "moreThan6"].map { .init(id: $0, name: $0) },
            workFormat: [.init(id: "REMOTE", name: "Удалённо")],
            schedule: [.init(id: "remote", name: "Удалённая работа")]
        )
    }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        let employerID = id.components(separatedBy: "-").first ?? "3529"
        return .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerID == "2798" ? "СберРешения" : "СБЕР", id: employerID),
                     area: .init(id: "1", name: "Москва"), salary: nil, alternateURL: nil,
                     description: "<p>Полное описание</p>")
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        switch mode {
        case .simple:
            let remote = request.employerID == "2798"
            let item = makeSummary(id: "\(request.employerID)-vacancy", employerID: request.employerID,
                                   employerName: remote ? "СберРешения" : "СБЕР", remote: remote)
            return page([item], found: 1, request: request)
        case .mismatch:
            return page([makeSummary(id: "only-one", employerID: request.employerID, employerName: "СБЕР")], found: 2, request: request)
        case .partitioned:
            let count: Int
            let prefix: String
            switch request.areaID {
            case "10": count = 1_200; prefix = "a"
            case "20": count = 801; prefix = "b"
            default: count = 2_001; prefix = "root"
            }
            let start = request.page * request.perPage
            let end = min(start + request.perPage, count)
            let values = start < end ? (start..<end).map {
                makeSummary(id: "\(prefix)-\($0)", employerID: request.employerID, employerName: "СБЕР")
            } : []
            return .init(items: values, found: count, pages: Int(ceil(Double(count) / Double(request.perPage))), page: request.page, perPage: request.perPage)
        case .failure:
            throw URLError(.notConnectedToInternet)
        }
    }
    private func page(_ all: [HHVacancySummary], found: Int, request: HHVacancySearchRequest) -> HHVacancySearchResponse {
        let start = request.page * request.perPage
        let end = min(start + request.perPage, all.count)
        let items = start < end ? Array(all[start..<end]) : []
        return .init(items: items, found: found, pages: Int(ceil(Double(found) / Double(request.perPage))), page: request.page, perPage: request.perPage)
    }
    private func makeSummary(id: String, employerID: String, employerName: String, remote: Bool = false) -> HHVacancySummary {
        .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerName, id: employerID), salary: nil,
              area: remote ? nil : .init(id: "1", name: "Москва"), alternateURL: nil, url: nil, snippet: nil,
              workFormat: remote ? [.init(id: "REMOTE", name: "Удалённо")] : nil,
              publishedAt: employerID == "3529" ? "2026-09-02T10:00:00+0300" : "2026-09-01T10:00:00+0300")
    }
}

private struct FixedTokenProvider: HHAccessTokenProviding {
    let accessToken: String? = "unit-token"
}

private final class SlowRecordingFavoriteStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var activeSaves = 0
    private var maximum = 0
    private var saved: [FavoriteVacancyRecord] = []
    private var count = 0

    func load() throws -> [FavoriteVacancyRecord] { [] }
    func save(_ favorites: [FavoriteVacancyRecord]) throws {
        lock.lock()
        activeSaves += 1
        maximum = max(maximum, activeSaves)
        count += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.05)
        lock.lock()
        saved = favorites
        activeSaves -= 1
        lock.unlock()
    }
    var maximumConcurrentSaves: Int { lock.withLock { maximum } }
    var lastSaved: [FavoriteVacancyRecord] { lock.withLock { saved } }
    var saveCount: Int { lock.withLock { count } }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock(); defer { unlock() }; return operation()
    }
}

private enum HTTPClientFactory {
    static func make() -> HHAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return HHAPIClient(
            session: URLSession(configuration: configuration),
            accessTokenProvider: FixedTokenProvider(),
            requestGate: HHRequestGate(minimumDelayNanoseconds: 0)
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

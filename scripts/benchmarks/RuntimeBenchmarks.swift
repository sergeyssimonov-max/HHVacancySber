import AppKit
import Darwin
import Foundation
import PDFKit

// Compile with the production sources, never with the app entry point. No live API calls.
@main
struct RuntimeBenchmarks {
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "pdf"
        let count = Int(CommandLine.arguments.dropFirst(2).first ?? "100") ?? 100
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HHRuntimeBench-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let values = (0..<count).map { vacancy($0, paragraphs: mode == "stress" ? 1200 : 12) }
        let start = ProcessInfo.processInfo.systemUptime
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        var result: [String: Any] = ["mode": mode, "vacancies": count]
        if mode == "gate" {
            let gate = HHRequestGate(minimumDelayNanoseconds: 0)
            let entered = Signal()
            let active = Task {
                try await gate.perform {
                    await entered.signal()
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            await entered.wait()
            let queued = Task { try await gate.perform { 42 } }
            try await Task.sleep(nanoseconds: 30_000_000)
            let cancellationStart = ProcessInfo.processInfo.systemUptime
            queued.cancel()
            _ = await queued.result
            result["cancel_seconds"] = ProcessInfo.processInfo.systemUptime - cancellationStart
            _ = await active.result
        } else if mode.hasPrefix("enrichment") {
            let client = FixtureClient(mode: mode)
            let exporter = ExportProbe()
            let records = values.map { FavoriteVacancyRecord(result: $0, favoritedAt: Date(), updatedAt: Date()) }
            let model = VacancySearchViewModel(apiClient: client, employerStore: Employers(),
                areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")),
                favoritesStore: InMemoryFavoriteVacancyStore(favorites: records), favoritePDFExporter: exporter)
            await model.loadPersistenceIfNeeded()
            if mode == "enrichment-favorites" { model.displayMode = .favorites }
            let expectedIDs = model.favorites.map(\.id)
            await model.exportFavoriteVacanciesPDF()
            if mode == "enrichment-repeat" || mode == "enrichment-favorites" {
                await model.exportFavoriteVacanciesPDF()
                precondition(exporter.calls == 2 && exporter.lastIDs == expectedIDs)
                let requestCount = await client.requests
                precondition(requestCount == count)
            }
            result["detail_requests"] = await client.requests
            result["export_calls"] = exporter.calls
        } else if mode == "search" {
            let client = FixtureClient(mode: mode, searchCount: count)
            let service = VacancyCollectionService(client: client)
            let areas = try AreaDirectoryIndex(root: .init(id: "113", name: "Россия"))
            let collected = try await service.collect(
                employers: [.init(id: "3529", name: "СБЕР", comment: "benchmark")],
                areas: areas,
                progress: { _ in }
            )
            precondition(collected.isComplete && collected.vacancies.count == count)
            result["search_requests"] = await client.requests
        } else if mode == "archive" {
            let client = FixtureClient(mode: mode)
            let records = values.map {
                FavoriteVacancyRecord(result: $0, favoritedAt: .distantPast, updatedAt: .distantPast)
            }
            let store = InMemoryFavoriteVacancyStore(favorites: records)
            let model = VacancySearchViewModel(
                apiClient: client,
                employerStore: Employers(),
                areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")),
                favoritesStore: store,
                currentDate: { Date(timeIntervalSince1970: 1_788_400_000) }
            )
            await model.checkArchiveStatusesIfNeeded()
            await model.waitForPendingFavoritesSaves()
            precondition(model.favorites.allSatisfy { $0.archiveCheckedAt != nil })
            result["detail_requests"] = await client.requests
        } else {
            let worker = PDFExportWorker()
            var pages = 0
            var bytes = 0
            var resident: [Int] = []
            var descriptors: [Int] = []
            let cycles = mode == "soak" ? 6 : 1
            let heartbeat = Heartbeat()
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeat.tick()
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            let client = FixtureClient(mode: "joint")
            let network = Task {
                for i in 0..<20 {
                    _ = try await client.vacancyDetails(id: "\(i)")
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            for cycle in 0..<cycles {
                if mode == "statistics" || mode == "soak" {
                    let report = VacancyStatisticsReport(entries: values.map(VacancyStatisticsReport.Entry.init),
                        modeName: "Все вакансии", employerID: "all", employerName: "Все работодатели",
                        regionID: "all", regionName: "Все регионы", createdAt: Date(timeIntervalSince1970: 1_788_400_000),
                        timeZoneIdentifier: "UTC", sourceNote: "Локальный benchmark; запросов к HH нет.")
                    let url = directory.appendingPathComponent("statistics.pdf")
                    try await worker.exportStatistics(report: report, destination: url)
                    let pdf = PDFDocument(url: url)!
                    pages = pdf.pageCount
                    bytes = try Data(contentsOf: url).count
                    // macOS 13 PDFKit may extract Cyrillic к as the shared kra glyph.
                    let text = pdf.string?.replacingOccurrences(of: "\u{0138}", with: "к")
                        .precomposedStringWithCanonicalMapping
                    precondition(text?.contains("Вакансия \(count - 1)") == true)
                    if let preview = ProcessInfo.processInfo.environment["HH_BENCH_PREVIEW"] {
                        try Data(contentsOf: url).write(to: URL(fileURLWithPath: preview), options: .atomic)
                    }
                } else {
                    let prepared = try await worker.prepare(vacancies: .init(values: values), progress: { _ in })
                    let names = (0..<prepared.partCount).map { "part-\($0).pdf" }
                    let written = try await worker.writePrepared(names: names, directory: directory)
                    pages = prepared.pageCount
                    bytes = try written.reduce(0) { try $0 + Data(contentsOf: $1).count }
                    for url in written { try FileManager.default.removeItem(at: url) }
                }
                resident.append(residentKiB())
                descriptors.append((0..<1024).filter { fcntl(Int32($0), F_GETFD) != -1 }.count)
                result["completed_cycles"] = cycle + 1
            }
            _ = try await network.value
            ticker.cancel()
            result["pages"] = pages
            result["pdf_bytes"] = bytes
            result["main_actor_max_gap_seconds"] = heartbeat.maximumGap
            result["main_actor_ticks"] = heartbeat.ticks
            result["concurrent_mock_requests"] = await client.requests
            result["resident_kib"] = resident
            result["open_descriptors_under_1024"] = descriptors
        }
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        func cpu(_ value: rusage) -> Double {
            Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
                + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
        }
        result["seconds"] = ProcessInfo.processInfo.systemUptime - start
        result["cpu_seconds"] = cpu(after) - cpu(before)
        result["peak_rss_bytes"] = after.ru_maxrss
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    static func vacancy(_ index: Int, paragraphs: Int) -> VacancySearchResult {
        let summary = HHVacancySummary(id: "\(index)", name: "Вакансия \(index)",
            employer: .init(name: "СБЕР", id: "3529"), salary: nil,
            area: .init(id: "1", name: "Москва"), alternateURL: nil, url: nil, snippet: nil,
            publishedAt: "2026-09-01T10:00:00+0300")
        let html = (0..<paragraphs).map { "<p>Раздел \($0). Разработка надёжных сервисов, анализ данных и тестирование. Swift, SQL, Unicode: ёж, Ω.</p>" }.joined()
        return VacancySearchResult(id: summary.id, summary: summary,
            details: .init(id: summary.id, name: summary.name, employer: summary.employer, area: summary.area,
                salary: nil, alternateURL: nil, description: html),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва"))
    }

    static func residentKiB() -> Int {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
    }
}

private actor Signal {
    var signalled = false
    var waiter: CheckedContinuation<Void, Never>?
    func wait() async { if !signalled { await withCheckedContinuation { waiter = $0 } } }
    func signal() { signalled = true; waiter?.resume(); waiter = nil }
}

@MainActor private final class Heartbeat {
    var last = ProcessInfo.processInfo.systemUptime
    var maximumGap = 0.0
    var ticks = 0
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        maximumGap = max(maximumGap, now - last)
        last = now; ticks += 1
    }
}

private struct Employers: EmployerConfigurationStoring {
    func loadOrCreate() throws -> EmployerConfiguration { .init(version: 1, employers: []) }
}

@MainActor private final class ExportProbe: FavoriteVacanciesPDFExporting {
    var calls = 0
    var lastIDs: [String] = []
    func export(vacancies: [VacancySearchResult], progress: @escaping @MainActor @Sendable (FavoritePDFExportProgress) -> Void) async throws -> FavoritePDFExportOutcome {
        calls += 1
        lastIDs = vacancies.map(\.id)
        return .cancelled
    }
}

private actor FixtureClient: HHVacancyAPIClient {
    let mode: String
    let searchCount: Int
    var requests = 0
    init(mode: String, searchCount: Int = 0) {
        self.mode = mode
        self.searchCount = searchCount
    }
    nonisolated func validateVacanciesAccess() throws {}
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        requests += 1
        if mode == "enrichment-cancel" { throw CancellationError() }
        if mode == "enrichment-limit" { throw HHAPIError.rateLimited(retryAfterSeconds: 60) }
        let value = RuntimeBenchmarks.vacancy(Int(id) ?? 0, paragraphs: 12)
        guard mode == "archive" else { return value.details }
        return .init(
            id: value.id,
            name: value.name,
            employer: value.details.employer,
            area: value.details.area,
            salary: value.details.salary,
            alternateURL: value.details.alternateURL,
            description: value.details.description,
            archived: true
        )
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        guard mode == "search" else { fatalError("No live search") }
        requests += 1
        let start = min(searchCount, request.page * request.perPage)
        let end = min(searchCount, start + request.perPage)
        let items = (start..<end).map { RuntimeBenchmarks.vacancy($0, paragraphs: 1).summary }
        let pages = max(1, Int(ceil(Double(searchCount) / Double(request.perPage))))
        return .init(items: items, found: searchCount, pages: pages, page: request.page, perPage: request.perPage)
    }
    func areaTree() async throws -> HHAreaNode { fatalError("No live areas") }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries { fatalError("No live dictionaries") }
}

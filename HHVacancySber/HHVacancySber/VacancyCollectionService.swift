import Foundation

struct VacancyCollectionProgress: Equatable, Sendable {
    let employerName: String
    let loadedCount: Int
    let partition: String
}

/// An employer whose vacancies were not read completely: the count differs from
/// hh.ru `found`, or some partitions failed after the client's own retries.
struct VacancyCollectionIssue: Codable, Equatable, Sendable {
    let employerID: String
    let employerName: String
    /// `found` of the employer's first request; nil when even that request failed.
    let expected: Int?
    let actual: Int
    let failures: [String]

    var message: String {
        var parts: [String] = []
        if let expected {
            if expected != actual { parts.append("ожидалось \(expected), получено \(actual)") }
        } else {
            parts.append("вакансии не получены")
        }
        if let first = failures.first {
            parts.append(failures.count == 1 ? "ошибка: \(first)" : "ошибок: \(failures.count), первая: \(first)")
        }
        return "\(employerName) – " + parts.joined(separator: ", ")
    }
}

struct VacancyCollectionResult: Sendable {
    let vacancies: [HHVacancySummary]
    let issues: [VacancyCollectionIssue]
    var isComplete: Bool { issues.isEmpty }
}

/// Best-effort full collection. hh.ru results change while they are paged, so a
/// short read is re-read once and then kept with an issue instead of discarding
/// every employer. Access restrictions stop the run and retain received pages;
/// authentication errors and cancellation still abort it.
struct VacancyCollectionService: Sendable {
    static let maximumAccessibleResults = 2_000
    static let perPage = 100
    private let client: any HHVacancyAPIClient
    private let now: @Sendable () -> Date
    private let maximumRequests: Int
    private let maximumDuration: TimeInterval
    private let uptime: @Sendable () -> TimeInterval

    // 47 employers × 20 accessible pages × two completeness passes = 1,880.
    // 2,000 leaves room for probes/splits; exceeding it is explicitly incomplete.
    // At one second pacing this is roughly 34 minutes without retries; allow one hour.
    init(client: any HHVacancyAPIClient, now: @escaping @Sendable () -> Date = { Date() },
         maximumRequests: Int = 2_000, maximumDuration: TimeInterval = 3_600,
         uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.client = client
        self.now = now
        self.maximumRequests = max(1, maximumRequests)
        self.maximumDuration = max(0, maximumDuration)
        self.uptime = uptime
    }

    typealias Progress = @MainActor @Sendable (VacancyCollectionProgress) -> Void

    private struct Outcome {
        var values: [String: HHVacancySummary] = [:]
        var failures: [String] = []
        var firstError: Error?

        mutating func merge(_ other: Outcome) {
            values.merge(other.values) { current, _ in current }
            failures += other.failures
            firstError = firstError ?? other.firstError
        }
    }

    static func isTerminal(_ error: Error) -> Bool {
        if error is CancellationError || error is CollectionLimitError { return true }
        guard let error = error as? HHAPIError else { return false }
        switch error {
        case .requestFailed, .invalidResponse: return false
        case .invalidURL, .missingApplicationToken, .placeholderApplicationToken, .unauthorized,
             .forbidden, .rateLimited, .captchaRequired: return true
        }
    }

    func collect(
        employers: [EmployerConfigurationEntry],
        areas: AreaDirectoryIndex,
        progress: @escaping Progress
    ) async throws -> VacancyCollectionResult {
        let run = CollectionRunClient(client: client, maximumRequests: maximumRequests,
                                      maximumDuration: maximumDuration, uptime: uptime)
        do {
            return try await VacancyCollectionService(client: run, now: now).collectWithinBudget(
                employers: employers, areas: areas, run: run, progress: progress
            )
        } catch let error as CollectionLimitError {
            try Task.checkCancellation()
            return await run.partialResult(employers: employers, error: error)
        } catch let error as HHAPIError {
            try Task.checkCancellation()
            switch error {
            case .rateLimited, .forbidden, .captchaRequired:
                if let result = await run.accessRestrictedResult(employers: employers, error: error) {
                    return result
                }
            default: break
            }
            throw error
        }
    }

    private func collectWithinBudget(
        employers: [EmployerConfigurationEntry], areas: AreaDirectoryIndex, run: CollectionRunClient,
        progress: @escaping Progress
    ) async throws -> VacancyCollectionResult {
        var all: [String: HHVacancySummary] = [:]
        var issues: [VacancyCollectionIssue] = []
        var firstError: Error?
        for employer in employers {
            try Task.checkCancellation()
            let request = HHVacancySearchRequest(employerID: employer.id)
            let initialResponse: HHVacancySearchResponse
            do {
                initialResponse = try await probe(for: request)
            } catch {
                guard !Self.isTerminal(error) else { throw error }
                firstError = firstError ?? error
                issues.append(.init(employerID: employer.id, employerName: employer.name, expected: nil, actual: 0,
                                    failures: [error.localizedDescription]))
                await run.recordFinishedEmployer(employer.id, issues: issues)
                continue
            }
            let outcome = try await collectPartition(
                request, initialResponse: initialResponse, areaNode: areas.root, areas: areas,
                employer: employer, progress: progress
            )
            for item in outcome.values.values { all[item.id] = item }
            firstError = firstError ?? outcome.firstError
            if outcome.values.count != initialResponse.found || !outcome.failures.isEmpty {
                issues.append(.init(employerID: employer.id, employerName: employer.name, expected: initialResponse.found,
                                    actual: outcome.values.count, failures: outcome.failures))
            }
            await run.recordFinishedEmployer(employer.id, issues: issues)
        }
        // Nothing read and a request failed (for example, the network is down): report the
        // error so the previous complete result stays on screen.
        if all.isEmpty, let firstError { throw firstError }
        return VacancyCollectionResult(vacancies: Array(all.values), issues: issues)
    }

    private func collectPartition(
        _ request: HHVacancySearchRequest,
        initialResponse: HHVacancySearchResponse,
        areaNode: HHAreaNode,
        areas: AreaDirectoryIndex,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        let expected = initialResponse.found
        if expected <= Self.maximumAccessibleResults {
            return try await fetchLeaf(request, initialResponse: initialResponse, employer: employer, progress: progress)
        }

        let children = areas.children(of: areaNode.id)
        var outcome = Outcome()
        for child in children {
            let childRequest = replacing(request, areaID: child.id)
            outcome.merge(try await recovering(childRequest) {
                try await collectPartition(
                    childRequest,
                    initialResponse: try await probe(for: childRequest),
                    areaNode: child,
                    areas: areas,
                    employer: employer,
                    progress: progress
                )
            })
        }
        if !children.isEmpty, outcome.values.count >= expected, outcome.failures.isEmpty { return outcome }

        // Areas did not cover the partition: split by publication date and keep the union.
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 946_684_800)
        let end = calendar.date(byAdding: .day, value: 1, to: now()) ?? now()
        outcome.merge(try await collectByDate(
            request,
            start: request.dateFrom ?? start,
            end: request.dateTo ?? end,
            employer: employer,
            progress: progress
        ))
        // Failures the date split made up for no longer describe missing vacancies.
        if outcome.values.count >= expected { outcome.failures = [] }
        return outcome
    }

    private func collectByDate(
        _ request: HHVacancySearchRequest,
        start: Date,
        end: Date,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        let span = end.timeIntervalSince(start)
        guard span > 300 else {
            return try await recovering(request) {
                try await collectByDictionaries(request, employer: employer, progress: progress)
            }
        }
        let midpoint = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 + span / 2))
        // Overlap the boundary: deduplication is safer than a gap for fractional timestamps.
        let secondStart = midpoint
        var combined = Outcome()
        for (lower, upper) in [(start, midpoint), (secondStart, end)] where lower <= upper {
            let child = replacing(request, dateFrom: lower, dateTo: upper)
            combined.merge(try await recovering(child) {
                let initialResponse = try await probe(for: child)
                return initialResponse.found <= Self.maximumAccessibleResults
                    ? try await fetchLeaf(child, initialResponse: initialResponse, employer: employer, progress: progress)
                    : try await collectByDate(child, start: lower, end: upper, employer: employer, progress: progress)
            })
        }
        return combined
    }

    private enum DictionaryDimension: String {
        case experience, workFormat, schedule
    }

    private func collectByDictionaries(
        _ request: HHVacancySearchRequest,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        let dictionaries = try await client.vacancyDictionaries()
        let dimensions: [(DictionaryDimension, [String])] = [
            (.experience, dictionaries.experience.compactMap(\.id)),
            (.workFormat, dictionaries.workFormat.compactMap(\.id)),
            (.schedule, dictionaries.schedule.compactMap(\.id))
        ].filter { !$0.1.isEmpty }
        return try await collectByDictionaryDimension(
            request,
            dimensions: dimensions,
            dimensionIndex: 0,
            employer: employer,
            progress: progress
        )
    }

    private func collectByDictionaryDimension(
        _ request: HHVacancySearchRequest,
        dimensions: [(DictionaryDimension, [String])],
        dimensionIndex: Int,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        guard dimensionIndex < dimensions.count else {
            // No filter narrows it further: read the accessible 2 000; the shortfall is reported.
            return try await fetchLeaf(request, initialResponse: try await probe(for: request), employer: employer, progress: progress)
        }
        let (dimension, values) = dimensions[dimensionIndex]
        var combined = Outcome()
        for value in values {
            let child = replacing(request, dimension: dimension, value: value)
            combined.merge(try await recovering(child) {
                let initialResponse = try await probe(for: child)
                return initialResponse.found <= Self.maximumAccessibleResults
                    ? try await fetchLeaf(child, initialResponse: initialResponse, employer: employer, progress: progress)
                    : try await collectByDictionaryDimension(
                        child,
                        dimensions: dimensions,
                        dimensionIndex: dimensionIndex + 1,
                        employer: employer,
                        progress: progress
                    )
            })
        }
        return combined
    }

    /// A non-terminal error ends only this partition; it is recorded and the collection continues.
    private func recovering(
        _ request: HHVacancySearchRequest,
        _ body: () async throws -> Outcome
    ) async throws -> Outcome {
        do {
            return try await body()
        } catch {
            guard !Self.isTerminal(error) else { throw error }
            return Outcome(failures: ["\(partitionName(request)): \(error.localizedDescription)"], firstError: error)
        }
    }

    private func replacing(
        _ request: HHVacancySearchRequest,
        dimension: DictionaryDimension,
        value: String
    ) -> HHVacancySearchRequest {
        HHVacancySearchRequest(
            employerID: request.employerID,
            areaID: request.areaID,
            page: request.page,
            perPage: request.perPage,
            dateFrom: request.dateFrom,
            dateTo: request.dateTo,
            experience: dimension == .experience ? value : request.experience,
            workFormat: dimension == .workFormat ? value : request.workFormat,
            schedule: dimension == .schedule ? value : request.schedule
        )
    }

    private func probe(for request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        try await client.searchVacancies(replacing(request, page: 0, perPage: Self.perPage))
    }

    /// Reads a partition of at most 2 000 results. A short read is repeated once and the
    /// two reads are combined: vacancies published or closed meanwhile shift the pages.
    private func fetchLeaf(
        _ request: HHVacancySearchRequest,
        initialResponse: HHVacancySearchResponse,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        var outcome = try await fetchPages(request, initialResponse: initialResponse, employer: employer, progress: progress)
        guard outcome.values.count < initialResponse.found, outcome.failures.isEmpty else { return outcome }
        outcome.merge(try await recovering(request) {
            let response = try await probe(for: request)
            return try await fetchPages(request, initialResponse: response, employer: employer, progress: progress)
        })
        return outcome
    }

    private func fetchPages(
        _ request: HHVacancySearchRequest,
        initialResponse: HHVacancySearchResponse,
        employer: EmployerConfigurationEntry,
        progress: @escaping Progress
    ) async throws -> Outcome {
        var result: [String: HHVacancySummary] = [:]
        for item in initialResponse.items { result[item.id] = item }
        guard initialResponse.found > 0 else { return Outcome(values: result) }
        await progress(.init(employerName: employer.name, loadedCount: result.count, partition: partitionName(request)))
        let pages = min(
            (min(max(0, initialResponse.found), Self.maximumAccessibleResults) + Self.perPage - 1) / Self.perPage,
            Self.maximumAccessibleResults / Self.perPage
        )
        for page in stride(from: 1, to: pages, by: 1) {
            try Task.checkCancellation()
            let response: HHVacancySearchResponse
            do {
                response = try await client.searchVacancies(replacing(request, page: page, perPage: Self.perPage))
            } catch {
                // Keep the pages already read; the missing tail is reported for the employer.
                guard !Self.isTerminal(error) else { throw error }
                return Outcome(values: result, failures: ["\(partitionName(request)), стр. \(page + 1): \(error.localizedDescription)"], firstError: error)
            }
            for item in response.items { result[item.id] = item }
            await progress(.init(employerName: employer.name, loadedCount: result.count, partition: partitionName(request)))
            if response.items.isEmpty, response.rejectedItemCount == 0 { break }
        }
        return Outcome(values: result)
    }

    private func partitionName(_ request: HHVacancySearchRequest) -> String {
        var values = ["area=\(request.areaID)"]
        if request.dateFrom != nil || request.dateTo != nil { values.append("date") }
        if let experience = request.experience { values.append("experience=\(experience)") }
        if let workFormat = request.workFormat { values.append("work_format=\(workFormat)") }
        if let schedule = request.schedule { values.append("schedule=\(schedule)") }
        return values.joined(separator: ", ")
    }

    private func replacing(
        _ request: HHVacancySearchRequest,
        areaID: String? = nil,
        page: Int? = nil,
        perPage: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        experience: String? = nil
    ) -> HHVacancySearchRequest {
        HHVacancySearchRequest(
            employerID: request.employerID,
            areaID: areaID ?? request.areaID,
            page: page ?? request.page,
            perPage: perPage ?? request.perPage,
            dateFrom: dateFrom ?? request.dateFrom,
            dateTo: dateTo ?? request.dateTo,
            experience: experience ?? request.experience,
            workFormat: request.workFormat,
            schedule: request.schedule
        )
    }
}


private enum CollectionLimitError: LocalizedError {
    case reached
    var errorDescription: String? {
        "Достигнут защитный предел запросов или времени сбора. Выгрузка неполная; повторите обновление позже."
    }
}

/// Per-collection budget, shared by every recursive branch. It retains successful
/// pages so unwinding a deep split cannot discard data on reaching a budget
/// or an access restriction.
private actor CollectionRunClient: HHVacancyAPIClient {
    nonisolated let client: any HHVacancyAPIClient
    private let maximumRequests: Int
    private let deadline: TimeInterval
    private let uptime: @Sendable () -> TimeInterval
    private var requests = 0
    private var values: [String: HHVacancySummary] = [:]
    private var employerValues: [String: Set<String>] = [:]
    private var expected: [String: Int] = [:]
    private var dictionaries: HHVacancyDictionaries?
    private var finishedEmployers: Set<String> = []
    private var finishedIssues: [VacancyCollectionIssue] = []

    init(client: any HHVacancyAPIClient, maximumRequests: Int, maximumDuration: TimeInterval,
         uptime: @escaping @Sendable () -> TimeInterval) {
        self.client = client
        self.maximumRequests = maximumRequests
        self.uptime = uptime
        deadline = uptime() + maximumDuration
    }

    private func reserve() throws {
        try Task.checkCancellation()
        guard requests < maximumRequests, uptime() < deadline else { throw CollectionLimitError.reached }
        requests += 1
    }

    nonisolated func validateVacanciesAccess() throws { try client.validateVacanciesAccess() }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        try reserve()
        let response = try await client.searchVacancies(request)
        try Task.checkCancellation()
        if expected[request.employerID] == nil { expected[request.employerID] = response.found }
        for item in response.items {
            values[item.id] = item
            employerValues[request.employerID, default: []].insert(item.id)
        }
        return response
    }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        if let dictionaries { return dictionaries }
        try reserve()
        let result = try await client.vacancyDictionaries()
        dictionaries = result
        return result
    }
    func areaTree() async throws -> HHAreaNode { try reserve(); return try await client.areaTree() }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        try reserve(); return try await client.vacancyDetails(id: id)
    }
    func partialResult(employers: [EmployerConfigurationEntry], error: CollectionLimitError) -> VacancyCollectionResult {
        // Conservatively mark the whole run: count equality alone is not proof of a full traversal.
        .init(vacancies: Array(values.values), issues: employers.map {
            .init(employerID: $0.id, employerName: $0.name, expected: expected[$0.id],
                  actual: employerValues[$0.id]?.count ?? 0, failures: [error.localizedDescription])
        })
    }

    func recordFinishedEmployer(_ id: String, issues: [VacancyCollectionIssue]) {
        finishedEmployers.insert(id)
        finishedIssues = issues
    }

    func accessRestrictedResult(employers: [EmployerConfigurationEntry], error: HHAPIError) -> VacancyCollectionResult? {
        guard !values.isEmpty else { return nil }
        let failures = ["Сбор остановлен ограничением hh.ru: \(error.localizedDescription)"]
        let unfinished = employers.filter { !finishedEmployers.contains($0.id) }.map {
            VacancyCollectionIssue(employerID: $0.id, employerName: $0.name, expected: expected[$0.id],
                                   actual: employerValues[$0.id]?.count ?? 0, failures: failures)
        }
        return .init(vacancies: Array(values.values), issues: finishedIssues + unfinished)
    }
}

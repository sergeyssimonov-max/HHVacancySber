import Foundation

/// Only accepted collection data is persisted; transient detail/loading state is not.
struct VacancySnapshot: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let summary: HHVacancySummary
        let location: VacancyLocation
    }

    let version: Int
    let vacancies: [Entry]
    let issues: [VacancyCollectionIssue]
    let updatedAt: Date

    init(values: [VacancySearchResult], issues: [VacancyCollectionIssue], updatedAt: Date) {
        version = 1
        vacancies = values.map { Entry(summary: $0.summary, location: $0.location) }
        self.issues = issues
        self.updatedAt = updatedAt
    }

    init(vacancies: [Entry], issues: [VacancyCollectionIssue], updatedAt: Date) {
        version = 1
        self.vacancies = vacancies
        self.issues = issues
        self.updatedAt = updatedAt
    }

    var results: [VacancySearchResult] {
        vacancies.map { VacancySearchResult(summary: $0.summary, location: $0.location) }
    }
}

protocol VacancySnapshotStoring: Sendable {
    func load() throws -> VacancySnapshot?
    func save(_ snapshot: VacancySnapshot) throws
}

enum VacancySnapshotStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case corruptedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Версия снимка вакансий \(version) не поддерживается."
        case .corruptedFile: return "Файл снимка вакансий повреждён."
        }
    }
}

struct VacancySnapshotStore: VacancySnapshotStoring, @unchecked Sendable {
    private let configuredFileURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        configuredFileURL = fileURL
        self.fileManager = fileManager
    }

    var fileURL: URL {
        get throws {
            if let configuredFileURL { return configuredFileURL }
            return try ApplicationSupportLocation.fileURL(named: "vacancies.json", fileManager: fileManager)
        }
    }

    func load() throws -> VacancySnapshot? {
        let fileURL = try self.fileURL
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        struct Version: Decodable { let version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let version = try? decoder.decode(Version.self, from: data).version else {
            _ = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            throw VacancySnapshotStoreError.corruptedFile
        }
        guard version == 1 else { throw VacancySnapshotStoreError.unsupportedVersion(version) }
        struct Recovery: Decodable {
            let vacancies: [RecoverableItem<VacancySnapshot.Entry>]
            let issues: [RecoverableItem<VacancyCollectionIssue>]
            let updatedAt: Date
        }
        guard let snapshot = try? decoder.decode(Recovery.self, from: data) else {
            _ = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            throw VacancySnapshotStoreError.corruptedFile
        }
        var seen = Set<String>()
        let values = snapshot.vacancies.compactMap(\.value).filter { seen.insert($0.summary.id).inserted }
        var issues = snapshot.issues.compactMap(\.value)
        let skipped = snapshot.vacancies.count - values.count + snapshot.issues.count - issues.count
        if skipped > 0 {
            let backup = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            issues.append(.init(employerID: "snapshot-recovery", employerName: "Снимок вакансий", expected: nil,
                                actual: 0, failures: ["Восстановлен частично, пропущено записей: \(skipped); копия: \(backup.lastPathComponent)"]))
        }
        return VacancySnapshot(vacancies: values, issues: issues, updatedAt: snapshot.updatedAt)
    }

    func save(_ snapshot: VacancySnapshot) throws {
        let fileURL = try self.fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

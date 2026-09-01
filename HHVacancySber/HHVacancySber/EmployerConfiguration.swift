import Foundation

struct EmployerConfigurationEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let comment: String
}

struct EmployerConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let employers: [EmployerConfigurationEntry]

    func validated() throws -> EmployerConfiguration {
        guard version == Self.currentVersion else { throw EmployerConfigurationError.unsupportedVersion(version) }
        guard !employers.isEmpty else { throw EmployerConfigurationError.empty }
        var ids = Set<String>()
        for employer in employers {
            guard !employer.id.isEmpty,
                  employer.id.utf8.allSatisfy({ (48...57).contains($0) }),
                  employer.id.first != "0",
                  employer.name.nilIfBlank != nil,
                  employer.comment.nilIfBlank != nil else {
                throw EmployerConfigurationError.invalidEntry(employer.id)
            }
            guard ids.insert(employer.id).inserted else { throw EmployerConfigurationError.duplicateID(employer.id) }
        }
        return self
    }
}

enum EmployerConfigurationError: LocalizedError, Equatable {
    case missingBundledDefault
    case empty
    case unsupportedVersion(Int)
    case invalidEntry(String)
    case duplicateID(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledDefault: return "В приложении отсутствует базовый employers.json."
        case .empty: return "Список работодателей пуст."
        case .unsupportedVersion(let version): return "Версия employers.json \(version) не поддерживается."
        case .invalidEntry(let id): return "Некорректная запись работодателя: \(id)."
        case .duplicateID(let id): return "Идентификатор работодателя \(id) указан повторно."
        }
    }
}

protocol EmployerConfigurationStoring: Sendable {
    func loadOrCreate() throws -> EmployerConfiguration
}

struct EmployerConfigurationStore: EmployerConfigurationStoring, @unchecked Sendable {
    private let configuredFileURL: URL?
    private let bundledDefaultURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, bundledDefaultURL: URL? = nil, fileManager: FileManager = .default) {
        configuredFileURL = fileURL
        self.bundledDefaultURL = bundledDefaultURL
        self.fileManager = fileManager
    }

    var fileURL: URL {
        if let configuredFileURL { return configuredFileURL }
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("HHVacancySber", isDirectory: true).appendingPathComponent("employers.json")
    }

    func loadOrCreate() throws -> EmployerConfiguration {
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard let bundledDefaultURL else { throw EmployerConfigurationError.missingBundledDefault }
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Data(contentsOf: bundledDefaultURL)
            _ = try JSONDecoder().decode(EmployerConfiguration.self, from: data).validated()
            try data.write(to: fileURL, options: .atomic)
        }
        return try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: fileURL)).validated()
    }
}

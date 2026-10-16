import Foundation

enum ApplicationSupportLocation {
    static let directoryName = "HHVacancySber"

    static func fileURL(named fileName: String, fileManager: FileManager) throws -> URL {
        do {
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        } catch {
            throw ApplicationSupportLocationError.unavailable(error.localizedDescription)
        }
    }
}

enum ApplicationSupportLocationError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Каталог Application Support/HHVacancySber недоступен: \(reason)"
        }
    }
}

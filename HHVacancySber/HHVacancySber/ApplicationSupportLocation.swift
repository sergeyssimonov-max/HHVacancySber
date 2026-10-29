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

/// Preserve the original bytes without replacing earlier recovery copies.
enum CorruptFileBackup {
    static func copy(_ source: URL, fileManager: FileManager) throws -> URL {
        var index = 0
        while true {
            let suffix = index == 0 ? ".bak" : ".bak.\(index)"
            let destination = URL(fileURLWithPath: source.path + suffix)
            if fileManager.fileExists(atPath: destination.path) { index += 1; continue }
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
    }
}

struct RecoverableItem<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

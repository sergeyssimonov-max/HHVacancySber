import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import Foundation

enum VacancyPDFDefaults {
    static let paperSize = NSSize(width: 595.28, height: 841.89)
    static let horizontalMargin: CGFloat = 40
    static let verticalMargin: CGFloat = 32
    // NSLayoutManager and NSAttributedString.draw can differ by a fraction of a
    // line in their final font-leading calculation. Reserve one body line so a
    // glyph range accepted by pagination cannot be clipped during PDF drawing.
    // Keep two compact body lines because a list marker and its wrapped text can
    // use different final line fragments in the two AppKit layout paths.
    static let paginationBottomSafetyMargin: CGFloat = 40

    static func personalFileName(
        vacancyID: String,
        vacancyName: String,
        exportStartedAt: Date = Date()
    ) -> String {
        PDFFileNameBuilder.personal(
            vacancyID: vacancyID,
            title: vacancyName,
            exportStartedAt: exportStartedAt
        )
    }

    static func favoritesFileName(
        part: Int,
        totalParts: Int,
        exportStartedAt: Date = Date()
    ) -> String {
        PDFFileNameBuilder.favorites(
            part: part,
            totalParts: totalParts,
            exportStartedAt: exportStartedAt
        )
    }
}

enum PDFFileNameBuilder {
    static let maximumUTF8Length = 240

    static func statisticsReport(_ report: VacancyStatisticsReport) -> String {
        // Keep both filter labels readable, even when one is exceptionally long.
        let labels = [report.modeName, report.employerName, report.regionName].map {
            prefixFittingUTF8Budget(sanitize($0, fallback: "all"), budget: 48)
        }.joined(separator: "_")
        let configuration = [report.modeName, report.employerID, report.regionID].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(configuration.utf8)).prefix(4)
            .map { String(format: "%02x", $0) }.joined()
        return fileName(
            base: "\(timestamp(report.createdAt))_статистика_\(labels)",
            semanticSuffix: digest,
            fallback: "статистика_вакансий"
        )
    }

    static func personal(vacancyID: String, title: String, exportStartedAt: Date) -> String {
        let safeTitle = sanitize(title, fallback: "без названия")
        return fileName(
            base: "\(timestamp(exportStartedAt))_\(safeTitle)",
            fallback: "вакансия"
        )
    }

    static func favorites(part: Int, totalParts: Int, exportStartedAt: Date) -> String {
        let stem = "\(timestamp(exportStartedAt))_избранные_вакансии"
        guard totalParts > 1 else { return fileName(base: stem, fallback: "избранные_вакансии") }
        return fileName(
            base: stem,
            semanticSuffix: "том_\(String(format: "%03d", part))_из_\(String(format: "%03d", totalParts))",
            fallback: "избранные_вакансии"
        )
    }

    static func sanitize(_ value: String, fallback: String) -> String {
        var result = value.precomposedStringWithCanonicalMapping
        while result.lowercased().hasSuffix(".pdf") {
            result.removeLast(4)
        }
        result = snakeCaseScalars(result)
        if !result.isEmpty { return result }
        let safeFallback = snakeCaseScalars(fallback.precomposedStringWithCanonicalMapping)
        return safeFallback.isEmpty ? "vacancy" : safeFallback
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy_MM_dd_HH_mm"
        return formatter.string(from: date)
    }

    static func fileName(
        base: String,
        semanticSuffix: String? = nil,
        fallback: String
    ) -> String {
        let safeBase = sanitize(base, fallback: fallback)
        let suffix = semanticSuffix.map { "_" + sanitize($0, fallback: "suffix") } ?? ""
        let budget = maximumUTF8Length - suffix.utf8.count - ".pdf".utf8.count
        precondition(budget > 0, "PDF filename suffix exceeds the supported byte budget")

        let fittedBase = prefixFittingUTF8Budget(safeBase, budget: budget)
        let fittedFallback = prefixFittingUTF8Budget(
            sanitize(fallback, fallback: "vacancy"),
            budget: budget
        )
        let finalBase = fittedBase.isEmpty ? fittedFallback : fittedBase
        precondition(!finalBase.isEmpty, "PDF filename base must not be empty")
        let result = finalBase + suffix + ".pdf"
        precondition(result.utf8.count <= maximumUTF8Length)
        return result
    }

    private static func prefixFittingUTF8Budget(_ value: String, budget: Int) -> String {
        var result = ""
        var usedBytes = 0
        for character in value {
            let text = String(character)
            // File URLs may expose decomposed Unicode on macOS. Reserve enough
            // bytes for either representation, including accented Cyrillic.
            let cost = max(text.utf8.count, text.decomposedStringWithCanonicalMapping.utf8.count)
            guard usedBytes + cost <= budget else { break }
            result.append(character)
            usedBytes += cost
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func snakeCaseScalars(_ value: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits)
        var output = ""
        var needsSeparator = false
        for scalar in value.lowercased(with: Locale(identifier: "en_US_POSIX")).unicodeScalars {
            if allowed.contains(scalar) {
                if needsSeparator && !output.isEmpty { output.append("_") }
                output.unicodeScalars.append(scalar)
                needsSeparator = false
            } else if !output.isEmpty {
                needsSeparator = true
            }
        }
        return output
    }
}

enum PDFVisualContentValidator {
    private static let rasterWidth = 160
    private static let whiteThreshold: UInt8 = 245
    private static let minimumInkPixels = 8

    static func pageHasVisibleInk(_ page: CGPDFPage) -> Bool {
        let mediaBox = page.getBoxRect(.mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return false }
        let rasterHeight = max(1, Int((CGFloat(rasterWidth) * mediaBox.height / mediaBox.width).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = rasterWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * rasterHeight)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: rasterWidth,
                height: rasterHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return false
        }

        let bounds = CGRect(x: 0, y: 0, width: rasterWidth, height: rasterHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.concatenate(page.getDrawingTransform(
            .mediaBox,
            rect: bounds,
            rotate: 0,
            preserveAspectRatio: true
        ))
        context.drawPDFPage(page)

        var inkPixels = 0
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            if pixels[offset] < whiteThreshold
                || pixels[offset + 1] < whiteThreshold
                || pixels[offset + 2] < whiteThreshold {
                inkPixels += 1
                if inkPixels >= minimumInkPixels { return true }
            }
        }
        return false
    }
}

enum VacancyPDFFormatter {
    /// Imports the description on the calling (main) actor and builds the document.
    @MainActor
    static func attributedDocument(for vacancy: VacancySearchResult) -> NSAttributedString {
        attributedDocument(for: vacancy, importedDescription: importedDescription(for: vacancy))
    }

    /// AppKit imports HTML through WebKit, which is main-thread only. Import here and pass
    /// the result to background rendering instead of importing inside PDFExportWorker.
    @MainActor
    static func importedDescription(for vacancy: VacancySearchResult) -> NSAttributedString? {
        guard let html = descriptionHTML(for: vacancy) else { return nil }
        return VacancyHTMLAttributedText.convert(html)
    }

    /// Safe off the main actor: HTML is never imported here. A description that was not
    /// imported in advance falls back to plain text.
    static func attributedDocument(
        for vacancy: VacancySearchResult,
        importedDescription: NSAttributedString?
    ) -> NSAttributedString {
        let builder = VacancyPDFDocumentBuilder()
        let details = vacancy.details

        builder.banner("ВАКАНСИЯ HEADHUNTER")
        builder.title(vacancy.name)
        builder.provenance("Данные вакансии получены с HH.ru")
        if let notice = vacancy.exportDataNotice?.nilIfBlank {
            builder.notice(notice)
        }

        builder.section("Основная информация")
        builder.field("Работодатель", vacancy.employerName)
        if let department = vacancy.departmentName {
            builder.field("Подразделение", department)
        }
        builder.field("Регион", vacancy.areaName)
        appendAddress(details.address, to: builder)
        builder.field("Статус", archiveStatus(for: vacancy))
        if let closed = details.closedForApplicants {
            builder.field("Приём откликов", closed ? "Закрыт" : "Открыт")
        }
        builder.field("Идентификатор вакансии", vacancy.id)
        builder.field("Дата публикации", details.publishedAt?.nilIfBlank ?? vacancy.publishedAt?.nilIfBlank)
        if details.initialCreatedAt?.nilIfBlank != details.publishedAt?.nilIfBlank {
            builder.field("Первоначально создана", details.initialCreatedAt?.nilIfBlank)
        }
        builder.field("Действует до", details.expiresAt?.nilIfBlank)
        builder.field("Дата архивации", details.archivedAt?.nilIfBlank)
        builder.linkField("Исходная ссылка HH.ru", vacancy.alternateURL)

        appendSalary(details: details, fallbackText: vacancy.salaryText, to: builder)
        appendEmployment(details, to: builder)
        appendDescription(vacancy, importedDescription: importedDescription, to: builder)

        let skills = names(details.keySkills)
        if !skills.isEmpty {
            builder.section("Ключевые навыки")
            builder.bullets(skills)
        }

        let roles = names(details.professionalRoles)
        if !roles.isEmpty {
            builder.section("Профессиональные роли")
            builder.bullets(roles)
        }

        if let languages = details.languages, !languages.isEmpty {
            let values = languages.compactMap { language -> String? in
                guard let name = language.name?.nilIfBlank ?? language.id?.nilIfBlank else { return nil }
                guard let level = language.level?.name?.nilIfBlank ?? language.level?.id?.nilIfBlank else {
                    return name
                }
                return "\(name) - \(level)"
            }
            if !values.isEmpty {
                builder.section("Языки")
                builder.bullets(values)
            }
        }

        appendContacts(details.contacts, to: builder)
        appendEmployer(details.employer, to: builder)
        appendAdditionalConditions(details, to: builder)
        return builder.document
    }

    private static func archiveStatus(for vacancy: VacancySearchResult) -> String {
        if vacancy.isArchived { return "В архиве" }
        if vacancy.archiveCheckedAt != nil || vacancy.details.archived == false { return "Активна" }
        return "не проверен"
    }

    private static func appendAddress(_ address: HHVacancyAddress?, to builder: VacancyPDFDocumentBuilder) {
        guard let address else { return }
        let components = [address.city, address.street, address.building]
            .compactMap { $0?.nilIfBlank }
        if !components.isEmpty { builder.field("Адрес", components.joined(separator: ", ")) }
        builder.field("Ориентир", address.description?.nilIfBlank)
        if let stations = address.metroStations {
            let values = stations.compactMap { station -> String? in
                guard let name = station.stationName?.nilIfBlank else { return nil }
                return station.lineName?.nilIfBlank.map { "\(name) (\($0))" } ?? name
            }
            if !values.isEmpty { builder.field("Метро", values.joined(separator: ", ")) }
        }
        if let lat = address.lat, let lng = address.lng {
            builder.field("Координаты", "\(lat), \(lng)")
        }
    }

    private static func appendSalary(
        details: HHVacancyDetails,
        fallbackText: String?,
        to builder: VacancyPDFDocumentBuilder
    ) {
        builder.section("Вознаграждение")
        if let range = details.salaryRange {
            builder.field("От", range.from.map(formatAmount))
            builder.field("До", range.to.map(formatAmount))
            builder.field("Валюта", range.currency?.nilIfBlank)
            builder.field("Налоги", range.gross.map { $0 ? "До вычета налогов" : "На руки" })
            builder.field("Период", range.mode?.name?.nilIfBlank ?? range.mode?.id?.nilIfBlank)
            builder.field("Частота выплаты", range.frequency?.name?.nilIfBlank ?? range.frequency?.id?.nilIfBlank)
            return
        }
        if let salary = details.salary {
            builder.field("От", salary.from.map(formatAmount))
            builder.field("До", salary.to.map(formatAmount))
            builder.field("Валюта", salary.currency?.nilIfBlank)
            builder.field("Налоги", salary.gross.map { $0 ? "До вычета налогов" : "На руки" })
            return
        }
        if let fallbackText = fallbackText?.nilIfBlank {
            builder.field("Сохранённое значение", fallbackText)
        } else {
            builder.plain("HH не указал вознаграждение.")
        }
    }

    private static func appendEmployment(_ details: HHVacancyDetails, to builder: VacancyPDFDocumentBuilder) {
        builder.section("Опыт, занятость и график")
        builder.field("Требуемый опыт", value(details.experience))
        builder.field("Форма занятости", value(details.employmentForm) ?? value(details.employment))
        builder.field("График", value(details.schedule))
        builder.field("Формат работы", joinedNames(details.workFormat))
        builder.field("Рабочие дни", joinedNames(details.workScheduleByDays) ?? joinedNames(details.workingDays))
        builder.field("Рабочие часы", joinedNames(details.workingHours))
        builder.field("Интервалы работы", joinedNames(details.workingTimeIntervals))
        builder.field("Режим времени", joinedNames(details.workingTimeModes))
        builder.field("Длительность вахты", joinedNames(details.flyInFlyOutDuration))
        builder.field("Стажировка", yesNo(details.internship))
        builder.field("Ночные смены", yesNo(details.nightShifts))
    }

    private static func descriptionHTML(for vacancy: VacancySearchResult) -> String? {
        vacancy.details.description?.nilIfBlank ?? vacancy.details.brandedDescription?.nilIfBlank
    }

    private static func appendDescription(
        _ vacancy: VacancySearchResult,
        importedDescription: NSAttributedString?,
        to builder: VacancyPDFDocumentBuilder
    ) {
        builder.section("Описание вакансии")
        if let html = descriptionHTML(for: vacancy) {
            builder.html(importedDescription ?? VacancyHTMLAttributedText.plainText(html))
            return
        }
        builder.notice("Полное описание из detail endpoint HH недоступно.")
        if let snippet = vacancy.summary.snippet?.plainText.nilIfBlank {
            builder.subheading("Сохранённые фрагменты поисковой карточки")
            builder.plain(snippet)
        }
    }

    private static func appendContacts(_ contacts: HHVacancyContacts?, to builder: VacancyPDFDocumentBuilder) {
        guard let contacts else { return }
        let phones = contacts.phones?.compactMap { phone -> String? in
            guard let number = phone.displayText else { return nil }
            return phone.comment?.nilIfBlank.map { "\(number) - \($0)" } ?? number
        } ?? []
        guard contacts.name?.nilIfBlank != nil || !phones.isEmpty else { return }
        builder.section("Контакты")
        builder.field("Контактное лицо", contacts.name?.nilIfBlank)
        if !phones.isEmpty { builder.bullets(phones) }
    }

    private static func appendEmployer(_ employer: HHEmployer?, to builder: VacancyPDFDocumentBuilder) {
        guard let employer else { return }
        let hasDetails = employer.trusted != nil || employer.accreditedITEmployer != nil
            || employer.rating != nil || employer.alternateURL?.nilIfBlank != nil
        guard hasDetails else { return }
        builder.section("Работодатель")
        builder.field("Название", employer.name?.nilIfBlank)
        builder.field("Проверен HH", yesNo(employer.trusted))
        builder.field("Аккредитованный IT-работодатель", yesNo(employer.accreditedITEmployer))
        if let rating = employer.rating {
            builder.field("Рейтинг", rating.totalRating?.nilIfBlank)
            builder.field("Количество отзывов", rating.reviewsCount.map(String.init))
        }
        builder.linkField("Страница работодателя", employer.alternateURL)
    }

    private static func appendAdditionalConditions(
        _ details: HHVacancyDetails,
        to builder: VacancyPDFDocumentBuilder
    ) {
        var fields: [(String, String?)] = []
        fields.append(("Возрастные условия", value(details.ageRestriction)))
        fields.append(("Доступность рабочего места", details.inclusivenessDescription?.nilIfBlank))
        fields.append(("Категории доступности", details.inclusivenessTypes?.filter { !$0.isEmpty }.joined(separator: ", ").nilIfBlank))
        fields.append(("Подходит для неполного резюме", yesNo(details.acceptIncompleteResumes)))
        fields.append(("Трудовой договор", yesNo(details.acceptLaborContract)))
        fields.append(("Временная работа", yesNo(details.acceptTemporary)))
        fields.append(("Доступна соискателям с инвалидностью", yesNo(details.acceptHandicapped)))
        fields.append(("Доступна соискателям от 14 лет", yesNo(details.acceptKids)))
        fields.append(("Сопроводительное письмо обязательно", yesNo(details.responseLetterRequired)))
        fields.append(("Есть тестовое задание", yesNo(details.hasTest)))
        fields.append(("Тест обязателен", yesNo(details.test?.required)))
        fields.append(("Можно написать работодателю", yesNo(details.allowMessages)))
        fields.append(("Категории водительских прав", joinedNames(details.driverLicenseTypes)))
        fields.append(("Гражданско-правовые договоры", joinedNames(details.civilLawContracts)))
        fields.append(("Тип вакансии", value(details.vacancyType)))
        fields.append(("Внутренний код работодателя", details.code?.nilIfBlank))

        let videoURL = details.videoVacancy?.video?.url?.nilIfBlank
            ?? details.videoVacancy?.videoURL?.nilIfBlank
        let hasValues = fields.contains { $0.1?.nilIfBlank != nil }
            || details.applyAlternateURL?.nilIfBlank != nil
            || details.responseURL?.nilIfBlank != nil
            || details.insiderInterview?.url?.nilIfBlank != nil
            || videoURL != nil
        guard hasValues else { return }

        builder.section("Дополнительные условия и ссылки")
        for field in fields { builder.field(field.0, field.1) }
        builder.linkField("Ссылка для отклика", details.applyAlternateURL)
        builder.linkField("Внешняя ссылка для отклика", details.responseURL)
        builder.linkField("Интервью о компании", details.insiderInterview?.url)
        builder.linkField("Видео вакансии", videoURL)
    }

    private static func names(_ items: [HHNamedItem]?) -> [String] {
        items?.compactMap { $0.name?.nilIfBlank ?? $0.id?.nilIfBlank } ?? []
    }

    private static func joinedNames(_ items: [HHNamedItem]?) -> String? {
        names(items).joined(separator: ", ").nilIfBlank
    }

    private static func value(_ item: HHNamedItem?) -> String? {
        item?.name?.nilIfBlank ?? item?.id?.nilIfBlank
    }

    private static func yesNo(_ value: Bool?) -> String? {
        value.map { $0 ? "Да" : "Нет" }
    }

    private static func formatAmount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

struct VacancyStatisticsReport: Sendable {
    struct Entry: Sendable {
        let id: String
        let name: String
        let publishedAt: String?
        let employerID: String
        let employerName: String
        let regionID: String
        let regionName: String
        let isArchived: Bool
        let hasSalary: Bool

        init(_ vacancy: VacancySearchResult) {
            id = vacancy.id
            name = vacancy.name
            publishedAt = vacancy.publishedAt
            employerID = vacancy.employerID ?? "unknown:\(vacancy.employerName)"
            employerName = vacancy.employerName
            regionID = vacancy.location.filterID
            regionName = vacancy.location.subjectName ?? vacancy.areaName
            isArchived = vacancy.isArchived
            hasSalary = vacancy.salaryText?.nilIfBlank != nil
        }
    }

    let entries: [Entry]
    let modeName: String
    let employerID: String
    let employerName: String
    let regionID: String
    let regionName: String
    let createdAt: Date
    let timeZoneIdentifier: String
    let sourceNote: String

    var fileName: String { PDFFileNameBuilder.statisticsReport(self) }

    func orderedEntries() -> [(entry: Entry, date: Date?)] {
        let parser = HHPublicationDateParser()
        return entries.map { entry in
            (entry: entry, date: parser.date(from: entry.publishedAt))
        }.sorted { left, right in
            switch (left.date, right.date) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.entry.id < right.entry.id
            }
        }
    }

    func attributedDocument() throws -> NSAttributedString {
        let builder = VacancyPDFDocumentBuilder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let ordered = orderedEntries()
        let dated = ordered.compactMap(\.date)
        let employers = Dictionary(grouping: entries, by: \.employerID)
        let regions = Dictionary(grouping: entries, by: \.regionID)
        let archived = entries.filter(\.isArchived).count
        let salaried = entries.filter(\.hasSalary).count

        builder.banner("ВАКАНСИИ HEADHUNTER")
        builder.title("Статистический отчёт")
        builder.provenance("Сформирован \(formatter.string(from: createdAt)); часовой пояс: \(timeZoneIdentifier)")
        builder.section("Конфигурация фильтров")
        builder.field("Список", modeName)
        builder.field("Работодатель", employerName)
        builder.field("Регион", regionName)
        builder.plain(sourceNote)
        builder.section("Общая статистика")
        builder.field("Всего вакансий", String(entries.count))
        builder.field("Работодателей", String(employers.count))
        builder.field("Регионов / территориальных групп", String(regions.count))
        builder.field("Активных по локальным данным", String(entries.count - archived))
        builder.field("В архиве", String(archived))
        builder.field("С указанной зарплатой", String(salaried))
        builder.field("Без указанной зарплаты", String(entries.count - salaried))
        if let newest = dated.first, let oldest = dated.last {
            builder.field("Период размещения", "\(formatter.string(from: oldest)) - \(formatter.string(from: newest))")
        }
        builder.field("Без корректной даты размещения", String(entries.count - dated.count))
        builder.section("По работодателям")
        for key in employers.keys.sorted() {
            try Task.checkCancellation()
            guard let values = employers[key], let first = values.first else { continue }
            builder.field(first.employerName, String(values.count))
        }
        builder.section("По регионам")
        for key in regions.keys.sorted() {
            try Task.checkCancellation()
            guard let values = regions[key], let first = values.first else { continue }
            builder.field(first.regionName, String(values.count))
        }
        builder.section("Вакансии: от новых к старым")
        if ordered.isEmpty { builder.plain("Под выбранными фильтрами вакансий нет.") }
        for (index, row) in ordered.enumerated() {
            try Task.checkCancellation()
            let date = row.date.map { formatter.string(from: $0) } ?? "Дата размещения не указана"
            builder.vacancyListItem(index: index + 1, name: row.entry.name, publishedAt: date)
        }
        return builder.document
    }
}

private final class VacancyPDFDocumentBuilder {
    private(set) var document = NSMutableAttributedString()

    // Computed: NSFont is not Sendable, so no shared static instances across actors.
    private static var bodyFont: NSFont { .systemFont(ofSize: 7.5) }
    private static var labelFont: NSFont { .systemFont(ofSize: 9.5, weight: .semibold) }
    private static var headingFont: NSFont { .systemFont(ofSize: 13, weight: .bold) }
    private static var titleFont: NSFont { .systemFont(ofSize: 18, weight: .bold) }
    private static var bannerFont: NSFont { .systemFont(ofSize: 7.5, weight: .semibold) }

    func banner(_ text: String) {
        append(text.uppercased() + "\n", attributes: [
            .font: Self.bannerFont,
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1),
            .kern: 1.1
        ])
    }

    func title(_ text: String) {
        let style = paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 8)
        append(text + "\n", attributes: [.font: Self.titleFont, .foregroundColor: NSColor.black, .paragraphStyle: style])
    }

    func provenance(_ text: String) {
        append(text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: NSColor(calibratedWhite: 0.3, alpha: 1)
        ])
    }

    func notice(_ text: String) {
        let style = paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 8, headIndent: 10, firstLineHeadIndent: 10)
        append(text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1),
            .backgroundColor: NSColor(calibratedWhite: 0.94, alpha: 1),
            .paragraphStyle: style
        ])
    }

    func section(_ text: String) {
        let style = paragraphStyle(lineSpacing: 1, paragraphSpacing: 6, paragraphSpacingBefore: 14)
        append(text + "\n", attributes: [
            .font: Self.headingFont,
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
            .paragraphStyle: style
        ])
    }

    func subheading(_ text: String) {
        append(text + "\n", attributes: [.font: Self.labelFont, .foregroundColor: NSColor.black])
    }

    func field(_ label: String, _ value: String?) {
        guard let value = value?.nilIfBlank else { return }
        let line = NSMutableAttributedString(string: label + ": ", attributes: [
            .font: Self.labelFont, .foregroundColor: NSColor.black
        ])
        line.append(NSAttributedString(string: value + "\n", attributes: [
            .font: Self.bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 2)
        ]))
        document.append(line)
    }

    func linkField(_ label: String, _ value: String?) {
        guard let value = value?.nilIfBlank else { return }
        let line = NSMutableAttributedString(string: label + ": ", attributes: [
            .font: Self.labelFont, .foregroundColor: NSColor.black
        ])
        var attributes: [NSAttributedString.Key: Any] = [
            .font: Self.bodyFont,
            .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.23, blue: 0.46, alpha: 1),
            .paragraphStyle: paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 2, lineBreakMode: .byCharWrapping)
        ]
        if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            attributes[.link] = url
        }
        line.append(NSAttributedString(string: value + "\n", attributes: attributes))
        document.append(line)
    }

    func plain(_ text: String) {
        append(text + "\n", attributes: [
            .font: Self.bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle(lineSpacing: 2.2, paragraphSpacing: 7)
        ])
    }

    func vacancyListItem(index: Int, name: String, publishedAt: String) {
        append("\(index). \(name): \(publishedAt)\n", attributes: [
            .font: Self.bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 5)
        ])
    }

    func bullets(_ values: [String]) {
        let list = NSTextList(markerFormat: .disc, options: 0)
        let style = paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 3, headIndent: 18, firstLineHeadIndent: 4)
        style.textLists = [list]
        style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
        for value in values where value.nilIfBlank != nil {
            append("•\t\(value)\n", attributes: [
                .font: Self.bodyFont, .foregroundColor: NSColor.black, .paragraphStyle: style
            ])
        }
    }

    func html(_ content: NSAttributedString) {
        if !document.string.hasSuffix("\n\n") {
            document.append(NSAttributedString(
                string: "\n",
                attributes: [.font: Self.bodyFont, .foregroundColor: NSColor.black]
            ))
        }
        document.append(content)
        if !document.string.hasSuffix("\n") { document.append(NSAttributedString(string: "\n")) }
    }

    private func append(_ text: String, attributes: [NSAttributedString.Key: Any]) {
        document.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func paragraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat = 0,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        style.lineBreakMode = lineBreakMode
        return style
    }
}

enum VacancyHTMLAttributedText {
    private static let commentExpression = expression(#"<!--[\s\S]*?-->"#)
    private static let blockedElementExpression = expression(
        #"<(script|style|noscript|iframe|object|embed|svg|canvas|form|button|video|audio|picture)\b[^>]*>[\s\S]*?</\1\s*>"#,
        options: [.caseInsensitive]
    )
    private static let unterminatedBlockedElementExpression = expression(
        #"<(script|style|noscript|iframe|object|embed|svg|canvas|form|button|video|audio|picture)\b[^>]*>[\s\S]*$"#,
        options: [.caseInsensitive]
    )
    private static let externalElementExpression = expression(
        #"<(img|input|source|link|meta)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let supportedElementExpression = expression(
        #"<(p|div|br|ul|ol|li|h[1-6]|strong|b|em|i|blockquote|pre|code|hr)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let unsupportedElementExpression = expression(
        #"<(?!/?(?:p|div|br|ul|ol|li|h[1-6]|strong|b|em|i|blockquote|pre|code|hr|a)\b)[^>]+>"#,
        options: [.caseInsensitive]
    )
    private static let anchorExpression = expression(#"<a\b[^>]*>"#, options: [.caseInsensitive])
    private static let anchorHREFExpression = expression(
        #"href\s*=\s*([\"'])(.*?)\1"#,
        options: [.caseInsensitive]
    )

    static func plainText(_ html: String) -> NSAttributedString {
        NSAttributedString(
            string: html.readableHTMLText,
            attributes: [.font: NSFont.systemFont(ofSize: 7.5), .foregroundColor: NSColor.black]
        )
    }

    @MainActor
    static func convert(_ html: String) -> NSAttributedString {
        let sanitized = sanitize(html)
        let wrapped = """
        <html><head><meta charset="utf-8"></head><body>\(sanitized)</body></html>
        """
        guard let data = wrapped.data(using: .utf8),
              let imported = try? NSMutableAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            return plainText(html)
        }

        let fullRange = NSRange(location: 0, length: imported.length)
        imported.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
        imported.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let source = value as? NSFont ?? NSFont.systemFont(ofSize: 11.5)
            let size = min(max(source.pointSize, 10.5), 19) - 4
            var traits = source.fontDescriptor.symbolicTraits
            traits.remove(.monoSpace)
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(traits)
            imported.addAttribute(.font, value: NSFont(descriptor: descriptor, size: size) ?? source, range: range)
        }
        normalizeParagraphStyles(in: imported)
        return imported
    }

    private static func normalizeParagraphStyles(in text: NSMutableAttributedString) {
        let source = text.string as NSString
        var location = 0
        while location < text.length {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            source.getParagraphStart(
                &paragraphStart,
                end: &paragraphEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            let paragraphRange = NSRange(
                location: paragraphStart,
                length: max(0, paragraphEnd - paragraphStart)
            )
            let contentsRange = NSRange(
                location: paragraphStart,
                length: max(0, contentsEnd - paragraphStart)
            )
            let content = source.substring(with: contentsRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let original = text.attribute(
                .paragraphStyle,
                at: min(paragraphStart, max(0, text.length - 1)),
                effectiveRange: nil
            ) as? NSParagraphStyle
            let style = (original?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            let hasList = !style.textLists.isEmpty
            let isBoldHeading = !content.isEmpty
                && content.count <= 80
                && paragraphIsBold(text, range: contentsRange)
                && (!hasList || content.hasSuffix(":"))

            style.lineSpacing = 2
            style.paragraphSpacing = hasList ? 4 : 7
            if isBoldHeading {
                style.textLists = []
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, 9)
                style.paragraphSpacing = 4
            } else if hasList {
                let textColumn = style.tabStops.last?.location ?? max(style.headIndent, 18)
                style.headIndent = textColumn
                style.firstLineHeadIndent = 0
            } else {
                style.headIndent = min(max(style.headIndent, 0), 18)
                style.firstLineHeadIndent = min(max(style.firstLineHeadIndent, 0), 18)
            }
            if paragraphRange.length > 0 {
                text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            }
            location = max(paragraphEnd, location + 1)
        }
    }

    private static func paragraphIsBold(_ text: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var sawText = false
        var allBold = true
        text.enumerateAttribute(.font, in: range) { value, fontRange, stop in
            let substring = (text.string as NSString).substring(with: fontRange)
            guard substring.nilIfBlank != nil else { return }
            sawText = true
            guard let font = value as? NSFont,
                  font.fontDescriptor.symbolicTraits.contains(.bold) else {
                allBold = false
                stop.pointee = true
                return
            }
        }
        return sawText && allBold
    }

    static func sanitize(_ html: String) -> String {
        var value = html
        value = replacing(commentExpression, in: value, with: "")
        value = replacing(
            blockedElementExpression,
            in: value,
            with: ""
        )
        value = replacing(
            unterminatedBlockedElementExpression,
            in: value,
            with: ""
        )
        value = replacing(externalElementExpression, in: value, with: "")
        value = sanitizeAnchors(in: value)
        value = replacing(
            supportedElementExpression,
            in: value,
            with: "<$1>"
        )
        value = replacing(
            unsupportedElementExpression,
            in: value,
            with: ""
        )
        return value
    }

    private static func sanitizeAnchors(in source: String) -> String {
        guard let expression = anchorExpression else { return source }
        let mutable = NSMutableString(string: source)
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        for match in matches.reversed() {
            let tag = mutable.substring(with: match.range)
            let href = firstCapture(expression: anchorHREFExpression, in: tag, group: 2)
            let replacement: String
            if let href,
               let url = URL(string: href),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                let escaped = href.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                replacement = "<a href=\"\(escaped)\">"
            } else {
                replacement = "<a>"
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return mutable as String
    }

    private static func firstCapture(
        expression: NSRegularExpression?,
        in source: String,
        group: Int
    ) -> String? {
        guard let expression,
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: source) else { return nil }
        return String(source[range])
    }

    private static func replacing(
        _ expression: NSRegularExpression?,
        in source: String,
        with replacement: String
    ) -> String {
        guard let expression else { return source }
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: replacement
        )
    }

    private static func expression(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }
}

struct FavoritePDFExportProgress: Equatable {
    let completedVacancies: Int
    let totalVacancies: Int
}

/// A vacancy frozen for background rendering, with its HTML description already
/// imported on the main actor. The attributed string is not mutated after creation.
struct PDFVacancySnapshot: @unchecked Sendable {
    let value: VacancySearchResult
    let importedDescription: NSAttributedString?

    @MainActor
    init(value: VacancySearchResult) {
        self.value = value
        importedDescription = VacancyPDFFormatter.importedDescription(for: value)
    }

    var attributedDocument: NSAttributedString {
        VacancyPDFFormatter.attributedDocument(for: value, importedDescription: importedDescription)
    }
}

struct PDFVacanciesSnapshot: @unchecked Sendable {
    let values: [PDFVacancySnapshot]

    @MainActor
    init(values: [VacancySearchResult]) {
        var snapshots: [PDFVacancySnapshot] = []
        snapshots.reserveCapacity(values.count)
        for value in values { snapshots.append(PDFVacancySnapshot(value: value)) }
        self.values = snapshots
    }

    @MainActor
    init(snapshots: [PDFVacancySnapshot]) {
        values = snapshots
    }

    /// Imports descriptions one by one, letting the UI run between vacancies.
    @MainActor
    static func make(values: [VacancySearchResult]) async throws -> PDFVacanciesSnapshot {
        var snapshots: [PDFVacancySnapshot] = []
        snapshots.reserveCapacity(values.count)
        for value in values {
            try Task.checkCancellation()
            snapshots.append(PDFVacancySnapshot(value: value))
            await Task.yield()
        }
        return PDFVacanciesSnapshot(snapshots: snapshots)
    }
}

enum FavoritePDFExportOutcome: Equatable {
    case cancelled
    case exported(fileCount: Int, pageCount: Int)
}

@MainActor
protocol FavoriteVacanciesPDFExporting {
    func export(
        vacancies: [VacancySearchResult],
        progress: @escaping @MainActor @Sendable (FavoritePDFExportProgress) -> Void
    ) async throws -> FavoritePDFExportOutcome
}

/// Writes new files and never replaces one: each name, or its first free `_N` variant,
/// is created with O_CREAT | O_EXCL, so checking and creating are a single step. If a
/// later file fails or the task is cancelled, the files this call wrote are removed.
enum PDFNewFileWriter {
    static func write(
        _ contents: [Data],
        names: [String],
        in directory: URL,
        maximumCandidates: Int = 10_000,
        beforeEachFile: (Int) throws -> Void = { _ in }
    ) throws -> [URL] {
        guard contents.count == names.count else { throw FavoriteVacanciesPDFExporter.ExportError.missingPreparedExport }
        var written: [URL] = []
        do {
            for (index, (data, name)) in zip(contents, names).enumerated() {
                try Task.checkCancellation()
                try beforeEachFile(index)
                written.append(try writeNewFile(data, name: name, in: directory, maximumCandidates: maximumCandidates))
            }
            return written
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    private static func writeNewFile(_ data: Data, name: String, in directory: URL, maximumCandidates: Int) throws -> URL {
        for number in 1...max(1, maximumCandidates) {
            let candidate = number == 1 ? name : PDFFileNameBuilder.fileName(
                base: name, semanticSuffix: String(number), fallback: "vacancy"
            )
            let url = directory.appendingPathComponent(candidate)
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
            guard descriptor >= 0 else {
                let code = errno
                if code == EEXIST { continue }
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            return url
        }
        throw FavoriteVacanciesPDFExporter.ExportError.noAvailableFileName
    }
}

actor PDFExportWorker {
    private struct PreparedPart: Sendable {
        let data: Data
        let pageCount: Int
    }

    private var preparedParts: [PreparedPart]?

    struct PreparedExport: Sendable {
        let partCount: Int
        let pageCount: Int
    }

    init() {}

    func prepare(
        vacancies: PDFVacanciesSnapshot,
        progress: @escaping @MainActor @Sendable (FavoritePDFExportProgress) -> Void
    ) async throws -> PreparedExport {
        preparedParts = nil
        try Task.checkCancellation()
        var parts: [PreparedPart] = []
        var currentPages: [FavoriteVacanciesPDFExporter.Page] = []
        currentPages.reserveCapacity(FavoriteVacanciesPDFExporter.maximumPagesPerFile)
        var totalPages = 0

        for (index, vacancy) in vacancies.values.enumerated() {
            try Task.checkCancellation()
            let pages = autoreleasepool {
                FavoriteVacanciesPDFExporter.pages(for: vacancy.attributedDocument)
            }
            if !currentPages.isEmpty,
               currentPages.count + pages.count > FavoriteVacanciesPDFExporter.maximumPagesPerFile {
                parts.append(try preparedPart(for: currentPages))
                totalPages += currentPages.count
                currentPages.removeAll(keepingCapacity: true)
            }
            if pages.count > FavoriteVacanciesPDFExporter.maximumPagesPerFile {
                parts.append(try preparedPart(for: pages))
                totalPages += pages.count
            } else {
                currentPages.append(contentsOf: pages)
            }
            await progress(.init(completedVacancies: index + 1, totalVacancies: vacancies.values.count))
        }
        if !currentPages.isEmpty {
            parts.append(try preparedPart(for: currentPages))
            totalPages += currentPages.count
        }
        preparedParts = parts
        return PreparedExport(
            partCount: parts.count,
            pageCount: totalPages
        )
    }

    func discardPreparedExport() {
        preparedParts = nil
    }

    private func preparedPart(
        for pages: [FavoriteVacanciesPDFExporter.Page]
    ) throws -> PreparedPart {
        try Task.checkCancellation()
        let data = try autoreleasepool {
            try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        }
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
        return PreparedPart(data: data, pageCount: pages.count)
    }

    func exportPersonal(
        vacancy: PDFVacancySnapshot,
        destination: URL,
        didRenderPage: (@Sendable (Int) -> Void)? = nil
    ) throws {
        try Task.checkCancellation()
        let pages = autoreleasepool {
            FavoriteVacanciesPDFExporter.pages(for: vacancy.attributedDocument)
        }
        try Task.checkCancellation()
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages, didRenderPage: didRenderPage)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
        try Task.checkCancellation()
        try data.write(to: destination, options: .atomic)
    }

    func exportStatistics(report: VacancyStatisticsReport, destination: URL) throws {
        try Task.checkCancellation()
        let pages = try autoreleasepool {
            try FavoriteVacanciesPDFExporter.pages(for: report.attributedDocument())
        }
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
        try Task.checkCancellation()
        try data.write(to: destination, options: .atomic)
    }

    /// Writes the prepared parts as new files; see PDFNewFileWriter.
    func writePrepared(names: [String], directory: URL) throws -> [URL] {
        guard let parts = preparedParts else {
            throw FavoriteVacanciesPDFExporter.ExportError.missingPreparedExport
        }
        preparedParts = nil
        return try PDFNewFileWriter.write(parts.map(\.data), names: names, in: directory)
    }
}

@MainActor
final class FavoriteVacanciesPDFExporter: FavoriteVacanciesPDFExporting {
    nonisolated static let maximumPagesPerFile = 100

    struct Page: @unchecked Sendable {
        let content: NSAttributedString
    }

    enum ExportError: LocalizedError {
        case cannotCreatePDF
        case invalidPDF(String)
        case missingPreparedExport
        case noAvailableFileName

        var errorDescription: String? {
            switch self {
            case .cannotCreatePDF: return "Не удалось сформировать PDF-документ."
            case .invalidPDF(let name): return "Не удалось проверить PDF «\(name)»."
            case .missingPreparedExport: return "Не удалось подготовить PDF-документ."
            case .noAvailableFileName: return "Не удалось подобрать свободное имя PDF. Выберите другой каталог."
            }
        }
    }

    private let worker = PDFExportWorker()
    private let chooseDirectory: () -> URL?
    private let now: () -> Date
    init(
        chooseDirectory: (() -> URL?)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.chooseDirectory = chooseDirectory ?? { FavoriteVacanciesPDFExporter.chooseExportDirectory() }
        self.now = now
    }

    func export(
        vacancies: [VacancySearchResult],
        progress: @escaping @MainActor @Sendable (FavoritePDFExportProgress) -> Void
    ) async throws -> FavoritePDFExportOutcome {
        let exportStartedAt = now()
        do {
            let prepared = try await worker.prepare(
                vacancies: try await PDFVacanciesSnapshot.make(values: vacancies),
                progress: progress
            )
            guard let directory = chooseDirectory() else {
                await worker.discardPreparedExport()
                return .cancelled
            }

            let names = (0..<prepared.partCount).map {
                Self.fileName(part: $0 + 1, totalParts: prepared.partCount, exportStartedAt: exportStartedAt)
            }
            let destinations = try await worker.writePrepared(names: names, directory: directory)
            return .exported(fileCount: destinations.count, pageCount: prepared.pageCount)
        } catch {
            await worker.discardPreparedExport()
            throw error
        }
    }

    static func configureDirectoryPanel(_ panel: NSOpenPanel) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Экспортировать"
    }

    static func chooseExportDirectory() -> URL? {
        let panel = NSOpenPanel()
        configureDirectoryPanel(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    nonisolated static func fileName(
        part: Int,
        totalParts: Int,
        exportStartedAt: Date = Date()
    ) -> String {
        VacancyPDFDefaults.favoritesFileName(
            part: part,
            totalParts: totalParts,
            exportStartedAt: exportStartedAt
        )
    }

    nonisolated static func validatePDF(at url: URL, expectedPages: Int) throws {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw ExportError.invalidPDF(url.lastPathComponent)
        }
        try validatePDF(document, expectedPages: expectedPages, name: url.lastPathComponent)
    }

    nonisolated static func validatePDF(data: Data, expectedPages: Int) throws {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw ExportError.invalidPDF("PDF")
        }
        try validatePDF(document, expectedPages: expectedPages, name: "PDF")
    }

    private nonisolated static func validatePDF(
        _ document: CGPDFDocument,
        expectedPages: Int,
        name: String
    ) throws {
        guard expectedPages > 0,
              document.numberOfPages == expectedPages,
              expectedPages > maximumPagesPerFile || document.numberOfPages <= maximumPagesPerFile,
              (1...document.numberOfPages).allSatisfy({ pageNumber in
                  guard let page = document.page(at: pageNumber) else { return false }
                  return PDFVisualContentValidator.pageHasVisibleInk(page)
              }) else {
            throw ExportError.invalidPDF(name)
        }
    }

    /// Lays the whole document out once, in a single container of unbounded height, and
    /// cuts pages at line boundaries by vertical position: linear in the document length.
    /// A paragraph that starts on a page and would cross its end moves to the next page;
    /// a whitespace-only tail joins the previous page instead of becoming a blank page.
    nonisolated static func pages(for attributedText: NSAttributedString) -> [Page] {
        guard attributedText.length > 0 else { return [Page(content: attributedText)] }
        let contentWidth = VacancyPDFDefaults.paperSize.width - VacancyPDFDefaults.horizontalMargin * 2
        let pageHeight = VacancyPDFDefaults.paperSize.height - VacancyPDFDefaults.verticalMargin * 2
            - VacancyPDFDefaults.paginationBottomSafetyMargin

        let lines: [(start: Int, minY: CGFloat, maxY: CGFloat)] = autoreleasepool {
            let textStorage = NSTextStorage(attributedString: attributedText)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            var result: [(start: Int, minY: CGFloat, maxY: CGFloat)] = []
            layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) {
                rect, _, _, glyphRange, _ in
                let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                result.append((characters.location, rect.minY, rect.maxY))
            }
            return result
        }
        guard !lines.isEmpty else { return [Page(content: attributedText)] }

        let source = attributedText.string as NSString
        var pageStarts = [0]
        var index = 1
        while index < lines.count {
            let first = pageStarts[pageStarts.count - 1]
            guard lines[index].maxY - lines[first].minY > pageHeight else {
                index += 1
                continue
            }
            var next = index
            let paragraph = source.paragraphRange(for: NSRange(location: lines[index].start, length: 0))
            if paragraph.location > lines[first].start {
                while next > first + 1, lines[next].start > paragraph.location { next -= 1 }
            }
            pageStarts.append(next)
            index = next + 1
        }

        var pages: [Page] = []
        for (position, lineIndex) in pageStarts.enumerated() {
            let start = lines[lineIndex].start
            let end = position + 1 < pageStarts.count ? lines[pageStarts[position + 1]].start : attributedText.length
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            if let previous = pages.last,
               source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let merged = NSMutableAttributedString(attributedString: previous.content)
                merged.append(attributedText.attributedSubstring(from: range))
                pages[pages.count - 1] = Page(content: merged)
            } else {
                pages.append(Page(content: attributedText.attributedSubstring(from: range)))
            }
        }
        return pages.isEmpty ? [Page(content: attributedText)] : pages
    }

    nonisolated static func pdfData(
        for pages: [Page],
        didRenderPage: (@Sendable (Int) -> Void)? = nil
    ) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: VacancyPDFDefaults.paperSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.cannotCreatePDF
        }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            context.beginPDFPage(nil)
            context.saveGState()
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)
            context.translateBy(x: 0, y: VacancyPDFDefaults.paperSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            page.content.draw(
                with: NSRect(
                    x: VacancyPDFDefaults.horizontalMargin, y: VacancyPDFDefaults.verticalMargin,
                    width: VacancyPDFDefaults.paperSize.width - VacancyPDFDefaults.horizontalMargin * 2,
                    height: VacancyPDFDefaults.paperSize.height - VacancyPDFDefaults.verticalMargin * 2
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
            didRenderPage?(index)
        }
        context.closePDF()
        return data as Data
    }
}

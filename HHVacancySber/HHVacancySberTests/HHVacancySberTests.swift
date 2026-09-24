import AppKit
import Foundation
import PDFKit
import XCTest
import SwiftUI
@testable import HHVacancySber

final class HHVacancySberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testTechnologyClassificationRecognizesRequestedFamilies() {
        let titles = [
            "Backend-разработчик", "Разработчик 1С", "QA Engineer", "SRE инженер",
            "Информационные и коммуникационные технологии", "Архитектор решений",
            "Архитектура решений", "Технический писатель", "UX/UI-дизайнер",
            "Менеджер продукта", "Финансовый аналитик", "HR-аналитика", "Риск-аналитика",
            "BI-разработка", "Инженерия данных", "Data Governance", "ETL-разработчик",
            "Машинное обучение", "LLM-приложения", "RAG-системы", "Edge AI",
            "Промышленная автоматизация", "Геоинформационные системы", "Биоинформатика",
            "Методология разработки", "Low-code разработчик", "C++ developer", "HR-tech",
            "Пентестер", "Системный администратор", "Product Owner", "Интернет"
        ]
        for title in titles {
            XCTAssertTrue(VacancyTechnologyClassifier.matches(title: title), title)
        }
    }

    func testTechnologyClassificationAvoidsUnrelatedWordsAndOfficeRequirements() {
        for title in ["Кассир", "Кредитный специалист", "Водитель", "Архитектор зданий",
                      "Аудитор", "Менеджер по продажам", "Биолог", "Администратор офиса"] {
            XCTAssertFalse(VacancyTechnologyClassifier.matches(
                title: title, context: "Работа в цифровой команде. Пользователь ПК, Excel, интернет и CRM."
            ), title)
        }
        XCTAssertTrue(VacancyTechnologyClassifier.matches(title: "Эксперт", roles: ["Программист, разработчик"]))
        XCTAssertTrue(VacancyTechnologyClassifier.matches(title: "Инженер", context: "Разработка RAG-системы и векторный поиск"))
        XCTAssertFalse(VacancyTechnologyClassifier.matches(title: "Repair specialist"))
    }

    func testInformationSecurityClassificationCoversRequestedDisciplines() {
        let disciplines = """
        информационная безопасность; кибербезопасность; защита информации; компьютерная безопасность
        техническая защита информации; организационная защита информации; правовая защита информации; инженерно-техническая защита
        защита информации в автоматизированных системах; защита информации в компьютерных системах и сетях; защита информации в телекоммуникационных системах и сетях
        безопасность компьютерных систем и сетей; информационно-аналитические системы безопасности; безопасность информационных технологий в правоохранительной сфере
        разработка средств защиты информации; производство средств защиты информации; внедрение средств защиты информации; администрирование средств защиты информации
        эксплуатация систем защиты информации; проектирование систем защиты информации; архитектура информационной безопасности; управление информационной безопасностью
        стратегия информационной безопасности; методология информационной безопасности; политики и регламенты информационной безопасности; управление рисками информационной безопасности
        комплаенс информационной безопасности; аудит информационной безопасности; оценка соответствия требованиям по защите информации; оценка защищённости; анализ угроз; моделирование угроз
        анализ уязвимостей; управление уязвимостями; тестирование на проникновение; анализ защищённости; этичный хакинг; red team; blue team; purple team; bug bounty; исследование уязвимостей
        безопасность приложений (AppSec); безопасная разработка; DevSecOps; безопасный SDLC; анализ исходного кода; динамическое тестирование приложений; анализ состава программного обеспечения
        безопасность кода; безопасность API; безопасность веб-приложений; защита веб-приложений (WAF); безопасность мобильных приложений; безопасность контейнеров и оркестрации
        безопасность CI/CD; облачная безопасность; сетевая безопасность; безопасность периметра; межсетевое экранирование; сегментация сетей; обнаружение и предотвращение вторжений
        анализ сетевого трафика; NDR; защита от DDoS; безопасность беспроводных сетей; безопасность электронной почты; антифишинг; защита конечных точек; антивирусная защита; EDR; XDR; песочницы
        защита от вредоносного кода; анализ вредоносного программного обеспечения; реверс-инжиниринг вредоносного кода; мониторинг информационной безопасности
        центр мониторинга и реагирования (SOC); управление событиями информационной безопасности (SIEM); оркестрация и автоматизация реагирования (SOAR)
        управление инцидентами информационной безопасности; реагирование на инциденты; расследование инцидентов; цифровая криминалистика; компьютерно-техническая экспертиза
        threat hunting; разведка киберугроз; ГосСОПКА; обнаружение и предупреждение компьютерных атак; управление идентификацией и доступом (IAM)
        управление привилегированным доступом (PAM); аутентификация и авторизация; многофакторная аутентификация; управление секретами; Zero Trust
        защита данных; безопасность данных; конфиденциальность данных; предотвращение утечек данных (DLP); контроль доступа к базам данных; DCAP; классификация данных; маскирование данных; безопасность баз данных
        криптографическая защита информации; средства криптографической защиты; инфраструктура открытых ключей; удостоверяющие центры; электронная подпись; управление ключами; стеганография
        защита персональных данных; безопасность ИСПДн; защита коммерческой тайны; защита государственной тайны; режим секретности; противодействие техническим разведкам
        защита от утечки по техническим каналам; физическая защита информации; безопасность критической информационной инфраструктуры; безопасность объектов КИИ
        безопасность государственных информационных систем; безопасность АСУ ТП; промышленная кибербезопасность; аттестация объектов информатизации; сертификация средств защиты информации
        лицензирование деятельности по защите информации; соответствие требованиям ФСТЭК; соответствие требованиям ФСБ; соответствие требованиям Банка России
        ГОСТ Р ИСО/МЭК 27001; ГОСТ Р 57580; PCI DSS; информационная безопасность кредитно-финансовой сферы; антифрод; безопасность платежей
        безопасность искусственного интеллекта; безопасность моделей машинного обучения; защита от атак на ИИ; безопасность интернета вещей; безопасность виртуализации
        безопасность беспилотных и автономных систем; безопасность цепочки поставок программного обеспечения; непрерывность деятельности и аварийное восстановление
        киберустойчивость; резервное копирование и восстановление; управление конфигурациями безопасности; осведомлённость по информационной безопасности
        консалтинг по информационной безопасности; управление проектами информационной безопасности; взаимодействие с регуляторами
        """.components(separatedBy: CharacterSet(charactersIn: ";\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        XCTAssertGreaterThan(disciplines.count, 130)
        for discipline in disciplines {
            XCTAssertTrue(VacancyInformationSecurityClassifier.matches(title: discipline), discipline)
        }
        for title in ["Специалист по ИБ", "Инженер СЗИ/СКЗИ", "SOC-аналитик L2", "Архитектор AppSec",
                      "CISO", "Cybersecurity Engineer", "Information Security Officer", "Пентестер",
                      "Специалист по оценке защищенности", "Red‑Team инженер", "Инженер по\nзащите\u{00a0}информации"] {
            XCTAssertTrue(VacancyInformationSecurityClassifier.matches(title: title), title)
        }
    }

    func testInformationSecurityClassificationUsesSpecificContextAndRoleEvidence() {
        for context in ["Проектирование систем защиты информации", "Мониторинг событий SIEM и расследование атак",
                        "Проводить аудит информационной безопасности", "Внедрение DLP", "Работа с PCI DSS",
                        "Контроль соблюдения требований информационной безопасности", "Разработка политик ИБ"] {
            XCTAssertTrue(VacancyInformationSecurityClassifier.matches(title: "Главный эксперт", context: context), context)
        }
        XCTAssertTrue(VacancyInformationSecurityClassifier.matches(title: "Эксперт", roles: ["Специалист по информационной безопасности"]))
        XCTAssertTrue(VacancyInformationSecurityClassifier.matches(title: "Эксперт", roles: ["Инженер по резервному копированию"]))
    }

    func testInformationSecurityClassificationAvoidsGenericSecurityAndBoilerplate() {
        for title in ["Охранник", "Специалист по пожарной безопасности", "Инженер по промышленной безопасности",
                      "Специалист по экономической безопасности", "Java-разработчик", "Менеджер по продажам",
                      "Кассир", "Финансовый аудитор", "Дизайнер", "Социальный работник", "Pampas specialist",
                      "Сибирский региональный менеджер", "DevOps engineer"] {
            for context in ["Соблюдение требований информационной безопасности и охраны труда.",
                            "Соблюдать внутренние политики ИБ. Знание основ информационной безопасности.",
                            "Следовать правилам защиты персональных данных.",
                            "Резервное копирование и восстановление. Анализ исходного кода. Аутентификация и авторизация.",
                            "Взаимодействие с регуляторами. Соответствие требованиям Банка России.",
                            "Согласие на обработку персональных данных.", "Работа в SOCIETY, IPSUM, EDRIVE."] {
                XCTAssertFalse(VacancyInformationSecurityClassifier.matches(title: title, context: context), "\(title): \(context)")
            }
        }
    }

    func testInformationSecurityFieldSurvivesDetailAndFavoriteLifecycle() throws {
        let summary = HHVacancySummary(id: "security", name: "Инженер", employer: .init(name: "СБЕР"),
                                       salary: nil, area: nil, alternateURL: nil, url: nil, snippet: nil)
        let partial = HHVacancyDetails(id: summary.id, name: summary.name, employer: summary.employer,
                                       area: nil, salary: nil, alternateURL: nil, description: nil, archived: false)
        let before = VacancySearchResult(id: summary.id, summary: summary, details: partial)
        XCTAssertEqual(before.field, .general)
        let details = HHVacancyDetails(id: summary.id, name: summary.name, employer: summary.employer,
                                      area: nil, salary: nil, alternateURL: nil,
                                      description: "<p>Разработка <b>средств защиты информации</b> и сервисов на Java.</p>", archived: false)
        let loaded = VacancySearchResult(id: summary.id, summary: summary, details: details, isDetailLoaded: true)
        XCTAssertTrue(loaded.isTechnologyRelated)
        XCTAssertTrue(loaded.isInformationSecurityRelated)
        XCTAssertEqual(loaded.field, .informationSecurity)
        XCTAssertEqual(loaded.updatingDetailState(isLoading: true, errorMessage: nil).field, .informationSecurity)
        let favorite = FavoriteVacancyRecord(result: loaded, favoritedAt: Date(), updatedAt: Date())
        let restored = try JSONDecoder().decode(FavoriteVacancyRecord.self, from: JSONEncoder().encode(favorite))
        XCTAssertEqual(restored.searchResult.field, .informationSecurity)
        XCTAssertEqual(restored.searchResult.htmlDescription, loaded.htmlDescription)

        let plainIT = HHVacancyDetails(id: "it", name: "Java-разработчик", employer: nil, area: nil, salary: nil,
                                      alternateURL: nil, description: "Соблюдение требований информационной безопасности.", archived: false)
        XCTAssertEqual(VacancySearchResult(id: "it", summary: summary, details: plainIT).field, .technology)
        let snippet = HHVacancySummary(id: "snippet", name: "Эксперт", employer: nil, salary: nil, area: nil,
                                      alternateURL: nil, url: nil, snippet: .init(requirement: "Опыт внедрения SIEM", responsibility: nil))
        XCTAssertEqual(VacancySearchResult(id: "snippet", summary: snippet, details: partial).field, .informationSecurity)
    }

    func testVacancyFieldTextContrastsWithBothNativeBackgrounds() throws {
        func luminance(_ channels: [Double]) -> Double {
            zip(channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) },
                [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
        }
        for (appearance, scheme) in [(NSAppearance.Name.aqua, SwiftUI.ColorScheme.light), (.darkAqua, .dark)] {
            try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
                for background in [NSColor.textBackgroundColor, .windowBackgroundColor] {
                    let bg = background.usingColorSpace(.sRGB)!
                    let bgL = luminance([bg.redComponent, bg.greenComponent, bg.blueComponent])
                    for field in [VacancyField.technology, .informationSecurity] {
                        for tone in [VacancyFieldPalette.primary(for: field, scheme: scheme)!, VacancyFieldPalette.secondary(for: field, scheme: scheme)!] {
                            let rgb = tone.rgb
                            let fgL = luminance([Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { $0 / 255 })
                            XCTAssertGreaterThanOrEqual((max(bgL, fgL) + 0.05) / (min(bgL, fgL) + 0.05), 4.5, "\(field), \(scheme), \(tone.css)")
                        }
                    }
                }
            }
        }
    }

    func testEmbeddedApplicationTokenIsConfigured() {
        XCTAssertNotNil(HHAuthConfig.configuredAccessToken)
        XCTAssertFalse(HHAuthConfig.configuredAccessToken?.isEmpty ?? true)
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

    func testEmployerConfigurationMigratesUntouchedLegacyDefault() throws {
        let directory = temporaryDirectory()
        let bundled = directory.appendingPathComponent("employers.json")
        let legacyURL = directory.appendingPathComponent("employers.legacy-v1.json")
        let runtime = directory.appendingPathComponent("runtime.json")
        let legacy = EmployerConfiguration(version: 1, employers: [.init(id: "3529", name: "СБЕР", comment: "old")])
        let updated = EmployerConfiguration(version: 1, employers: legacy.employers + [.init(id: "11036409", name: "ПУЛЬС", comment: "new")])
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        try JSONEncoder().encode(legacy).write(to: runtime)
        try JSONEncoder().encode(updated).write(to: bundled)
        let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
        XCTAssertEqual(try store.loadOrCreate(), updated)
        XCTAssertEqual(try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: runtime)), updated)
        XCTAssertEqual(try store.loadOrCreate(), updated)
    }

    func testEmployerConfigurationPreservesEveryKindOfCustomization() throws {
        let directory = temporaryDirectory()
        let bundled = directory.appendingPathComponent("employers.json")
        let legacyURL = directory.appendingPathComponent("employers.legacy-v1.json")
        let runtime = directory.appendingPathComponent("runtime.json")
        let first = EmployerConfigurationEntry(id: "3529", name: "СБЕР", comment: "old")
        let second = EmployerConfigurationEntry(id: "2798", name: "СберРешения", comment: "old")
        let extra = EmployerConfigurationEntry(id: "11036409", name: "ПУЛЬС", comment: "new")
        try JSONEncoder().encode(EmployerConfiguration(version: 1, employers: [first, second])).write(to: legacyURL)
        try JSONEncoder().encode(EmployerConfiguration(version: 1, employers: [first, second, extra])).write(to: bundled)
        for entries in [[first], [second, first], [first, second, extra],
                        [.init(id: first.id, name: first.name, comment: "my comment"), second],
                        [.init(id: first.id, name: "my name", comment: first.comment), second]] {
            let custom = EmployerConfiguration(version: 1, employers: entries)
            let data = try JSONEncoder().encode(custom)
            try data.write(to: runtime)
            let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
            XCTAssertEqual(try store.loadOrCreate(), custom)
            XCTAssertEqual(try Data(contentsOf: runtime), data)
        }
    }

    func testEmployerConfigurationMigrationDoesNotReplaceInvalidRuntimeOrDefault() throws {
        let directory = temporaryDirectory()
        let bundled = directory.appendingPathComponent("employers.json")
        let legacyURL = directory.appendingPathComponent("employers.legacy-v1.json")
        let runtime = directory.appendingPathComponent("runtime.json")
        let legacy = try JSONEncoder().encode(EmployerConfiguration(version: 1, employers: [.init(id: "3529", name: "СБЕР", comment: "old")]))
        let invalid = Data("invalid JSON".utf8)
        try legacy.write(to: legacyURL)
        let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
        try legacy.write(to: bundled)
        try invalid.write(to: runtime)
        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertEqual(try Data(contentsOf: runtime), invalid)
        try legacy.write(to: runtime)
        try invalid.write(to: bundled)
        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertEqual(try Data(contentsOf: runtime), legacy)
    }

    func testEmployerConfigurationBundledPerimeterAndRealLegacyMigration() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "employers", withExtension: "json"))
        let legacyURL = try XCTUnwrap(Bundle.main.url(forResource: "employers.legacy-v1", withExtension: "json"))
        let current = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: bundled)).validated()
        let legacy = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: legacyURL)).validated()
        let ids = Set(current.employers.map(\.id))
        XCTAssertEqual(ids.count, 47)
        XCTAssertEqual(current.employers.first { $0.id == "11685629" }?.jointVenture, true)
        XCTAssertEqual(legacy.employers.count, 11)
        XCTAssertTrue(Set(legacy.employers.map(\.id)).isSubset(of: ids))
        XCTAssertTrue(Set(["11036409", "1071925", "64174", "1975264", "3513136", "2460946", "2367681", "3853446"]).isSubset(of: ids))
        XCTAssertTrue(ids.isDisjoint(with: ["2104700", "4659934", "5803001", "5267014", "1480834", "9074152", "1375441", "1829949", "2425896", "4585", "8620"]))
        let directory = temporaryDirectory()
        let runtime = directory.appendingPathComponent("runtime/employers.json")
        let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
        XCTAssertEqual(try store.loadOrCreate(), current)
        try Data(contentsOf: legacyURL).write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate(), current)
        let previousURL = try XCTUnwrap(Bundle.main.url(forResource: "employers.legacy-44", withExtension: "json"))
        let previous = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: previousURL)).validated()
        XCTAssertEqual(previous.employers.count, 44)
        try Data(contentsOf: previousURL).write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate(), current)
        XCTAssertEqual(try store.loadOrCreate(), current)

        let previous45URL = try XCTUnwrap(Bundle.main.url(forResource: "employers.legacy-45", withExtension: "json"))
        let previous45 = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: previous45URL)).validated()
        XCTAssertEqual(previous45.employers.count, 45)
        XCTAssertEqual(Array(current.employers.prefix(45)), previous45.employers)
        try Data(contentsOf: previous45URL).write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate(), current)
        XCTAssertEqual(try store.loadOrCreate(), current)

        var customEntries = previous45.employers
        let first = customEntries[0]
        customEntries[0] = .init(id: first.id, name: first.name, comment: "user edit")
        let custom = EmployerConfiguration(version: 1, employers: customEntries)
        let customData = try JSONEncoder().encode(custom)
        try customData.write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate(), custom)
        XCTAssertEqual(try Data(contentsOf: runtime), customData)
    }

    func testEmployerConfigurationJointVentureMetadataRoundTrips() throws {
        let legacy = Data(#"{"id":"3529","name":"Sber","comment":"old"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(EmployerConfigurationEntry.self, from: legacy).jointVenture)
        let entry = EmployerConfigurationEntry(id: "11685629", name: "Gistech", comment: "JV", jointVenture: true)
        let encoded = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(EmployerConfigurationEntry.self, from: encoded), entry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["joint_venture"] as? Bool, true)
        XCTAssertNil(json["jointVenture"])
    }

    func testPersistentStoresShareCanonicalApplicationSupportDirectory() {
        let employerURL = EmployerConfigurationStore().fileURL
        let areaURL = AreaDirectoryStore().fileURL
        let favoritesURL = FavoriteVacancyStore().fileURL
        let directory = employerURL.deletingLastPathComponent()

        XCTAssertEqual(directory.lastPathComponent, ApplicationSupportLocation.directoryName)
        XCTAssertEqual(areaURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(favoritesURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(employerURL.lastPathComponent, "employers.json")
        XCTAssertEqual(areaURL.lastPathComponent, "areas.json")
        XCTAssertEqual(favoritesURL.lastPathComponent, "favorites.json")
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

    @MainActor
    func testUnsupportedFavoritesSchemaIsNotOverwrittenByArchiveCheck() async throws {
        let url = temporaryDirectory().appendingPathComponent("favorites.json")
        let unsupported = Data(#"{"version":99,"favorites":[]}"#.utf8)
        try unsupported.write(to: url)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: FavoriteVacancyStore(fileURL: url)
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(try Data(contentsOf: url), unsupported)
        XCTAssertNotNil(model.favoritesWarning)
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
        XCTAssertTrue(values.isComplete)
        XCTAssertEqual(values.vacancies.count, 2_001)
        XCTAssertEqual(Set(values.vacancies.map(\.id)).count, 2_001)
    }

    func testCollectorRereadsShortLeafOnceThenKeepsPartialResultWithIssue() async throws {
        let client = MockAPIClient(mode: .mismatch)
        let result = try await VacancyCollectionService(client: client).collect(
            employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
            areas: try AreaDirectoryIndex(root: Self.areaTree),
            progress: { _ in }
        )

        let requestCount = await client.searchRequestCount
        XCTAssertEqual(result.vacancies.map(\.id), ["only-one"])
        XCTAssertEqual(result.issues, [.init(employerID: "3529", employerName: "СБЕР", expected: 2, actual: 1, failures: [])])
        XCTAssertEqual(result.issues.first?.message, "СБЕР – ожидалось 2, получено 1")
        XCTAssertEqual(requestCount, 2)
    }

    func testCollectorKeepsOtherEmployersWhenOneEmployerFails() async throws {
        let client = EmployerScriptedClient(behaviors: ["1": .vacancies(3), "2": .failure])
        let result = try await VacancyCollectionService(client: client).collect(
            employers: [.init(id: "1", name: "Первый", comment: "test"), .init(id: "2", name: "Второй", comment: "test")],
            areas: try AreaDirectoryIndex(root: Self.areaTree),
            progress: { _ in }
        )

        XCTAssertEqual(result.vacancies.count, 3)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.issues.map(\.employerID), ["2"])
        XCTAssertNil(result.issues.first?.expected)
        XCTAssertEqual(result.issues.first?.failures.count, 1)
    }

    func testCollectorKeepsPagesReadBeforeLeafFailure() async throws {
        let client = EmployerScriptedClient(behaviors: ["1": .failAfterFirstPage(150)])
        let result = try await VacancyCollectionService(client: client).collect(
            employers: [.init(id: "1", name: "Первый", comment: "test")],
            areas: try AreaDirectoryIndex(root: Self.areaTree),
            progress: { _ in }
        )

        XCTAssertEqual(result.vacancies.count, 100)
        XCTAssertEqual(result.issues.first?.expected, 150)
        XCTAssertEqual(result.issues.first?.actual, 100)
        XCTAssertEqual(result.issues.first?.failures.count, 1)
        XCTAssertTrue(result.issues.first?.failures.first?.contains("стр. 2") == true)
    }

    func testCollectorThrowsWhenNothingWasReadBecauseOfFailures() async throws {
        let client = EmployerScriptedClient(behaviors: ["1": .failure, "2": .failure])
        do {
            _ = try await VacancyCollectionService(client: client).collect(
                employers: [.init(id: "1", name: "Первый", comment: "test"), .init(id: "2", name: "Второй", comment: "test")],
                areas: try AreaDirectoryIndex(root: Self.areaTree),
                progress: { _ in }
            )
            XCTFail("Expected the transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
    }

    func testCollectorStopsOnAccessRestriction() async throws {
        let client = EmployerScriptedClient(behaviors: ["1": .vacancies(3), "2": .forbidden, "3": .vacancies(1)])
        do {
            _ = try await VacancyCollectionService(client: client).collect(
                employers: ["1", "2", "3"].map { .init(id: $0, name: "Работодатель \($0)", comment: "test") },
                areas: try AreaDirectoryIndex(root: Self.areaTree),
                progress: { _ in }
            )
            XCTFail("Expected forbidden")
        } catch let error as HHAPIError {
            XCTAssertEqual(error, .forbidden(requestID: nil))
        }
        let requested = await client.requestedEmployerIDs
        XCTAssertFalse(requested.contains("3"))
    }

    @MainActor
    func testPartialSearchShowsReceivedVacanciesWithWarningAndBypassesCache() async {
        let client = EmployerScriptedClient(behaviors: ["1": .vacancies(2), "2": .failure])
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [
                .init(id: "1", name: "Первый", comment: "test"), .init(id: "2", name: "Второй", comment: "test")
            ]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )

        await model.search()
        XCTAssertEqual(model.results.count, 2)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.collectionWarning?.hasPrefix("Выгрузка неполная. Второй – вакансии не получены") == true)
        XCTAssertTrue(model.statusMessage?.hasPrefix("Готово с пропусками") == true)
        XCTAssertTrue(model.statisticsReportSnapshot().sourceNote.contains("работодателей с пропусками: 1"))

        let requestsAfterFirstSearch = await client.requestedEmployerIDs.count
        await model.search()
        let requestsAfterSecondSearch = await client.requestedEmployerIDs.count
        XCTAssertGreaterThan(requestsAfterSecondSearch, requestsAfterFirstSearch, "An incomplete result must not be served from cache")
    }

    func testCollectorSearchRequestCountForOneLeaf() async throws {
        let client = MockAPIClient(mode: .simple)
        let values = try await VacancyCollectionService(client: client).collect(
            employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
            areas: try AreaDirectoryIndex(root: Self.areaTree),
            progress: { _ in }
        )

        let requestCount = await client.searchRequestCount
        XCTAssertEqual(values.vacancies.count, 1)
        XCTAssertTrue(values.isComplete)
        XCTAssertEqual(requestCount, 1)
    }

    func testCollectorSearchRequestCountForPartitionedResult() async throws {
        let client = MockAPIClient(mode: .partitioned)
        let values = try await VacancyCollectionService(client: client).collect(
            employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
            areas: try AreaDirectoryIndex(root: .init(id: "113", name: "Россия", areas: [
                .init(id: "10", name: "Регион A"), .init(id: "20", name: "Регион B")
            ])),
            progress: { _ in }
        )

        let requestCount = await client.searchRequestCount
        XCTAssertEqual(values.vacancies.count, 2_001)
        XCTAssertTrue(values.isComplete)
        XCTAssertEqual(requestCount, 22)
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

    func testSemanticallyInvalidFreshAreaCacheIsRefreshed() async throws {
        let file = temporaryDirectory().appendingPathComponent("areas.json")
        let invalid = #"{"version":1,"fetchedAt":"2026-09-02T00:00:00Z","root":{"id":"113","name":"Россия","areas":[{"id":"1","name":"Москва","areas":[]},{"id":"1","name":"Дубликат","areas":[]}]}}"#
        try Data(invalid.utf8).write(to: file)
        let store = AreaDirectoryStore(
            fileURL: file,
            now: { Date(timeIntervalSince1970: 1_788_321_600) }
        )

        let snapshot = try await store.load(using: MockAPIClient(mode: .simple))

        XCTAssertNil(snapshot.warning)
        XCTAssertEqual(snapshot.index.subjects.map(\.id), ["1", "2", "66"])
    }

    func testAreaDirectoryCancellationNeverBecomesStaleSuccessOrUnavailable() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let instant = Date(timeIntervalSince1970: 1_788_200_000)
        let file = directory.appendingPathComponent("areas.json")
        _ = try await AreaDirectoryStore(fileURL: file, now: { instant }).load(using: MockAPIClient(mode: .simple))
        let original = try Data(contentsOf: file)
        for cached in [true, false] {
            let target = cached ? file : directory.appendingPathComponent("missing.json")
            let store = AreaDirectoryStore(fileURL: target, now: { instant.addingTimeInterval(AreaDirectoryStore.defaultTTL + 1) })
            do {
                _ = try await store.load(using: CancelledAreaClient())
                XCTFail("Cancellation must not return a stale snapshot")
            } catch is CancellationError {
                // Cancellation is not a failed directory lookup.
            } catch {
                XCTFail("Cancellation was replaced with \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("missing.json").path))
    }

    func testAreaDirectoryTaskCancellationDoesNotPublishLateResponse() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("areas.json")
        let started = expectation(description: "Area request started")
        let responseGate = TestAsyncSignal()
        let client = CancelledAreaClient(responseGate: responseGate, onRequest: { started.fulfill() })
        let task = Task { try await AreaDirectoryStore(fileURL: file).load(using: client) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await responseGate.signal()
        do {
            _ = try await task.value
            XCTFail("A late successful response must not complete a cancelled load")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFreshAreaTreeRemainsAvailableWhenCacheWriteFails() async throws {
        let directory = temporaryDirectory()
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("file blocks directory creation".utf8).write(to: blockedParent)
        let store = AreaDirectoryStore(
            fileURL: blockedParent.appendingPathComponent("areas.json")
        )

        let snapshot = try await store.load(using: MockAPIClient(mode: .simple))

        XCTAssertEqual(snapshot.index.subjects.map(\.id), ["1", "2", "66"])
        XCTAssertTrue(snapshot.warning?.contains("Не удалось сохранить кэш регионов") == true)
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

    func testLiveAPIUsesEmbeddedTokenAndRetrievesOneVacancyWithDetails() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HHVACANCYSBER_RUN_LIVE_API_TEST"] == "1",
            "Opt-in live check; set HHVACANCYSBER_RUN_LIVE_API_TEST=1."
        )
        let maximumRequestCount = 2
        var requestCount = 0
        let client = HHAPIClient(
            accessTokenProvider: HHDefaultAccessTokenProvider(),
            requestGate: HHRequestGate(minimumDelayNanoseconds: 0),
            maximumRateLimitRetries: 0,
            maximumTransientRetries: 0
        )

        requestCount += 1
        let response = try await client.searchVacancies(.init(employerID: "3529", perPage: 1))
        XCTAssertGreaterThan(response.found, 0)
        XCTAssertLessThanOrEqual(response.items.count, 1)
        let vacancy = try XCTUnwrap(response.items.first)
        XCTAssertFalse(vacancy.id.isEmpty)
        XCTAssertFalse(vacancy.name.isEmpty)

        requestCount += 1
        let details = try await client.vacancyDetails(id: vacancy.id)
        XCTAssertEqual(details.id, vacancy.id)
        XCTAssertFalse(details.name.isEmpty)
        XCTAssertLessThanOrEqual(requestCount, maximumRequestCount)
    }

    func testLiveAPITechnologyBadgeRecognizesExplicitTechnicalTitles() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HHVACANCYSBER_RUN_LIVE_TECHNOLOGY_TEST"] == "1",
            "Opt-in: set HHVACANCYSBER_RUN_LIVE_TECHNOLOGY_TEST=1. At most one search request."
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = HHAPIClient(session: session, requestGate: HHRequestGate(), maximumRateLimitRetries: 0, maximumTransientRetries: 0)

        // One bounded production request; no paging, detail fetching or retry on errors.
        let response = try await client.searchVacancies(.init(employerID: "3529", perPage: 20))
        XCTAssertLessThanOrEqual(response.items.count, 20)
        // Independent, intentionally narrow oracle, not the production classifier:
        // these job titles unambiguously belong to the requested technology group.
        let technicalTitle = try NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:разработчик[а-я]*|программист[а-я]*|тестировщик[а-я]*|devops|sre|frontend|backend|fullstack)(?![\p{L}\p{N}])"#
        )
        let candidates = response.items.filter { vacancy in
            technicalTitle.firstMatch(in: vacancy.name, range: NSRange(vacancy.name.startIndex..., in: vacancy.name)) != nil
        }
        try XCTSkipIf(candidates.isEmpty, "No explicit technical titles in this live sample; no additional requests made.")
        for summary in candidates {
            let result = VacancySearchResult(
                id: summary.id,
                summary: summary,
                details: HHVacancyDetails(
                    id: summary.id, name: summary.name, employer: summary.employer,
                    area: summary.area, salary: summary.salary,
                    alternateURL: summary.alternateURL, description: nil
                )
            )
            XCTAssertTrue(result.isTechnologyRelated, "Explicit technical title must receive the technology badge (vacancy ID: \(summary.id)).")
            XCTAssertTrue(result.updatingDetailState(isLoading: true, errorMessage: nil).isTechnologyRelated)
        }
    }

    @MainActor
    func testLiveCancellationWhenEmployerFilterHidesDetails() async throws {
        try await checkLiveDetailCancellation(transition: .employer)
    }

    @MainActor
    func testLiveCancellationWhenRegionFilterHidesDetails() async throws {
        try await checkLiveDetailCancellation(transition: .region)
    }

    @MainActor
    func testLiveCancellationWhenFavoritesModeHidesDetails() async throws {
        try await checkLiveDetailCancellation(transition: .favorites)
    }

    @MainActor
    private func checkLiveDetailCancellation(transition: LiveCancellationTransition) async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HHVACANCYSBER_RUN_LIVE_CANCELLATION_TESTS"] == "1",
            "Opt-in live cancellation group; at most four GET requests for all three tests."
        )
        let run = LiveCancellationRun.shared
        try XCTSkipIf(run.stopped, "Live group stopped after an earlier API or transport failure; no further requests.")
        defer {
            let attachment = XCTAttachment(string: run.journal)
            attachment.name = "Live cancellation request journal"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let rows = try await run.searchRows()
        try XCTSkipIf(rows.count < 3, "Need three distinct live vacancies for three detail requests; no extra search.")
        let source = rows[transition.rawValue]
        let received = expectation(description: "Real detail response received before publication")
        let cancelled = expectation(description: "Hidden card detail Task is cancelled")
        let resume = TestAsyncSignal()
        let fixture = FixedSummaryAPIClient(rows: rows, detailLoader: { id in
            let details = try await run.detail(id: id)
            received.fulfill()
            // Hold the genuine response at the client boundary; do not fabricate a
            // response or cancel the transport ourselves. The ViewModel owns cancellation.
            await resume.wait()
            if Task.isCancelled { cancelled.fulfill() }
            return details
        })
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = VacancySearchViewModel(
            apiClient: fixture,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "live fixture")]),
            areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json"))
        )
        await model.search()
        let sourceIndex = try XCTUnwrap(model.results.firstIndex { $0.id == source.id })
        XCTAssertFalse(model.results[sourceIndex].isDetailLoaded)
        model.toggleExplanation(for: source.id)
        await fulfillment(of: [received], timeout: 25)
        // API errors stop the shared group, including later XCTest cases.
        guard !run.stopped else {
            await resume.signal()
            XCTFail("Live request failed; inspect the status-only journal.")
            return
        }
        XCTAssertTrue(model.results[sourceIndex].isDetailLoading)
        XCTAssertEqual(model.expandedVacancyID, source.id)
        switch transition {
        case .employer: model.selectedEmployerID = "2798"
        case .region: model.selectedRegionID = "subject:66"
        case .favorites: model.displayMode = .favorites
        }
        XCTAssertNil(model.expandedVacancyID)
        XCTAssertFalse(model.displayedResults.contains { $0.id == source.id })
        await resume.signal()
        await fulfillment(of: [cancelled], timeout: 2)
        for _ in 0..<1000 where model.results[sourceIndex].isDetailLoading {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.results[sourceIndex].isDetailLoading)
        XCTAssertFalse(model.results[sourceIndex].isDetailLoaded)
        XCTAssertNil(model.results[sourceIndex].detailErrorMessage)
        XCTAssertNil(model.errorMessage)
        XCTAssertLessThanOrEqual(run.requestCount, 4)
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

    func testRateLimitRetriesTwiceThenReturnsSuccessfulResponse() async throws {
        var requests = 0
        let client = makeHTTPClient { _ in
            requests += 1
            if requests < 3 { return (429, ["Retry-After": "0"], Data(#"{"errors":[]}"#.utf8)) }
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        do {
            let response = try await client.searchVacancies(.init(employerID: "3529"))
            XCTAssertEqual(response.found, 0)
        } catch {
            XCTFail("Expected successful response after bounded retries: \(error)")
        }
        XCTAssertEqual(requests, 3)
    }

    @MainActor
    func testFavoritePDFCollisionCreatesSuffixAndPreservesExistingFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_788_400_000)
        let name = FavoriteVacanciesPDFExporter.fileName(part: 1, totalParts: 1, exportStartedAt: date)
        let original = directory.appendingPathComponent(name)
        let originalData = Data("existing user file".utf8)
        try originalData.write(to: original)
        let exporter = FavoriteVacanciesPDFExporter(chooseDirectory: { directory }, now: { date })
        let outcome = try await exporter.export(vacancies: [makePDFVacancy(id: "suffix")]) { _ in }
        XCTAssertEqual(outcome, .exported(fileCount: 1, pageCount: 1))
        XCTAssertEqual(try Data(contentsOf: original), originalData)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pdf" && $0.lastPathComponent != name }
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(try XCTUnwrap(files.first).lastPathComponent.hasSuffix("_2.pdf"))
        XCTAssertNotNil(PDFDocument(url: try XCTUnwrap(files.first)))
        // No hidden staging, backup or recovery directories are left next to the PDFs.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testPDFWriterUsesFreeSuffixesForOccupiedAndDuplicateNamesWithinUTF8Limit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("keep".utf8).write(to: directory.appendingPathComponent("report.pdf"))
        try Data("keep too".utf8).write(to: directory.appendingPathComponent("report_2.pdf"))
        let written = try PDFNewFileWriter.write(
            [Data("a".utf8), Data("b".utf8)], names: ["report.pdf", "report.pdf"], in: directory
        )
        XCTAssertEqual(written.map(\.lastPathComponent), ["report_3.pdf", "report_4.pdf"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("report.pdf")), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("report_2.pdf")), Data("keep too".utf8))
        XCTAssertEqual(try Data(contentsOf: written[1]), Data("b".utf8))

        let longName = PDFFileNameBuilder.fileName(base: String(repeating: "ёж🙂/", count: 300), fallback: "vacancy")
        let long = try PDFNewFileWriter.write([Data("1".utf8), Data("2".utf8)], names: [longName, longName], in: directory)
        let names = long.map(\.lastPathComponent)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertTrue(names.allSatisfy { $0.utf8.count <= 240 && !$0.contains("/") })
        XCTAssertTrue(names[1].hasSuffix("_2.pdf"))

        XCTAssertThrowsError(try PDFNewFileWriter.write(
            [Data()], names: ["report.pdf"], in: directory, maximumCandidates: 2
        )) { error in
            guard case FavoriteVacanciesPDFExporter.ExportError.noAvailableFileName = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPDFWriterRemovesItsFilesOnFailureOrCancellationAndKeepsExistingOnes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("part-2.pdf")
        try Data("user file".utf8).write(to: existing)

        XCTAssertThrowsError(try PDFNewFileWriter.write(
            [Data("1".utf8), Data("2".utf8)], names: ["part-1.pdf", "part-2.pdf"], in: directory,
            beforeEachFile: { index in if index == 1 { throw CocoaError(.fileWriteUnknown) } }
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["part-2.pdf"])

        let cancelled = Task {
            // Cancelled while the second file is written: the check before the third file stops the
            // batch and both files already written by this call are removed.
            try PDFNewFileWriter.write(
                [Data("1".utf8), Data("3".utf8), Data("4".utf8)], names: ["part-1.pdf", "part-3.pdf", "part-4.pdf"],
                in: directory,
                beforeEachFile: { index in if index == 1 { withUnsafeCurrentTask { $0?.cancel() } } }
            )
        }
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["part-2.pdf"])
        XCTAssertEqual(try Data(contentsOf: existing), Data("user file".utf8))
    }

    func testRateLimitWaitPreventsQueuedRequestsFromOvertakingRetry() async throws {
        let entered = expectation(description: "Retry owns gate")
        let release = TestAsyncSignal()
        let gate = HHRequestGate(minimumDelayNanoseconds: 0)
        var employers: [String] = []
        URLProtocolStub.handler = { request in
            let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .first { $0.name == "employer_id" }!.value!
            employers.append(id)
            if employers.count == 1 { return (429, [:], Data(#"{"errors":[]}"#.utf8)) }
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let client = HTTPClientFactory.make(requestGate: gate, retrySleep: { _ in
            entered.fulfill()
            await release.wait()
        })
        let first = Task { try await client.searchVacancies(.init(employerID: "3529")) }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { try await client.searchVacancies(.init(employerID: "2798")) }
        for _ in 0..<200 {
            if await gate.queuedRequestCount == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let queued = await gate.queuedRequestCount
        XCTAssertEqual(queued, 1)
        XCTAssertEqual(employers, ["3529"])
        await release.signal()
        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(employers, ["3529", "3529", "2798"])
    }

    func testRateLimitRetryStopsOnForbiddenCaptchaAndConfiguredCeiling() async {
        for (limit, terminal, captcha, expected) in [(99, 429, false, 3), (-1, 429, false, 1), (2, 403, false, 2), (2, 429, true, 1)] {
            var requests = 0
            URLProtocolStub.handler = { _ in
                requests += 1
                let body = captcha ? #"{"errors":[{"type":"captcha","value":"required"}]}"# : #"{"errors":[]}"#
                return (requests == 1 ? 429 : terminal, [:], Data(body.utf8))
            }
            let client = HTTPClientFactory.make(maximumRateLimitRetries: limit)
            do { _ = try await client.searchVacancies(.init(employerID: "3529")); XCTFail("Expected terminal failure") }
            catch { XCTAssertEqual(requests, expected) }
        }
    }

    func testRateLimitRetryBudgetAndServerDelayCeiling() async {
        for (header, expectedRequests) in [("0", 3), ("60", 3), ("61", 1), ("9999999999999999999999999999999999999999", 1)] {
            var requests = 0
            let client = makeHTTPClient { _ in
                requests += 1
                return (429, ["Retry-After": header], Data(#"{"errors":[]}"#.utf8))
            }
            do { _ = try await client.searchVacancies(.init(employerID: "3529")); XCTFail("Expected rate limit") }
            catch let error as HHAPIError {
                guard case .rateLimited = error else { return XCTFail("Expected rate limit") }
            } catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(requests, expectedRequests)
        }
    }

    func testRateLimitDelaySupportsHTTPDateAndNeverRetriesBeforeServerDelay() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: nil, now: now, attempt: 0), 1)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: "invalid", now: now, attempt: 1), 2)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: "-1", now: now, attempt: 0), 1)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: " 17 ", now: now, attempt: 0), 17)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: "Thu, 01 Jan 1970 00:00:17 GMT", now: now, attempt: 0), 17)
        XCTAssertEqual(HHAPIClient.rateLimitDelay(header: "Wed, 31 Dec 1969 23:59:59 GMT", now: now, attempt: 1), 2)
        XCTAssertNil(HHAPIClient.rateLimitDelay(header: "Thu, 01 Jan 1970 00:01:01 GMT", now: now, attempt: 0))
    }

    func testRateLimitRetryUsesExpectedBackoffAndCanBeDisabledForLiveBudget() async throws {
        let waits = RetryWaitRecorder()
        var requests = 0
        URLProtocolStub.handler = { _ in
            requests += 1
            if requests <= 2 { return (429, [:], Data(#"{"errors":[]}"#.utf8)) }
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let client = HTTPClientFactory.make(maximumRateLimitRetries: 99, retrySleep: { await waits.append($0) })
        _ = try await client.searchVacancies(.init(employerID: "3529"))
        let delays = await waits.values
        XCTAssertEqual(delays, [1_000_000_000, 2_000_000_000])
        XCTAssertEqual(requests, 3)
        requests = 0
        let noRetries = HTTPClientFactory.make(maximumRateLimitRetries: 0)
        do { _ = try await noRetries.searchVacancies(.init(employerID: "3529")); XCTFail("Expected rate limit") }
        catch { XCTAssertEqual(requests, 1) }
    }

    func testRateLimitWaitCancellationStopsRetriesAndReleasesSharedGate() async throws {
        let waiting = expectation(description: "Entered retry delay")
        var requests = 0
        URLProtocolStub.handler = { _ in
            requests += 1
            if requests == 1 { return (429, [:], Data(#"{"errors":[]}"#.utf8)) }
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let client = HTTPClientFactory.make(retrySleep: { _ in
            waiting.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
        })
        let task = Task { try await client.searchVacancies(.init(employerID: "3529")) }
        await fulfillment(of: [waiting], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(requests, 1)
        _ = try await client.searchVacancies(.init(employerID: "3529"))
        XCTAssertEqual(requests, 2)
    }

    func testAPIDoesNotRetryClientHTTPFailures() async {
        let failures: [(Int, HHAPIError)] = [
            (400, .requestFailed(statusCode: 400, message: nil)),
            (404, .requestFailed(statusCode: 404, message: nil)),
            (403, .forbidden(requestID: nil))
        ]
        for (status, expected) in failures {
            var requests = 0
            let client = makeHTTPClient { _ in
                requests += 1
                return (status, ["Retry-After": "17"], Data(#"{"errors":[]}"#.utf8))
            }
            await assertAPIError(client, equals: expected)
            XCTAssertEqual(requests, 1, "HTTP \(status) must finish without automatic retries")
        }
        var requests = 0
        let offline = makeHTTPClient { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        _ = try? await offline.searchVacancies(.init(employerID: "3529"))
        XCTAssertEqual(requests, 1, "Offline is not a transient failure")
    }

    func testAPIRetriesTransientFailuresTwiceThenReportsThem() async {
        for status in [500, 502, 503, 504] {
            var requests = 0
            let client = makeHTTPClient { _ in
                requests += 1
                return (status, [:], Data(#"{"errors":[]}"#.utf8))
            }
            await assertAPIError(client, equals: .requestFailed(statusCode: status, message: nil))
            XCTAssertEqual(requests, 3, "HTTP \(status) gets two bounded retries")
        }
        for code in [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost] {
            var requests = 0
            let client = makeHTTPClient { _ in
                requests += 1
                throw URLError(code)
            }
            do {
                _ = try await client.searchVacancies(.init(employerID: "3529"))
                XCTFail("Expected transport failure")
            } catch let error as URLError {
                XCTAssertEqual(error.code, code)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(requests, 3, "\(code) gets two bounded retries")
        }
    }

    func testAPITransientRetriesUseBackoffAndRecover() async throws {
        let waits = RetryWaitRecorder()
        var requests = 0
        URLProtocolStub.handler = { _ in
            requests += 1
            if requests == 1 { throw URLError(.timedOut) }
            if requests == 2 { return (502, [:], Data(#"{"errors":[]}"#.utf8)) }
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let client = HTTPClientFactory.make(retrySleep: { await waits.append($0) })
        let response = try await client.searchVacancies(.init(employerID: "3529"))
        let delays = await waits.values
        XCTAssertEqual(response.found, 0)
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(delays, [1_000_000_000, 2_000_000_000])
    }

    func testAPIServerRetryHonorsRetryAfterCeilingAndCanBeDisabled() async {
        var requests = 0
        var client = makeHTTPClient { _ in
            requests += 1
            return (503, ["Retry-After": "120"], Data(#"{"errors":[]}"#.utf8))
        }
        await assertAPIError(client, equals: .requestFailed(statusCode: 503, message: nil))
        XCTAssertEqual(requests, 1, "A server delay above 60 seconds is not waited out")

        requests = 0
        URLProtocolStub.handler = { _ in
            requests += 1
            return (502, [:], Data(#"{"errors":[]}"#.utf8))
        }
        client = HTTPClientFactory.make(maximumTransientRetries: 0)
        await assertAPIError(client, equals: .requestFailed(statusCode: 502, message: nil))
        XCTAssertEqual(requests, 1)
    }

    func testRequestGateCancelsQueuedWaiterBeforeActiveRequestFinishes() async throws {
        let gate = HHRequestGate(minimumDelayNanoseconds: 0)
        let activeStarted = expectation(description: "active started")
        let blocker = TestAsyncSignal()
        let active = Task {
            try await gate.perform {
                activeStarted.fulfill()
                await blocker.wait()
                return 1
            }
        }
        await fulfillment(of: [activeStarted], timeout: 2)
        let cancelled = expectation(description: "queued task cancelled without releasing active")
        let queued = Task {
            do {
                _ = try await gate.perform { XCTFail("Cancelled request executed"); return 2 }
                XCTFail("Expected cancellation")
            } catch is CancellationError { cancelled.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        for _ in 0..<1000 {
            if await gate.queuedRequestCount == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let before = await gate.queuedRequestCount
        XCTAssertEqual(before, 1)
        queued.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        let after = await gate.queuedRequestCount
        XCTAssertEqual(after, 0)
        await blocker.signal()
        _ = try await active.value
        await queued.value
        let next = try await gate.perform { 3 }
        XCTAssertEqual(next, 3)
    }

    func testRequestGateCancellationRaceReleasesEveryWaiterAndPreservesSerialization() async throws {
        let gate = HHRequestGate(minimumDelayNanoseconds: 0)
        let tracker = ConcurrentOperationTracker()
        for _ in 0..<10 {
            let tasks = (0..<20).map { index in
                Task {
                    try await gate.perform {
                        await tracker.begin()
                        await Task.yield()
                        await tracker.end()
                        return index
                    }
                }
            }
            for (index, task) in tasks.enumerated() where index.isMultiple(of: 2) { task.cancel() }
            for task in tasks { _ = await task.result }
        }
        let queued = await gate.queuedRequestCount
        let peak = await tracker.maximumConcurrentOperations
        XCTAssertEqual(queued, 0)
        XCTAssertEqual(peak, 1)
        let next = try await gate.perform { true }
        XCTAssertTrue(next)
    }

    func testRequestGateCancellationDuringPacingDoesNotRunOperation() async throws {
        let gate = HHRequestGate(minimumDelayNanoseconds: 500_000_000)
        _ = try await gate.perform { 1 }
        let task = Task { try await gate.perform { XCTFail("Must cancel during pacing"); return 2 } }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let next = try await gate.perform { 3 }
        XCTAssertEqual(next, 3)
    }

    func testRequestGateSerializesConcurrentOperations() async throws {
        let gate = HHRequestGate(minimumDelayNanoseconds: 0)
        let tracker = ConcurrentOperationTracker()

        async let first: Int = gate.perform {
            await tracker.begin()
            try await Task.sleep(nanoseconds: 100_000_000)
            await tracker.end()
            return 1
        }
        async let second: Int = gate.perform {
            await tracker.begin()
            try await Task.sleep(nanoseconds: 100_000_000)
            await tracker.end()
            return 2
        }

        _ = try await (first, second)
        let maximumConcurrentOperations = await tracker.maximumConcurrentOperations
        XCTAssertEqual(maximumConcurrentOperations, 1)
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
    func testFilterOptionsAreDeduplicatedSortedAndGroupCitiesBySubject() async {
        let model = makeFilterViewModel()
        await model.search()

        XCTAssertEqual(model.employerFilterOptions.map(\.id), ["all", "9999", "3529", "2798"])
        XCTAssertEqual(model.employerFilterOptions.map(\.title), [
            "Все работодатели", "Альфа Банк", "СБЕР", "СберРешения"
        ])
        XCTAssertEqual(Set(model.employerFilterOptions.map(\.id)).count, model.employerFilterOptions.count)

        XCTAssertEqual(model.regionFilterOptions.first, .init(id: "all", title: "Все регионы"))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: model.regionFilterOptions.map { ($0.id, $0.title) }), [
            "all": "Все регионы",
            "remote": "Удалённо",
            "unknown": "Регион не определён",
            "subject:1": "Москва",
            "subject:2": "Санкт-Петербург",
            "subject:66": "Свердловская область"
        ])
        XCTAssertEqual(Set(model.regionFilterOptions.map(\.id)).count, model.regionFilterOptions.count)
    }

    @MainActor
    func testDropdownSelectionsApplyEmployerRegionAndANDCombinations() async {
        let model = makeFilterViewModel()
        await model.search()

        model.selectedEmployerID = "3529"
        XCTAssertEqual(Set(model.displayedResults.map(\.id)), ["filter-moscow", "filter-ekb", "filter-unknown"])
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 3")

        model.selectedRegionID = "subject:66"
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-ekb"])
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 1")

        model.selectedEmployerID = "2798"
        XCTAssertTrue(model.displayedResults.isEmpty)
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 0")

        model.selectedRegionID = "remote"
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-remote"])

        model.selectedEmployerID = "all"
        model.selectedRegionID = "all"
        XCTAssertEqual(model.displayedResults.count, 5)
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 5")
    }

    @MainActor
    func testDropdownOptionsFollowFavoritesAndInvalidSelectionsReset() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleFavorite(id: "filter-remote")
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"

        model.displayMode = .favorites

        XCTAssertEqual(model.selectedEmployerID, "all")
        XCTAssertEqual(model.selectedRegionID, "all")
        XCTAssertEqual(model.employerFilterOptions.map(\.id), ["all", "2798"])
        XCTAssertEqual(model.regionFilterOptions.map(\.id), ["all", "remote"])
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-remote"])
    }

    @MainActor
    func testRemovingLastMatchingFavoriteResetsDropdowns() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleFavorite(id: "filter-remote")
        model.displayMode = .favorites
        model.selectedEmployerID = "2798"
        model.selectedRegionID = "remote"

        model.toggleFavorite(id: "filter-remote")

        XCTAssertEqual(model.selectedEmployerID, "all")
        XCTAssertEqual(model.selectedRegionID, "all")
        XCTAssertEqual(model.employerFilterOptions, [.init(id: "all", title: "Все работодатели")])
        XCTAssertEqual(model.regionFilterOptions, [.init(id: "all", title: "Все регионы")])
        XCTAssertTrue(model.displayedResults.isEmpty)
    }

    @MainActor
    func testChangingDropdownSelectionCollapsesAHiddenExpandedVacancy() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleExplanation(for: "filter-moscow")
        XCTAssertEqual(model.expandedVacancyID, "filter-moscow")

        model.selectedRegionID = "subject:66"

        XCTAssertNil(model.expandedVacancyID)
    }

    @MainActor
    func testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload() async throws {
        for hide in ["employer", "region", "favorites"] {
            let started = expectation(description: "detail suspended: \(hide)")
            let cancelled = expectation(description: "detail task cancelled: \(hide)")
            let resume = TestAsyncSignal()
            let client = MockAPIClient(mode: .simple, beforeFirstDetailResponse: {
                started.fulfill()
                await resume.wait()
                do { try Task.checkCancellation() }
                catch { cancelled.fulfill(); throw error }
            })
            let model = VacancySearchViewModel(
                apiClient: client,
                employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
                areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
            )
            await model.search()
            model.toggleExplanation(for: "3529-vacancy")
            await fulfillment(of: [started], timeout: 2)
            XCTAssertTrue(model.results[0].isDetailLoading)

            switch hide {
            case "employer": model.selectedEmployerID = "2798"
            case "region": model.selectedRegionID = "remote"
            default: model.displayMode = .favorites
            }
            XCTAssertNil(model.expandedVacancyID)
            await resume.signal()
            await fulfillment(of: [cancelled], timeout: 2)
            for _ in 0..<1000 where model.results[0].isDetailLoading {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertFalse(model.results[0].isDetailLoading)
            XCTAssertFalse(model.results[0].isDetailLoaded, hide)
            XCTAssertNil(model.results[0].detailErrorMessage)

            model.displayMode = .all
            model.selectedEmployerID = "all"
            model.selectedRegionID = "all"
            await model.loadVacancyDetails(id: "3529-vacancy")
            let requestCount = await client.detailRequestCount
            XCTAssertEqual(requestCount, 2, "Cancelled response must not populate the session cache")
            XCTAssertTrue(model.results[0].isDetailLoaded)
        }
    }

    @MainActor
    func testFilterChangeKeepingExpandedVacancyVisiblePreservesInFlightDetails() async throws {
        let started = expectation(description: "visible detail suspended")
        let resume = TestAsyncSignal()
        let client = MockAPIClient(mode: .simple, beforeFirstDetailResponse: {
            started.fulfill()
            await resume.wait()
            try Task.checkCancellation()
        })
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()
        model.toggleExplanation(for: "3529-vacancy")
        await fulfillment(of: [started], timeout: 2)
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        XCTAssertEqual(model.expandedVacancyID, "3529-vacancy")
        await resume.signal()
        for _ in 0..<1000 where model.results[0].isDetailLoading {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.results[0].isDetailLoading)
        XCTAssertTrue(model.results[0].isDetailLoaded)
        XCTAssertNil(model.results[0].detailErrorMessage)
        let requestCount = await client.detailRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testAllAndPersistedFavoritesAreAlwaysOrderedNewestFirst() async throws {
        let employerStore = TestEmployerStore(entries: [
            .init(id: "2798", name: "СберРешения", comment: "test"),
            .init(id: "3529", name: "СБЕР", comment: "test")
        ])
        let source = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await source.search()
        XCTAssertEqual(source.results.map(\.id), ["3529-vacancy", "2798-vacancy"])
        XCTAssertEqual(source.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])

        let older = try XCTUnwrap(source.results.first { $0.id == "2798-vacancy" })
        let newer = try XCTUnwrap(source.results.first { $0.id == "3529-vacancy" })
        let persisted = FavoriteVacancyStore(fileURL: temporaryDirectory().appendingPathComponent("favorites.json"))
        try persisted.save([
            .init(result: older, favoritedAt: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 200)),
            .init(result: newer, favoritedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        ])
        let relaunched = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: persisted
        )
        await relaunched.loadPersistenceIfNeeded()
        relaunched.displayMode = .favorites

        XCTAssertEqual(relaunched.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])
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
    func testCompletedRefreshIgnoresDetailResponseFromPreviousResults() async {
        let client = MockAPIClient(mode: .delayedArchive)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()

        let detail = Task { await model.loadVacancyDetails(id: "3529-vacancy") }
        while await client.detailRequestCount == 0 { await Task.yield() }
        await model.refreshVacancies()
        await detail.value

        XCTAssertFalse(model.results[0].isDetailLoaded)
    }

    @MainActor
    func testFailedRefreshDoesNotDiscardDetailLoadedWhileRefreshWasRunning() async {
        let client = MockAPIClient(mode: .delayedRefreshFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()

        let initialRequestCount = await client.searchRequestCount
        await client.enableDelayedSearchFailure()
        let refresh = Task { await model.refreshVacancies() }
        while await client.searchRequestCount == initialRequestCount { await Task.yield() }
        await model.loadVacancyDetails(id: "3529-vacancy")
        await refresh.value

        XCTAssertTrue(model.results[0].isDetailLoaded)
        XCTAssertEqual(model.results[0].plainTextDescription, "Полное описание")
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

    @MainActor
    func testArchiveCheckDoesNotPersistWhenNothingChanged() async {
        let store = SlowRecordingFavoriteStore()
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testArchiveCancellationPersistsCompletedUpdatesAndStopsRemainingRequests() async {
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let records = ["3529-ok", "3529-cancel", "3529-unreached"].enumerated().map { index, id in
            FavoriteVacancyRecord(result: statisticsVacancy(id: id, date: nil),
                favoritedAt: Date(timeIntervalSince1970: Double(3 - index)), updatedAt: .distantPast)
        }
        let store = SlowRecordingFavoriteStore(favorites: records)
        let client = MockAPIClient(mode: .archiveCancelled)
        let model = VacancySearchViewModel(apiClient: client, employerStore: TestEmployerStore(entries: []),
            favoritesStore: store, currentDate: { now })
        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()
        let requests = await client.requestedDetailIDs
        XCTAssertEqual(requests, ["3529-ok", "3529-cancel"])
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.lastSaved.first?.isArchived, true)
        XCTAssertEqual(store.lastSaved.first?.archiveCheckedAt, now)
        XCTAssertEqual(store.lastSaved, model.favorites)
        XCTAssertNil(model.favorites[1].archiveCheckedAt)
        await model.checkArchiveStatusesIfNeeded()
        let repeated = await client.requestedDetailIDs
        XCTAssertEqual(repeated, ["3529-ok", "3529-cancel", "3529-cancel"])
        XCTAssertEqual(store.saveCount, 1)
    }

    @MainActor
    func testArchiveTaskCancellationStillSavesEarlierCompletedCheck() async throws {
        let records = ["3529-first", "3529-second"].enumerated().map { index, id in
            FavoriteVacancyRecord(result: statisticsVacancy(id: id, date: nil),
                favoritedAt: Date(timeIntervalSince1970: Double(2 - index)), updatedAt: .distantPast)
        }
        let store = SlowRecordingFavoriteStore(favorites: records)
        let client = MockAPIClient(mode: .delayedArchive)
        let model = VacancySearchViewModel(apiClient: client, employerStore: TestEmployerStore(entries: []), favoritesStore: store)
        let task = Task { await model.checkArchiveStatusesIfNeeded() }
        for _ in 0..<1000 {
            if await client.requestedDetailIDs.count == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        await task.value
        await model.waitForPendingFavoritesSaves()
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertNotNil(store.lastSaved.first?.archiveCheckedAt)
        XCTAssertNil(store.lastSaved.last?.archiveCheckedAt)
        XCTAssertEqual(store.lastSaved, model.favorites)
    }

    @MainActor
    func testArchiveCheckRevalidatesFavoriteIndexAfterRemovalDuringRequest() async throws {
        let blocked = expectation(description: "first archive request suspended")
        let records = ["first", "second"].map { id in
            FavoriteVacancyRecord(
                result: statisticsVacancy(id: id, date: nil),
                favoritedAt: .distantPast,
                updatedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: records)
        let client = SuspendedEnrichmentClient(onFirstRequest: { blocked.fulfill() })
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: []),
            favoritesStore: store
        )
        await model.loadPersistenceIfNeeded()

        let check = Task { await model.checkArchiveStatusesIfNeeded() }
        await fulfillment(of: [blocked], timeout: 2)
        model.toggleFavorite(id: "first")
        await client.resumeFirstRequest()
        await check.value
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(model.favorites.map(\.id), ["second"])
        XCTAssertEqual(model.favorites.first?.isArchived, true)
        XCTAssertNotNil(model.favorites.first?.archiveCheckedAt)
        XCTAssertEqual(store.lastSaved, model.favorites)
    }

    @MainActor
    func testArchiveCancellationBeforeAnyUpdateDoesNotWriteFavorites() async {
        let record = FavoriteVacancyRecord(result: statisticsVacancy(id: "3529-cancel", date: nil),
            favoritedAt: .distantPast, updatedAt: .distantPast)
        let store = SlowRecordingFavoriteStore(favorites: [record])
        let model = VacancySearchViewModel(apiClient: MockAPIClient(mode: .archiveCancelled),
            employerStore: TestEmployerStore(entries: []), favoritesStore: store)
        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(store.lastSaved, [record])
        XCTAssertEqual(model.favorites, [record])
    }

    @MainActor
    func testArchiveCheckPersistsAnUpdatedStatus() async {
        let vacancy = summary(id: "3529-archived", areaID: "1", areaName: "Москва")
        let result = VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id,
                name: vacancy.name,
                employer: vacancy.employer,
                area: vacancy.area,
                salary: nil,
                alternateURL: nil,
                description: nil,
                archived: false
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
        let record = FavoriteVacancyRecord(
            result: result,
            favoritedAt: .distantPast,
            updatedAt: .distantPast,
            archiveCheckedAt: .distantPast
        )
        let store = SlowRecordingFavoriteStore(favorites: [record])
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store,
            currentDate: { now }
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.lastSaved.first?.archiveCheckedAt, now)
    }

    @MainActor
    func testConcurrentArchiveChecksUseOneRequest() async {
        let vacancy = summary(id: "3529-concurrent", areaID: "1", areaName: "Москва")
        let result = VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id,
                name: vacancy.name,
                employer: vacancy.employer,
                area: vacancy.area,
                salary: nil,
                alternateURL: nil,
                description: nil,
                archived: false
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
        let record = FavoriteVacancyRecord(
            result: result,
            favoritedAt: .distantPast,
            updatedAt: .distantPast,
            archiveCheckedAt: .distantPast
        )
        let store = SlowRecordingFavoriteStore(favorites: [record])
        let client = MockAPIClient(mode: .delayedArchive)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        let first = Task { await model.checkArchiveStatusesIfNeeded() }
        await Task.yield()
        let second = Task { await model.checkArchiveStatusesIfNeeded() }
        await first.value
        await second.value
        await model.waitForPendingFavoritesSaves()

        let requestCount = await client.detailRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testArchiveCheckMarksNotFoundAsArchivedAndContinues() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-missing"),
            record(id: "3529-continues")
        ])
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .archiveNotFound),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store,
            currentDate: { now }
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        let saved = store.lastSaved
        XCTAssertEqual(saved.first { $0.id == "3529-missing" }?.archiveCheckedAt, now)
        XCTAssertEqual(saved.first { $0.id == "3529-missing" }?.isArchived, true)
        XCTAssertEqual(saved.first { $0.id == "3529-continues" }?.isArchived, true)
    }

    @MainActor
    private func makeOfflineFavoriteModel(mode: MockAPIClient.Mode, store: SlowRecordingFavoriteStore) -> VacancySearchViewModel {
        VacancySearchViewModel(
            apiClient: MockAPIClient(mode: mode),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )
    }

    private func offlineFavoriteRecord(id: String) -> FavoriteVacancyRecord {
        let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
        let result = VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id, name: vacancy.name, employer: vacancy.employer, area: vacancy.area,
                salary: nil, alternateURL: vacancy.alternateURL, description: nil, archived: false
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
        return FavoriteVacancyRecord(result: result, favoritedAt: .distantPast, updatedAt: .distantPast)
    }

    @MainActor
    func testOfflineFavoriteDetailsLoadAndPersistSnapshotWithoutSearch() async {
        let store = SlowRecordingFavoriteStore(favorites: [offlineFavoriteRecord(id: "3529-offline")])
        let model = makeOfflineFavoriteModel(mode: .simple, store: store)
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites
        XCTAssertFalse(model.displayedResults[0].isDetailLoaded)

        await model.loadVacancyDetails(id: "3529-offline")
        await model.waitForPendingFavoritesSaves()

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.displayedResults[0].isDetailLoaded)
        XCTAssertEqual(model.displayedResults[0].plainTextDescription, "Полное описание")
        XCTAssertEqual(store.lastSaved.first?.detailsSnapshot?.description, "<p>Полное описание</p>")
    }

    @MainActor
    func testOfflineFavoriteDetailFailureIsShownOnTheCard() async {
        let store = SlowRecordingFavoriteStore(favorites: [offlineFavoriteRecord(id: "3529-offline")])
        let model = makeOfflineFavoriteModel(mode: .failure, store: store)
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites

        await model.loadVacancyDetails(id: "3529-offline")

        let card = model.displayedResults[0]
        XCTAssertFalse(card.isDetailLoaded)
        XCTAssertFalse(card.isDetailLoading)
        XCTAssertTrue(card.detailErrorMessage?.hasPrefix("Не удалось загрузить описание") == true)
        XCTAssertNil(store.lastSaved.first?.detailsSnapshot)
    }

    @MainActor
    func testStartedRefreshCanBeCancelledAndKeepsPreviousResults() async {
        let client = MockAPIClient(mode: .delayedRefreshFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()
        let initialRequestCount = await client.searchRequestCount
        await client.enableDelayedSearchFailure()

        model.startRefresh()
        XCTAssertFalse(model.canSearch)
        while await client.searchRequestCount == initialRequestCount { await Task.yield() }
        XCTAssertTrue(model.canCancelSearch)
        model.cancelSearch()
        XCTAssertTrue(model.isCancellingSearch)
        XCTAssertFalse(model.canCancelSearch)
        while !model.canSearch { await Task.yield() }

        XCTAssertEqual(model.statusMessage, "Поиск отменён.")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isCancellingSearch)
        XCTAssertEqual(model.results.map(\.id), ["3529-vacancy"])
    }

    @MainActor
    func testArchiveCheckUsesFavoritesOrder() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let expectedIDs = (1...8).map { "3529-order-\($0)" }
        let store = SlowRecordingFavoriteStore(favorites: expectedIDs.map(record))
        let client = MockAPIClient(mode: .simple)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, expectedIDs)
    }

    @MainActor
    func testArchiveCheckContinuesAfterRecoverableVacancyFailure() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-fail"),
            record(id: "3529-continues")
        ])
        let client = MockAPIClient(mode: .archiveRecoverableFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, ["3529-fail", "3529-continues"])
        XCTAssertEqual(store.lastSaved.first { $0.id == "3529-continues" }?.isArchived, true)
    }

    @MainActor
    func testArchiveCheckStopsAfterTerminalAPIError() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-fail"),
            record(id: "3529-not-requested")
        ])
        let client = MockAPIClient(mode: .archiveTerminalFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, ["3529-fail"])
    }

    @MainActor
    func testFavoritePDFExportProducesBoundedValidPartsAndMainActorProgress() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedDate = Date(timeIntervalSince1970: 1_788_400_000)
        let vacancies = (0..<101).map { makePDFVacancy(id: String($0)) }
        var progressValues: [FavoritePDFExportProgress] = []
        var progressWasOnMainThread = true
        let exporter = FavoriteVacanciesPDFExporter(
            chooseDirectory: { directory },
            now: { fixedDate }
        )

        let outcome = try await exporter.export(vacancies: vacancies) { progress in
            progressWasOnMainThread = progressWasOnMainThread && Thread.isMainThread
            progressValues.append(progress)
        }

        XCTAssertEqual(outcome, .exported(fileCount: 2, pageCount: 101))
        XCTAssertEqual(progressValues.first, .init(completedVacancies: 1, totalVacancies: 101))
        XCTAssertEqual(progressValues.last, .init(completedVacancies: 101, totalVacancies: 101))
        XCTAssertTrue(progressValues.allSatisfy { $0.totalVacancies == 101 })
        XCTAssertTrue(zip(progressValues, progressValues.dropFirst()).allSatisfy {
            $0.completedVacancies <= $1.completedVacancies
        })
        XCTAssertEqual(progressValues.filter { $0.completedVacancies == 101 }.count, 1)
        XCTAssertTrue(progressWasOnMainThread)

        let pdfs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(pdfs.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2, "Only the PDFs are written")
        try FavoriteVacanciesPDFExporter.validatePDF(at: pdfs[0], expectedPages: 100)
        try FavoriteVacanciesPDFExporter.validatePDF(at: pdfs[1], expectedPages: 1)
        let documents = try pdfs.map { try XCTUnwrap(PDFDocument(url: $0)) }
        let text = try documents.map(extractedStatisticsText).joined(separator: "\n")
        var previous = text.startIndex
        for vacancy in vacancies {
            let titleLine = vacancy.name + "\n"
            XCTAssertEqual(text.components(separatedBy: titleLine).count - 1, 1)
            let range = try XCTUnwrap(text.range(of: titleLine))
            XCTAssertGreaterThanOrEqual(range.lowerBound, previous)
            previous = range.upperBound
        }
        for document in documents {
            XCTAssertNotNil(document.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date)
            XCTAssertNotNil(document.documentAttributes?[PDFDocumentAttribute.producerAttribute] as? String)
        }
    }

    @MainActor
    func testCancelledFavoritePDFSelectionReleasesPreparationAndAllowsNextExport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var selectedDirectory: URL?
        let exporter = FavoriteVacanciesPDFExporter(
            chooseDirectory: { selectedDirectory },
            now: { Date(timeIntervalSince1970: 1_788_400_000) }
        )
        let vacancy = makePDFVacancy(id: "cancel-retry")

        let cancelled = try await exporter.export(vacancies: [vacancy]) { _ in }
        XCTAssertEqual(cancelled, .cancelled)

        selectedDirectory = directory
        let completed = try await exporter.export(vacancies: [vacancy]) { _ in }
        XCTAssertEqual(completed, .exported(fileCount: 1, pageCount: 1))
    }

    func testPDFPaginationPreservesOversizedUnicodeContentAndRendersEveryPage() throws {
        let paragraph = "ОченьДлиннаяНепрерывнаяСтрокаБезПробелов0123456789🙂"
        let source = (0..<1_000).map { "\($0): \(paragraph)\n" }.joined()
        let attributed = NSAttributedString(
            string: source,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
        )

        let pages = FavoriteVacanciesPDFExporter.pages(for: attributed)

        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.content.string).joined(), source)
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
    }

    func testPDFPaginationKeepsParagraphsTogetherAndEveryPageFitsWhenDrawnAlone() throws {
        let words = (0..<60).map { "слово\($0)" }.joined(separator: " ")
        let source = (0..<120).map { "Абзац \($0). \(words)\n" }.joined()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        let attributed = NSAttributedString(string: source, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black, .paragraphStyle: style
        ])

        let pages = FavoriteVacanciesPDFExporter.pages(for: attributed)

        XCTAssertGreaterThan(pages.count, 3)
        XCTAssertEqual(pages.map(\.content.string).joined(), source)
        let text = source as NSString
        var offset = 0
        var previousStart = 0
        let drawableHeight = VacancyPDFDefaults.paperSize.height - VacancyPDFDefaults.verticalMargin * 2
        let width = VacancyPDFDefaults.paperSize.width - VacancyPDFDefaults.horizontalMargin * 2
        for (index, page) in pages.enumerated() {
            if index > 0 {
                let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
                // A page starts a paragraph unless that paragraph is longer than a page.
                XCTAssertTrue(paragraph.location == offset || paragraph.location <= previousStart,
                              "Page \(index + 1) splits a paragraph that fits on one page")
            }
            let height = page.content.boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            XCTAssertLessThanOrEqual(height, drawableHeight, "Page \(index + 1) would be clipped")
            previousStart = offset
            offset += page.content.length
        }
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
    }

    func testPDFPaginationDoesNotEmitBlankPagesForWhitespaceTail() throws {
        let source = "Текст вакансии\n" + String(repeating: "\n", count: 400)
        let attributed = NSAttributedString(
            string: source,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
        )

        let pages = FavoriteVacanciesPDFExporter.pages(for: attributed)

        XCTAssertEqual(pages.map(\.content.string).joined(), source)
        XCTAssertTrue(pages.allSatisfy { !$0.content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
    }

    @MainActor
    func testPDFSnapshotImportsHTMLOnMainActorForBackgroundRendering() async throws {
        let snapshot = PDFVacancySnapshot(value: makePDFVacancy(id: "main-import"))
        let imported = try XCTUnwrap(snapshot.importedDescription)
        XCTAssertTrue(imported.string.contains("Кириллица, Unicode"))

        // Rendering happens off the main actor from the imported text only.
        let rendered = await Task.detached { snapshot.attributedDocument.string }.value
        XCTAssertTrue(rendered.contains("Кириллица, Unicode"))
        XCTAssertFalse(rendered.contains("<p>"))

        let batch = try await PDFVacanciesSnapshot.make(values: [makePDFVacancy(id: "a"), makePDFVacancy(id: "b")])
        XCTAssertEqual(batch.values.map(\.value.id), ["a", "b"])
        XCTAssertTrue(batch.values.allSatisfy { $0.importedDescription != nil })
    }

    func testPDFDocumentWithoutImportedDescriptionFallsBackToPlainText() {
        let document = VacancyPDFFormatter.attributedDocument(
            for: makePDFVacancy(id: "plain"),
            importedDescription: nil
        ).string
        XCTAssertTrue(document.contains("Кириллица, Unicode"))
        XCTAssertFalse(document.contains("<p>"))
    }

    @MainActor
    func testPDFHeadingAndBodyTypographyUsesReducedPointSizes() throws {
        let document = VacancyPDFFormatter.attributedDocument(for: makePDFVacancy(id: "typography"))
        let text = document.string as NSString

        func fontSize(at substring: String, offset: Int = 0) throws -> CGFloat {
            let range = text.range(of: substring)
            guard range.location != NSNotFound else {
                XCTFail("Missing PDF text: \(substring)")
                return 0
            }
            let location = range.location + offset
            return try XCTUnwrap(
                document.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            ).pointSize
        }

        XCTAssertEqual(try fontSize(at: "Инженер надёжности typography"), 18, accuracy: 0.01)
        XCTAssertEqual(try fontSize(at: "Основная информация"), 13, accuracy: 0.01)
        XCTAssertEqual(try fontSize(at: "Работодатель: СБЕР"), 9.5, accuracy: 0.01)
        XCTAssertEqual(
            try fontSize(at: "Работодатель: СБЕР", offset: ("Работодатель: " as NSString).length),
            7.5,
            accuracy: 0.01
        )
    }

    @MainActor
    func testPersonalPDFWorkerCreatesAtomicValidDocument() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("personal.pdf")
        let worker = PDFExportWorker()

        try await worker.exportPersonal(
            vacancy: PDFVacancySnapshot(value: makePDFVacancy(id: "personal")),
            destination: destination
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        try FavoriteVacanciesPDFExporter.validatePDF(at: destination, expectedPages: 1)
    }

    func testPersonalPDFCancellationOnLastPageNeverPublishesAndAllowsRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vacancy = makePDFVacancy(id: "last-page-cancel")
        let worker = PDFExportWorker()
        let originalURL = directory.appendingPathComponent("original.pdf")
        try await worker.exportPersonal(vacancy: .init(value: makePDFVacancy(id: "original")), destination: originalURL)
        let original = try Data(contentsOf: originalURL)
        for existing in [false, true] {
            let destination = directory.appendingPathComponent(existing ? "existing.pdf" : "new.pdf")
            if existing { try original.write(to: destination, options: .atomic) }
            let task = Task {
                try await worker.exportPersonal(vacancy: .init(value: vacancy), destination: destination) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            do {
                try await task.value
                XCTFail("Cancellation on the final page must prevent publication")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            if existing {
                XCTAssertEqual(try Data(contentsOf: destination), original)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            }
            try await worker.exportPersonal(vacancy: .init(value: vacancy), destination: destination)
            let pdf = try XCTUnwrap(PDFDocument(url: destination))
            XCTAssertEqual(pdf.pageCount, 1)
            XCTAssertTrue(pdf.string?.contains("last-page-cancel") == true)
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                       Set(["original.pdf", "existing.pdf", "new.pdf"]))
    }

    @MainActor
    func testPDFFallbackPreservesSummaryFieldsInPersonalAndFavoriteDocuments() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let summary = HHVacancySummary(id: "fallback-fields", name: "UniqueTitleAlpha",
            employer: .init(name: "СБЕР", id: "3529"),
            salary: .init(from: 123_456, to: nil, currency: "RUR", gross: false),
            area: .init(id: "1", name: "Москва"), alternateURL: "https://example.invalid/fallback-fields",
            url: nil, snippet: .init(requirement: "UniqueSnippetBeta", responsibility: nil),
            department: .init(name: "DepartmentFallback"), publishedAt: "2026-09-02T12:34:56+0300")
        let value = VacancySearchResult(id: summary.id, summary: summary,
            details: .init(id: summary.id, name: summary.name, employer: nil, area: nil,
                salary: nil, alternateURL: nil, description: nil),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва"))
        let worker = PDFExportWorker()
        let personal = directory.appendingPathComponent("personal.pdf")
        try await worker.exportPersonal(vacancy: .init(value: value), destination: personal)
        let exporter = FavoriteVacanciesPDFExporter(chooseDirectory: { directory },
            now: { Date(timeIntervalSince1970: 1_788_400_000) })
        _ = try await exporter.export(vacancies: [value]) { _ in }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pdf" }
        XCTAssertEqual(files.count, 2)
        for file in files {
            let pdf = try XCTUnwrap(PDFDocument(url: file))
            XCTAssertEqual(pdf.pageCount, 1)
            let text = try extractedStatisticsText(pdf)
            // Use word markers: PDFKit versions can reorder punctuation during
            // extraction. Check exact source content and one complete occurrence
            // in the PDF, independent of extracted whitespace.
            let sourceText = VacancyPDFFormatter.attributedDocument(for: value).string
            let markerText = text.components(separatedBy: .whitespacesAndNewlines).joined()
            for marker in ["UniqueTitleAlpha", "UniqueSnippetBeta"] {
                XCTAssertEqual(sourceText.components(separatedBy: marker).count - 1, 1)
                XCTAssertEqual(markerText.components(separatedBy: marker).count - 1, 1,
                               "Extracted synthetic PDF text: \(text)")
            }
            XCTAssertTrue(text.contains("DepartmentFallback"), "Lost summary department")
            XCTAssertTrue(text.contains("2026-09-02T12:34:56+0300"), "Lost summary publication date")
            XCTAssertTrue(text.contains("123 456"), "Lost summary salary")
            XCTAssertTrue(text.contains("https://example.invalid/fallback-fields"))
            XCTAssertTrue(text.contains("Полное описание из detail endpoint HH недоступно."))
            let attachment = XCTAttachment(data: try Data(contentsOf: file), uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = file.lastPathComponent == "personal.pdf" ? "Fallback personal PDF" : "Fallback favorites PDF"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testPDFFallbackDoesNotOverrideAvailableDetailFields() throws {
        let summary = HHVacancySummary(id: "priority", name: "Priority title", employer: nil,
            salary: .init(from: 123_456, to: nil, currency: "RUR", gross: nil), area: nil,
            alternateURL: nil, url: nil, snippet: nil, department: .init(name: "SummaryDepartment"),
            publishedAt: "2026-09-01T10:00:00Z")
        let value = VacancySearchResult(id: summary.id, summary: summary,
            details: .init(id: summary.id, name: summary.name, employer: nil, area: nil,
                salary: .init(from: 987_654, to: nil, currency: "RUR", gross: nil), alternateURL: nil,
                description: nil, publishedAt: "2026-09-02T10:00:00Z", department: .init(name: "DetailDepartment")),
            isDetailLoaded: true)
        let pages = FavoriteVacanciesPDFExporter.pages(for: VacancyPDFFormatter.attributedDocument(for: value))
        let pdf = try XCTUnwrap(PDFDocument(data: FavoriteVacanciesPDFExporter.pdfData(for: pages)))
        let text = try extractedStatisticsText(pdf)
        for expected in ["DetailDepartment", "2026-09-02T10:00:00Z", "987 654"] {
            XCTAssertTrue(text.contains(expected))
        }
        for absent in ["SummaryDepartment", "2026-09-01T10:00:00Z", "123 456"] {
            XCTAssertFalse(text.contains(absent))
        }
    }

    func testHTMLSanitizerIsSafeAndDeterministicUnderConcurrentUse() async {
        let source = """
        <!-- secret --><div class="layout"><h2>Кириллица</h2><script>alert(1)</script>
        <a href="https://hh.ru/vacancy/42" onclick="alert(2)">HH</a>
        <a href="javascript:alert(3)">bad</a><img src="https://example.invalid/tracker.png"></div>
        """
        let expected = VacancyHTMLAttributedText.sanitize(source)

        XCTAssertFalse(expected.contains("secret"))
        XCTAssertFalse(expected.contains("script"))
        XCTAssertFalse(expected.contains("onclick"))
        XCTAssertFalse(expected.contains("javascript"))
        XCTAssertFalse(expected.contains("img"))
        XCTAssertTrue(expected.contains("<a href=\"https://hh.ru/vacancy/42\">"))
        XCTAssertTrue(expected.contains("Кириллица"))

        let values = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<100 {
                group.addTask { VacancyHTMLAttributedText.sanitize(source) }
            }
            var values: [String] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(Set(values), [expected])
    }

    @MainActor
    func testStatisticsSnapshotUsesCombinedFiltersAndRemainsStable() async {
        let model = makeFilterViewModel()
        await model.search()
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        let snapshot = model.statisticsReportSnapshot()
        XCTAssertEqual(snapshot.entries.map(\.id), ["filter-moscow"])
        XCTAssertEqual(snapshot.employerName, "СБЕР")
        XCTAssertEqual(snapshot.regionName, "Москва")
        model.selectedRegionID = "all"
        XCTAssertEqual(snapshot.entries.map(\.id), ["filter-moscow"])
        model.toggleFavorite(id: "filter-moscow")
        model.displayMode = .favorites
        XCTAssertEqual(model.statisticsReportSnapshot().entries.map(\.id), ["filter-moscow"])
        XCTAssertEqual(model.statisticsReportSnapshot().modeName, "Избранное")
        model.displayMode = .all
        model.selectedRegionID = "remote"
        XCTAssertTrue(model.statisticsReportSnapshot().entries.isEmpty)
        XCTAssertTrue(model.canExportStatisticsPDF)
    }

    func testStatisticsChronologyCountsMissingDatesAndPDFCompleteness() throws {
        let report = statisticsFixture([
            statisticsVacancy(id: "old", date: "2026-09-01T10:00:00+0300"),
            statisticsVacancy(id: "unknown", date: nil),
            statisticsVacancy(id: "new", date: "2026-09-03T10:00:00+0300", salary: true),
            statisticsVacancy(id: "fractional", date: "2026-09-03T08:00:00.500Z", archived: true),
            statisticsVacancy(id: "bad", date: "invalid")
        ])
        XCTAssertEqual(report.orderedEntries().map(\.entry.id), ["fractional", "new", "old", "bad", "unknown"])
        let document = try report.attributedDocument()
        XCTAssertTrue(document.string.contains("Всего вакансий: 5"))
        XCTAssertTrue(document.string.contains("В архиве: 1"))
        XCTAssertTrue(document.string.contains("С указанной зарплатой: 1"))
        XCTAssertTrue(document.string.contains("Без корректной даты размещения: 2"))
        let vacancyRowStringRange = try XCTUnwrap(
            document.string.range(of: "1. Вакансия fractional: 03.09.2026 08:00")
        )
        let vacancyRowRange = NSRange(vacancyRowStringRange, in: document.string)
        document.enumerateAttribute(.font, in: vacancyRowRange) { value, _, _ in
            guard let font = value as? NSFont else {
                XCTFail("В строке вакансии должен быть задан шрифт")
                return
            }
            XCTAssertEqual(font.pointSize, 7.5)
            XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.bold))
        }
        let vacancyRowStyle = try XCTUnwrap(
            document.attribute(.paragraphStyle, at: vacancyRowRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(vacancyRowStyle.lineSpacing, 3)
        XCTAssertEqual(vacancyRowStyle.paragraphSpacing, 5)
        let pages = FavoriteVacanciesPDFExporter.pages(for: document)
        XCTAssertEqual(pages.map(\.content.string).joined(), document.string)
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try extractedStatisticsText(pdf)
        XCTAssertTrue(text.contains("Вакансия fractional"))
        XCTAssertTrue(text.contains("Вакансия unknown"))
        XCTAssertTrue(text.contains("03.09.2026 08:00"))
    }

    func testStatisticsFilenameRetainsBothFiltersAndIsSafeForLongLabels() {
        let report = statisticsFixture([])
        XCTAssertTrue(report.fileName.contains("сбер"))
        XCTAssertTrue(report.fileName.contains("москва"))
        let long = VacancyStatisticsReport(
            entries: [], modeName: "Все вакансии", employerID: "3529",
            employerName: String(repeating: "Очень длинное / название ", count: 50),
            regionID: "subject:1", regionName: String(repeating: "Москва ", count: 50),
            createdAt: report.createdAt, timeZoneIdentifier: "UTC", sourceNote: ""
        )
        XCTAssertLessThanOrEqual(long.fileName.utf8.count, PDFFileNameBuilder.maximumUTF8Length)
        XCTAssertFalse(long.fileName.contains("/"))
        XCTAssertTrue(long.fileName.contains("москва"))
        XCTAssertTrue(long.fileName.hasSuffix(".pdf"))
    }

    @MainActor
    func testStatisticsExportUsesFrozenRowsWithoutDetailRequestsAndCanRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MockAPIClient(mode: .filters)
        var destination: URL?
        var chosenName = ""
        weak var observedModel: VacancySearchViewModel?
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")),
            statisticsPDFDestination: { name in
                chosenName = name
                observedModel?.selectedRegionID = "all"
                return destination
            }
        )
        observedModel = model
        XCTAssertFalse(model.canExportStatisticsPDF)
        await model.search()
        await model.exportStatisticsPDF() // cancelled save panel
        XCTAssertFalse(model.isExportingStatisticsPDF)
        XCTAssertNil(model.statisticsPDFExportMessage)
        destination = directory.appendingPathComponent("missing/report.pdf")
        await model.exportStatisticsPDF()
        XCTAssertTrue(model.statisticsPDFExportMessage?.contains("Не удалось") == true)
        destination = directory.appendingPathComponent("report.pdf")
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        await model.exportStatisticsPDF()
        let pdf = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(destination)))
        let text = try extractedStatisticsText(pdf)
        XCTAssertTrue(text.contains("Вакансия filter-moscow"))
        XCTAssertFalse(text.contains("Вакансия filter-ekb"))
        XCTAssertTrue(chosenName.contains("москва"))
        XCTAssertTrue(model.statisticsPDFExportMessage?.contains("сохранён: 1") == true)
        XCTAssertTrue(model.canExportStatisticsPDF)
        let detailRequests = await client.detailRequestCount
        XCTAssertEqual(detailRequests, 0)
    }

    func testStatisticsEmptyAndMultipageReportsPreserveEveryRow() throws {
        let empty = try statisticsFixture([]).attributedDocument()
        XCTAssertTrue(empty.string.contains("Всего вакансий: 0"))
        XCTAssertTrue(empty.string.contains("Под выбранными фильтрами вакансий нет."))
        let report = statisticsFixture((0..<250).map {
            statisticsVacancy(id: String($0), date: "2026-09-03T10:00:00+0300")
        })
        let document = try report.attributedDocument()
        let pages = FavoriteVacanciesPDFExporter.pages(for: document)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.content.string).joined(), document.string)
        let data = try FavoriteVacanciesPDFExporter.pdfData(for: pages)
        try FavoriteVacanciesPDFExporter.validatePDF(data: data, expectedPages: pages.count)
        let text = try extractedStatisticsText(XCTUnwrap(PDFDocument(data: data)))
        for entry in report.entries { XCTAssertTrue(text.contains(entry.name + ":")) }
    }

    @MainActor
    func testStatisticsPDFExportAcrossEveryEmployerAndRegionCombination() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, panel) = makeStatisticsExportModel(directory: directory)
        await model.search()
        let rows = statisticsFilterRows
        for employer in ["all", "3529", "2798", "9999"] {
            for region in ["all", "subject:1", "subject:2", "subject:66", "remote", "unknown"] {
                let expected = rows.filter {
                    (employer == "all" || $0.employer == employer) && (region == "all" || $0.region == region)
                }.map(\.id)
                try await assertStatisticsExport(model, client: client, panel: panel,
                                                 employer: employer, region: region, expected: expected)
            }
        }
        XCTAssertEqual(panel.names.count, 24)
        XCTAssertEqual(Set(panel.names).count, 24)
    }

    @MainActor
    func testStatisticsPDFExportAcrossEveryFavoriteFilterCombination() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, panel) = makeStatisticsExportModel(directory: directory)
        await model.search()
        let favoriteIDs = ["filter-moscow", "filter-unknown", "filter-remote"]
        for id in favoriteIDs { model.toggleFavorite(id: id) }
        model.displayMode = .favorites
        for employer in ["all", "3529", "2798"] {
            for region in ["all", "subject:1", "remote", "unknown"] {
                let expected = statisticsFilterRows.filter {
                    favoriteIDs.contains($0.id)
                        && (employer == "all" || $0.employer == employer)
                        && (region == "all" || $0.region == region)
                }.map(\.id)
                try await assertStatisticsExport(model, client: client, panel: panel,
                                                 employer: employer, region: region, expected: expected)
            }
        }
        XCTAssertEqual(panel.names.count, 12)
        XCTAssertEqual(Set(panel.names).count, 12)
        XCTAssertTrue(panel.names.allSatisfy { $0.contains("избранное") })
    }

    @MainActor
    func testRepeatedStatisticsExportsReplacePriorFilterContentsInSameFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, panel) = makeStatisticsExportModel(directory: directory)
        await model.search()
        for (employer, region, expected) in [
            ("all", "all", statisticsFilterRows.map(\.id)),
            ("3529", "subject:1", ["filter-moscow"]),
            ("2798", "remote", ["filter-remote"]),
            ("3529", "remote", []),
            ("all", "unknown", ["filter-unknown"]),
            ("all", "all", statisticsFilterRows.map(\.id))
        ] {
            try await assertStatisticsExport(model, client: client, panel: panel,
                                             employer: employer, region: region, expected: expected)
        }
        XCTAssertEqual(panel.names.first, panel.names.last)
        XCTAssertFalse(model.isExportingStatisticsPDF)
    }

    @MainActor
    func testStatisticsExportCapturesModeRowsAndLabelsBeforeSavePanelChangesFavorites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, _, panel) = makeStatisticsExportModel(directory: directory)
        await model.search()
        model.toggleFavorite(id: "filter-moscow")
        model.toggleFavorite(id: "filter-remote")
        model.displayMode = .favorites
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        panel.onChoose = { [weak model] in
            guard let model else { return }
            XCTAssertTrue(model.isExportingStatisticsPDF)
            XCTAssertFalse(model.canExportStatisticsPDF)
            XCTAssertFalse(model.canExportFavoritesPDF)
            model.toggleFavorite(id: "filter-moscow")
            model.displayMode = .all
            model.selectedEmployerID = "2798"
            model.selectedRegionID = "remote"
        }
        await model.exportStatisticsPDF()
        let text = try extractedStatisticsText(XCTUnwrap(PDFDocument(url: XCTUnwrap(panel.destination))))
        XCTAssertTrue(text.contains("Список: Избранное"))
        XCTAssertTrue(text.contains("Работодатель: СБЕР"))
        XCTAssertTrue(text.contains("Регион: Москва"))
        XCTAssertTrue(text.contains("Вакансия filter-moscow:"))
        XCTAssertFalse(text.contains("Вакансия filter-remote:"))
        XCTAssertTrue(panel.names[0].contains("избранное_сбер_москва"))
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-remote"])
        XCTAssertTrue(model.canExportFavoritesPDF)
    }

    @MainActor
    func testStatisticsExportEmptyFavoritesWorksWithoutSearch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, panel) = makeStatisticsExportModel(directory: directory)
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites
        try await assertStatisticsExport(model, client: client, panel: panel,
                                         employer: "all", region: "all", expected: [])
        let requests = await client.searchRequestCount
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(panel.names[0].contains("избранное"))
    }

    @MainActor
    func testStatisticsExportUnavailableBeforeSearchOrAfterInitialFailure() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, _, panel) = makeStatisticsExportModel(directory: directory, mode: .failure)
        await model.loadPersistenceIfNeeded()
        await model.exportStatisticsPDF()
        XCTAssertTrue(panel.names.isEmpty)
        await model.search()
        XCTAssertNotNil(model.errorMessage)
        await model.exportStatisticsPDF()
        XCTAssertFalse(model.canExportStatisticsPDF)
        XCTAssertTrue(panel.names.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: panel.destination!.path))
    }

    @MainActor
    func testStatisticsExportPersistedFavoritesWithoutNetworkPreservesArchiveAndDates() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MockAPIClient(mode: .failure)
        let destination = directory.appendingPathComponent("offline.pdf")
        let records = [statisticsVacancy(id: "offline-old", date: "2026-08-01T10:00:00+0300", archived: true),
                       statisticsVacancy(id: "offline-new", date: "2026-09-01T10:00:00+0300", salary: true)].map {
            FavoriteVacancyRecord(result: $0, favoritedAt: .distantPast, updatedAt: .distantPast)
        }
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")),
            favoritesStore: InMemoryFavoriteVacancyStore(favorites: records),
            statisticsPDFDestination: { _ in destination }
        )
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        await model.exportStatisticsPDF()
        let text = try extractedStatisticsText(XCTUnwrap(PDFDocument(url: destination)))
        XCTAssertTrue(text.contains("Всего вакансий: 2"))
        XCTAssertTrue(text.contains("В архиве: 1"))
        XCTAssertTrue(text.contains("С указанной зарплатой: 1"))
        XCTAssertTrue(text.contains("Вакансия offline-new:"))
        XCTAssertTrue(text.contains("Вакансия offline-old:"))
        XCTAssertLessThan((text as NSString).range(of: "Вакансия offline-new:").location,
                          (text as NSString).range(of: "Вакансия offline-old:").location)
        let searches = await client.searchRequestCount
        let details = await client.detailRequestCount
        let attemptedDetails = await client.requestedDetailIDs
        XCTAssertEqual(searches, 0)
        XCTAssertEqual(details, 0)
        XCTAssertTrue(attemptedDetails.isEmpty)
    }

    @MainActor
    func testStatisticsExportBlockedDuringRefreshAndUsesExplicitStaleDataAfterFailure() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, panel) = makeStatisticsExportModel(directory: directory, mode: .delayedRefreshFailure)
        await model.search()
        await client.enableDelayedSearchFailure()
        let refresh = Task { await model.refreshVacancies() }
        for _ in 0..<1_000 {
            if model.isLoading { break }
            await Task.yield()
        }
        XCTAssertTrue(model.isLoading)
        await model.exportStatisticsPDF()
        XCTAssertTrue(panel.names.isEmpty)
        await refresh.value
        XCTAssertNotNil(model.errorMessage)
        await model.exportStatisticsPDF()
        let text = try extractedStatisticsText(XCTUnwrap(PDFDocument(url: XCTUnwrap(panel.destination))))
        XCTAssertTrue(text.contains("Последнее обновление не завершено"))
        XCTAssertTrue(text.contains("Всего вакансий: 3"))
        XCTAssertTrue(model.canExportStatisticsPDF)
    }

    func testStatisticsFilenameDisambiguatesSameNamesWithDifferentIDsAndModes() {
        func report(employer: String, region: String, mode: String) -> VacancyStatisticsReport {
            VacancyStatisticsReport(entries: [], modeName: mode, employerID: employer, employerName: "Одинаковое имя",
                                    regionID: region, regionName: "Одинаковый регион", createdAt: .distantPast,
                                    timeZoneIdentifier: "UTC", sourceNote: "")
        }
        let names = [report(employer: "1", region: "subject:1", mode: "Все вакансии"),
                     report(employer: "2", region: "subject:1", mode: "Все вакансии"),
                     report(employer: "1", region: "subject:2", mode: "Все вакансии"),
                     report(employer: "1", region: "subject:1", mode: "Избранное")].map(\.fileName)
        XCTAssertEqual(Set(names).count, 4)
        XCTAssertTrue(names.allSatisfy { $0.utf8.count <= PDFFileNameBuilder.maximumUTF8Length })
    }

    func testStatisticsOrderIsStableForEqualInstantsAcrossTimeZones() {
        let vacancies = [statisticsVacancy(id: "b", date: "2026-09-03T10:00:00+0300"),
                         statisticsVacancy(id: "a", date: "2026-09-03T07:00:00Z"),
                         statisticsVacancy(id: "c", date: "2026-09-03T07:00:00.001Z"),
                         statisticsVacancy(id: "z", date: nil)]
        XCTAssertEqual(statisticsFixture(vacancies).orderedEntries().map(\.entry.id), ["c", "a", "b", "z"])
        XCTAssertEqual(statisticsFixture(Array(vacancies.reversed())).orderedEntries().map(\.entry.id), ["c", "a", "b", "z"])
    }

    func testCancelledStatisticsWorkerPreservesExistingFileAndAllowsRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.pdf")
        let original = Data("original file must survive cancellation".utf8)
        try original.write(to: url)
        let worker = PDFExportWorker()
        let report = statisticsFixture([statisticsVacancy(id: "retry", date: nil)])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await worker.exportStatistics(report: report, destination: url)
        }
        do { try await cancelled.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: url), original)
        try await worker.exportStatistics(report: report, destination: url)
        XCTAssertTrue(try extractedStatisticsText(XCTUnwrap(PDFDocument(url: url))).contains("Вакансия retry:"))
    }

    func testOptInPDFRenderingMetrics() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HH_RUN_PERFORMANCE_TESTS"] == "1",
            "Set HH_RUN_PERFORMANCE_TESTS=1 for the five-iteration SDK metrics run."
        )
        let paragraph = "Надёжность, производительность и Unicode: ёж, Ω.\n"
        let document = NSAttributedString(
            string: String(repeating: paragraph, count: 8_000),
            attributes: [.font: NSFont.systemFont(ofSize: 9.5)]
        )
        let pages = FavoriteVacanciesPDFExporter.pages(for: document)
        XCTAssertGreaterThan(pages.count, 10)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var renderedByteCount = 0
        var renderingError: Error?
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            autoreleasepool {
                do {
                    renderedByteCount = try FavoriteVacanciesPDFExporter.pdfData(for: pages).count
                } catch {
                    renderingError = error
                }
            }
        }
        if let renderingError { throw renderingError }
        XCTAssertGreaterThan(renderedByteCount, 0)
    }

    private var statisticsFilterRows: [(id: String, employer: String, region: String)] {
        [("filter-moscow", "3529", "subject:1"), ("filter-ekb", "3529", "subject:66"),
         ("filter-unknown", "3529", "unknown"), ("filter-remote", "2798", "remote"),
         ("filter-spb", "9999", "subject:2")]
    }

    @MainActor
    private final class StatisticsDestinationSpy {
        var destination: URL?
        var names: [String] = []
        var onChoose: (() -> Void)?
        init(destination: URL) { self.destination = destination }
        func choose(_ name: String) -> URL? {
            names.append(name)
            onChoose?()
            return destination
        }
    }

    @MainActor
    private func makeStatisticsExportModel(directory: URL, mode: MockAPIClient.Mode = .filters)
        -> (VacancySearchViewModel, MockAPIClient, StatisticsDestinationSpy) {
        let client = MockAPIClient(mode: mode)
        let panel = StatisticsDestinationSpy(destination: directory.appendingPathComponent("report.pdf"))
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [
                .init(id: "3529", name: "СБЕР", comment: "test"),
                .init(id: "2798", name: "СберРешения", comment: "test"),
                .init(id: "9999", name: "Альфа Банк", comment: "test")
            ]),
            areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")),
            statisticsPDFDestination: panel.choose,
            currentDate: { Date(timeIntervalSince1970: 1_788_400_000) }
        )
        return (model, client, panel)
    }

    @MainActor
    private func assertStatisticsExport(_ model: VacancySearchViewModel, client: MockAPIClient,
                                        panel: StatisticsDestinationSpy, employer: String, region: String,
                                        expected: [String], file: StaticString = #filePath, line: UInt = #line) async throws {
        model.selectedEmployerID = employer
        model.selectedRegionID = region
        let snapshot = model.statisticsReportSnapshot()
        let context = "\(model.displayMode.rawValue) / \(employer) / \(region)"
        XCTAssertEqual(Set(snapshot.entries.map(\.id)), Set(expected), context, file: file, line: line)
        let beforeSearch = await client.searchRequestCount
        let beforeDetails = await client.detailRequestCount
        await model.exportStatisticsPDF()
        let pdf = try XCTUnwrap(PDFDocument(url: XCTUnwrap(panel.destination)), context, file: file, line: line)
        let text = try extractedStatisticsText(pdf)
        XCTAssertGreaterThan(pdf.pageCount, 0, context, file: file, line: line)
        XCTAssertTrue(text.contains("Всего вакансий: \(expected.count)"), context, file: file, line: line)
        XCTAssertTrue(text.contains("Список: \(snapshot.modeName)"), context, file: file, line: line)
        XCTAssertTrue(text.contains("Работодатель: \(snapshot.employerName)"), context, file: file, line: line)
        XCTAssertTrue(text.contains("Регион: \(snapshot.regionName)"), context, file: file, line: line)
        let expectedRows = statisticsFilterRows.filter { expected.contains($0.id) }
        XCTAssertTrue(text.contains("Работодателей: \(Set(expectedRows.map(\.employer)).count)"), context, file: file, line: line)
        XCTAssertTrue(text.contains("Регионов / территориальных групп: \(Set(expectedRows.map(\.region)).count)"), context, file: file, line: line)
        for row in statisticsFilterRows {
            XCTAssertEqual(text.contains("Вакансия \(row.id):"), expected.contains(row.id), context, file: file, line: line)
        }
        // Fixture 3529 was published a day later than the other employers.
        let expectedOrder = expectedRows.sorted {
            if ($0.employer == "3529") != ($1.employer == "3529") { return $0.employer == "3529" }
            return $0.id < $1.id
        }
        var previousPosition = -1
        for row in expectedOrder {
            let position = (text as NSString).range(of: "Вакансия \(row.id):").location
            XCTAssertNotEqual(position, NSNotFound, context, file: file, line: line)
            XCTAssertGreaterThan(position, previousPosition, context, file: file, line: line)
            previousPosition = position
        }
        XCTAssertEqual(panel.names.last, snapshot.fileName, context, file: file, line: line)
        XCTAssertFalse(model.isExportingStatisticsPDF, context, file: file, line: line)
        XCTAssertTrue(model.statisticsPDFExportMessage?.contains("сохранён: \(expected.count)") == true, context, file: file, line: line)
        let afterSearch = await client.searchRequestCount
        let afterDetails = await client.detailRequestCount
        XCTAssertEqual(afterSearch, beforeSearch, context, file: file, line: line)
        XCTAssertEqual(afterDetails, beforeDetails, context, file: file, line: line)
    }

    private func extractedStatisticsText(_ pdf: PDFDocument) throws -> String {
        // macOS 13 Quartz/PDFKit can expose the shared SF glyph for Cyrillic к as kra.
        // Exact original Unicode is checked separately on the attributed page sequence.
        try XCTUnwrap(pdf.string).replacingOccurrences(of: "\u{0138}", with: "к")
            .precomposedStringWithCanonicalMapping
    }

    private func statisticsFixture(_ vacancies: [VacancySearchResult]) -> VacancyStatisticsReport {
        VacancyStatisticsReport(
            entries: vacancies.map(VacancyStatisticsReport.Entry.init), modeName: "Все вакансии",
            employerID: "3529", employerName: "СБЕР", regionID: "subject:1", regionName: "Москва",
            createdAt: Date(timeIntervalSince1970: 1_788_400_000), timeZoneIdentifier: "UTC", sourceNote: "Локальная выборка."
        )
    }

    private func statisticsVacancy(id: String, date: String?, salary: Bool = false, archived: Bool = false) -> VacancySearchResult {
        let summary = HHVacancySummary(
            id: id, name: "Вакансия \(id)", employer: .init(name: "СБЕР", id: "3529"),
            salary: salary ? .init(from: 100_000, to: nil, currency: "RUR", gross: false) : nil,
            area: .init(id: "1", name: "Москва"), alternateURL: nil, url: nil, snippet: nil, publishedAt: date
        )
        return VacancySearchResult(
            id: id, summary: summary,
            details: .init(id: id, name: summary.name, employer: summary.employer, area: summary.area,
                           salary: summary.salary, alternateURL: nil, description: nil, archived: archived),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
    }

    func testPublicationDateParserPreservesOffsetsFractionsAndMissingValues() throws {
        let parser = HHPublicationDateParser()
        let whole = try XCTUnwrap(parser.date(from: "2026-09-01T10:00:00Z"))
        for date in ["2026-09-01T13:00:00+0300", "2026-09-01T13:00:00+03:00", "2026-09-01T10:00:00.000Z"] {
            XCTAssertEqual(parser.date(from: date), whole)
        }
        let fraction = try XCTUnwrap(parser.date(from: "2026-09-01T10:00:00.125Z"))
        XCTAssertEqual(fraction.timeIntervalSince(whole), 0.125, accuracy: 0.0001)
        for date: String? in [nil, "", "not-a-date"] { XCTAssertNil(parser.date(from: date)) }
    }

    @MainActor
    func testFavoritesAndStatisticsAgreeOnFractionalPublicationChronology() async {
        let rows = [
            statisticsVacancy(id: "standard", date: "2026-09-01T10:00:00Z"),
            statisticsVacancy(id: "newest", date: "2026-09-03T13:00:00.125+0300"),
            statisticsVacancy(id: "middle", date: "2026-09-02T10:00:00.900Z"),
            statisticsVacancy(id: "missing", date: nil)
        ]
        let records = rows.map { FavoriteVacancyRecord(result: $0, favoritedAt: Date(), updatedAt: Date()) }
        let model = VacancySearchViewModel(apiClient: PDFEnrichmentClient(),
            employerStore: TestEmployerStore(entries: []), favoritesStore: InMemoryFavoriteVacancyStore(favorites: records))
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites
        let expected = ["newest", "middle", "standard", "missing"]
        XCTAssertEqual(model.displayedResults.map(\.id), expected)
        XCTAssertEqual(model.statisticsReportSnapshot().orderedEntries().map(\.entry.id), expected)
    }

    @MainActor
    func testSearchOrdersFractionalDatesBeforeOlderWholeSecondDates() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = [statisticsVacancy(id: "old", date: "2026-09-01T10:00:00Z"),
                    statisticsVacancy(id: "new", date: "2026-09-01T10:00:00.900Z")]
        let model = VacancySearchViewModel(apiClient: FixedSummaryAPIClient(rows: rows.map(\.summary)),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: directory.appendingPathComponent("areas.json")))
        await model.search()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.results.map(\.id), ["new", "old"])
    }

    @MainActor
    func testFavoritePDFSnapshotKeepsLocalStateWhileArchiveChecksUpdateFavorites() async {
        let blocked = expectation(description: "enrichment suspended")
        let client = SuspendedEnrichmentClient(onFirstRequest: { blocked.fulfill() })
        let exporter = PDFEnrichmentExporter()
        let model = await snapshotExportModel(client: client, exporter: exporter)
        let export = Task { await model.exportFavoriteVacanciesPDF() }
        await fulfillment(of: [blocked], timeout: 2)
        await model.checkArchiveStatusesIfNeeded()
        XCTAssertTrue(model.favorites.allSatisfy(\.isArchived))
        await client.resumeFirstRequest()
        await export.value
        XCTAssertEqual(exporter.snapshots.count, 1)
        XCTAssertEqual(exporter.snapshots.first?.map(\.id), ["pending", "full"])
        XCTAssertEqual(exporter.snapshots.first?.map(\.isArchived), [false, false])
        await model.waitForPendingFavoritesSaves()
    }

    @MainActor
    func testFavoritePDFProgressAndMembershipRemainStableWhenFavoriteIsRemoved() async {
        let blocked = expectation(description: "enrichment suspended")
        let client = SuspendedEnrichmentClient(onFirstRequest: { blocked.fulfill() })
        let exporter = PDFEnrichmentExporter()
        let model = await snapshotExportModel(client: client, exporter: exporter)
        exporter.onExport = { [weak model] in
            XCTAssertEqual(model?.favoritesPDFExportProgress, .init(completedVacancies: 2, totalVacancies: 2))
        }
        let export = Task { await model.exportFavoriteVacanciesPDF() }
        await fulfillment(of: [blocked], timeout: 2)
        model.toggleFavorite(id: "pending")
        XCTAssertEqual(model.favorites.count, 1)
        await client.resumeFirstRequest()
        await export.value
        XCTAssertEqual(exporter.snapshots.first?.map(\.id), ["pending", "full"])
        XCTAssertFalse(model.isExportingFavoritesPDF)
        await model.waitForPendingFavoritesSaves()
    }

    @MainActor
    private func snapshotExportModel(client: SuspendedEnrichmentClient, exporter: PDFEnrichmentExporter) async -> VacancySearchViewModel {
        let pending = FavoriteVacancyRecord(result: statisticsVacancy(id: "pending", date: nil),
            favoritedAt: Date(timeIntervalSince1970: 2), updatedAt: Date())
        let full = FavoriteVacancyRecord(result: makePDFVacancy(id: "full"),
            favoritedAt: Date(timeIntervalSince1970: 1), updatedAt: Date())
        let model = VacancySearchViewModel(apiClient: client, employerStore: TestEmployerStore(entries: []),
            favoritesStore: InMemoryFavoriteVacancyStore(favorites: [pending, full]), favoritePDFExporter: exporter)
        await model.loadPersistenceIfNeeded()
        model.displayMode = .favorites
        return model
    }

    @MainActor
    func testLargePDFPreparationAllowsFilterChangesAndInteractiveHHDetails() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, client, _) = makeStatisticsExportModel(directory: directory)
        await model.search()
        let initialSearchRequests = await client.searchRequestCount
        let worker = PDFExportWorker()
        let snapshot = PDFVacanciesSnapshot(values: (0..<100).map { makePDFVacancy(id: "joint-\($0)") })
        var completed = 0
        let preparation = Task {
            try await worker.prepare(vacancies: snapshot) { completed = $0.completedVacancies }
        }
        var interactionsDuringPDF = 0
        for index in 0..<20 {
            if completed < 100 { interactionsDuringPDF += 1 }
            model.selectedEmployerID = index.isMultiple(of: 2) ? "3529" : "all"
            model.selectedRegionID = index.isMultiple(of: 2) ? "subject:1" : "all"
            XCTAssertEqual(model.displayedResults.count, index.isMultiple(of: 2) ? 1 : 5)
            await model.loadVacancyDetails(id: index.isMultiple(of: 2) ? "filter-moscow" : "filter-ekb")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let prepared = try await preparation.value
        XCTAssertGreaterThan(interactionsDuringPDF, 1)
        XCTAssertEqual(prepared.pageCount, 100)
        XCTAssertEqual(completed, 100)
        let details = await client.requestedDetailIDs
        let searches = await client.searchRequestCount
        XCTAssertEqual(details, ["filter-moscow", "filter-ekb"])
        XCTAssertEqual(searches, initialSearchRequests)
        await worker.discardPreparedExport()
        await model.refreshVacancies()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.displayedResults.count, 5)
    }

    @MainActor
    func testRepeatedFavoritePDFEnrichmentReusesSessionDetailsWithoutChangingSnapshot() async {
        let client = PDFEnrichmentClient()
        let exporter = PDFEnrichmentExporter()
        let model = await enrichmentModel(client: client, exporter: exporter)
        await model.exportFavoriteVacanciesPDF()
        let firstCount = await client.requests
        XCTAssertEqual(firstCount, 3)
        await client.setError(HHAPIError.rateLimited(retryAfterSeconds: 60))
        await model.exportFavoriteVacanciesPDF()
        let repeatedCount = await client.requests
        XCTAssertEqual(repeatedCount, firstCount)
        XCTAssertEqual(exporter.snapshots.count, 2)
        XCTAssertEqual(exporter.snapshots[0].map(\.id), exporter.snapshots[1].map(\.id))
        XCTAssertEqual(exporter.snapshots[0].map(\.details), exporter.snapshots[1].map(\.details))
        XCTAssertTrue(exporter.snapshots[1].allSatisfy { $0.isDetailLoaded && $0.exportDataNotice == nil })
    }

    @MainActor
    func testFailedFavoritePDFEnrichmentIsNotCachedAndCanRecover() async {
        let client = PDFEnrichmentClient(error: URLError(.timedOut))
        let exporter = PDFEnrichmentExporter()
        let model = await enrichmentModel(client: client, exporter: exporter)
        await model.exportFavoriteVacanciesPDF()
        await client.setError(nil)
        await model.exportFavoriteVacanciesPDF()
        let count = await client.requests
        XCTAssertEqual(count, 6)
        XCTAssertTrue(exporter.snapshots[0].allSatisfy { $0.exportDataNotice != nil })
        XCTAssertTrue(exporter.snapshots[1].allSatisfy { $0.isDetailLoaded && $0.exportDataNotice == nil })
    }

    @MainActor
    func testFavoritePDFEnrichmentStopsOnAccessRestrictionsAndAllowsRetry() async {
        let errors: [HHAPIError] = [.unauthorized, .forbidden(requestID: "test"),
            .rateLimited(retryAfterSeconds: 60), .captchaRequired(requestID: "test"),
            .missingApplicationToken, .placeholderApplicationToken]
        for error in errors {
            let client = PDFEnrichmentClient(error: error)
            let exporter = PDFEnrichmentExporter()
            let model = await enrichmentModel(client: client, exporter: exporter)
            await model.exportFavoriteVacanciesPDF()
            let stoppedCount = await client.requests
            XCTAssertEqual(stoppedCount, 1, "\(error)")
            XCTAssertEqual(exporter.snapshots.count, 0, "Restricted export must not be presented as complete")
            XCTAssertFalse(model.isExportingFavoritesPDF)
            XCTAssertNil(model.favoritesPDFExportProgress)
            XCTAssertTrue(model.canExportFavoritesPDF)
            XCTAssertTrue(model.statusMessage?.contains(error.localizedDescription) == true)
            await client.setError(nil)
            await model.exportFavoriteVacanciesPDF()
            let retryCount = await client.requests
            XCTAssertEqual(retryCount, 4)
            XCTAssertEqual(exporter.snapshots.count, 1)
            XCTAssertEqual(exporter.snapshots.first?.count, 3)
        }
    }

    @MainActor
    func testFavoritePDFEnrichmentPropagatesCancellationWithoutPublishing() async {
        let client = PDFEnrichmentClient(error: CancellationError())
        let exporter = PDFEnrichmentExporter()
        let model = await enrichmentModel(client: client, exporter: exporter)
        await model.exportFavoriteVacanciesPDF()
        let count = await client.requests
        XCTAssertEqual(count, 1)
        XCTAssertTrue(exporter.snapshots.isEmpty)
        XCTAssertFalse(model.isExportingFavoritesPDF)
        XCTAssertNil(model.favoritesPDFExportProgress)
        XCTAssertEqual(model.statusMessage, "Сохранение избранного в PDF отменено.")
    }

    @MainActor
    func testFavoritePDFEnrichmentTaskCancellationStopsInFlightAndAllowsNextExport() async throws {
        let client = PDFEnrichmentClient(delay: 300_000_000)
        let exporter = PDFEnrichmentExporter()
        let model = await enrichmentModel(client: client, exporter: exporter)
        let task = Task { await model.exportFavoriteVacanciesPDF() }
        for _ in 0..<1000 {
            if await client.requests == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        await task.value
        let count = await client.requests
        XCTAssertEqual(count, 1)
        XCTAssertTrue(exporter.snapshots.isEmpty)
        XCTAssertTrue(model.canExportFavoritesPDF)
        await client.setDelay(0)
        await model.exportFavoriteVacanciesPDF()
        XCTAssertEqual(exporter.snapshots.count, 1)
    }

    @MainActor
    func testFavoritePDFRecoverableErrorsRetainExplicitLocalFallbackForEveryRow() async {
        for error in [HHAPIError.requestFailed(statusCode: 404, message: nil) as Error, URLError(.timedOut)] {
            let client = PDFEnrichmentClient(error: error)
            let exporter = PDFEnrichmentExporter()
            let model = await enrichmentModel(client: client, exporter: exporter)
            await model.exportFavoriteVacanciesPDF()
            let count = await client.requests
            XCTAssertEqual(count, 3)
            XCTAssertEqual(exporter.snapshots.first?.count, 3)
            XCTAssertTrue(exporter.snapshots.first?.allSatisfy { $0.exportDataNotice != nil } == true)
        }
    }

    @MainActor
    func testFavoritePDFWithPersistedDetailsDoesNotEnrichAgain() async {
        let client = PDFEnrichmentClient(error: HHAPIError.rateLimited(retryAfterSeconds: 60))
        let exporter = PDFEnrichmentExporter()
        let records = (0..<3).map {
            FavoriteVacancyRecord(result: makePDFVacancy(id: "\($0)"), favoritedAt: Date(), updatedAt: Date())
        }
        let model = VacancySearchViewModel(apiClient: client, employerStore: TestEmployerStore(entries: []),
            favoritesStore: InMemoryFavoriteVacancyStore(favorites: records), favoritePDFExporter: exporter)
        await model.loadPersistenceIfNeeded()
        await model.exportFavoriteVacanciesPDF()
        let count = await client.requests
        XCTAssertEqual(count, 0)
        XCTAssertEqual(exporter.snapshots.first?.count, 3)
    }

    @MainActor
    private func enrichmentModel(client: PDFEnrichmentClient, exporter: PDFEnrichmentExporter) async -> VacancySearchViewModel {
        let records = (0..<3).map {
            FavoriteVacancyRecord(result: statisticsVacancy(id: "\($0)", date: "2026-09-01T10:00:00Z"),
                favoritedAt: Date(timeIntervalSince1970: Double($0)), updatedAt: Date())
        }
        let model = VacancySearchViewModel(apiClient: client, employerStore: TestEmployerStore(entries: []),
            favoritesStore: InMemoryFavoriteVacancyStore(favorites: records), favoritePDFExporter: exporter)
        await model.loadPersistenceIfNeeded()
        return model
    }

    private func makePDFVacancy(id: String) -> VacancySearchResult {
        let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
        return VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id,
                name: "Инженер надёжности \(id)",
                employer: vacancy.employer,
                area: vacancy.area,
                salary: nil,
                alternateURL: "https://hh.ru/vacancy/\(id)",
                description: "<p>Кириллица, Unicode и длинная строка: надёжность-производительность-HeadHunter-PDF.</p>",
                archived: false,
                keySkills: [.init(name: "Swift"), .init(name: "macOS")]
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва"),
            isDetailLoaded: true
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HHVacancySberTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func makeFilterViewModel() -> VacancySearchViewModel {
        VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .filters),
            employerStore: TestEmployerStore(entries: [
                .init(id: "2798", name: "СберРешения", comment: "test"),
                .init(id: "3529", name: "СБЕР", comment: "test"),
                .init(id: "9999", name: "Альфа Банк", comment: "test")
            ]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: InMemoryFavoriteVacancyStore()
        )
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

private struct CancelledAreaClient: HHVacancyAPIClient {
    var responseGate: TestAsyncSignal? = nil
    var onRequest: @Sendable () -> Void = {}
    func validateVacanciesAccess() throws {}
    func areaTree() async throws -> HHAreaNode {
        onRequest()
        if let responseGate {
            await responseGate.wait()
            return .init(id: "113", name: "Россия", areas: [.init(id: "1", name: "Москва")])
        }
        throw CancellationError()
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        XCTFail("Search must not follow a cancelled area request")
        throw CancellationError()
    }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        XCTFail("Unexpected detail request")
        throw CancellationError()
    }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        XCTFail("Unexpected dictionary request")
        throw CancellationError()
    }
}

private actor EmployerScriptedClient: HHVacancyAPIClient {
    enum Behavior: Sendable { case vacancies(Int), failAfterFirstPage(Int), failure, forbidden }
    let behaviors: [String: Behavior]
    private(set) var requestedEmployerIDs: [String] = []
    init(behaviors: [String: Behavior]) { self.behaviors = behaviors }
    nonisolated func validateVacanciesAccess() throws {}
    func areaTree() async throws -> HHAreaNode { .init(id: "113", name: "Россия", areas: [.init(id: "1", name: "Москва")]) }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries { .init(experience: [], workFormat: [], schedule: []) }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        XCTFail("Unexpected detail request"); throw HHAPIError.invalidResponse
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        requestedEmployerIDs.append(request.employerID)
        let count: Int
        switch behaviors[request.employerID] ?? .vacancies(0) {
        case .failure: throw URLError(.timedOut)
        case .forbidden: throw HHAPIError.forbidden(requestID: nil)
        case .vacancies(let value): count = value
        case .failAfterFirstPage(let value):
            if request.page > 0 { throw HHAPIError.requestFailed(statusCode: 502, message: nil) }
            count = value
        }
        let start = request.page * request.perPage
        let end = min(start + request.perPage, count)
        let items = start < end ? (start..<end).map { index in
            HHVacancySummary(
                id: "\(request.employerID)-\(index)", name: "Вакансия \(index)",
                employer: .init(name: "Работодатель", id: request.employerID), salary: nil,
                area: .init(id: "1", name: "Москва"), alternateURL: nil, url: nil, snippet: nil,
                publishedAt: "2026-09-01T10:00:00+0300"
            )
        } : []
        return .init(items: items, found: count, pages: Int(ceil(Double(count) / Double(request.perPage))),
                     page: request.page, perPage: request.perPage)
    }
}

private actor MockAPIClient: HHVacancyAPIClient {
    enum Mode: Sendable {
        case simple, partitioned, mismatch, failure, delayedArchive, archiveNotFound
        case archiveRecoverableFailure, archiveTerminalFailure, archiveCancelled, delayedRefreshFailure, filters
    }
    let mode: Mode
    private(set) var detailRequestCount = 0
    private(set) var requestedDetailIDs: [String] = []
    private(set) var searchRequestCount = 0
    private var shouldFailSearch = false
    private let beforeFirstDetailResponse: (@Sendable () async throws -> Void)?
    init(mode: Mode, beforeFirstDetailResponse: (@Sendable () async throws -> Void)? = nil) {
        self.mode = mode
        self.beforeFirstDetailResponse = beforeFirstDetailResponse
    }
    func enableDelayedSearchFailure() { shouldFailSearch = true }
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
        requestedDetailIDs.append(id)
        if case .archiveCancelled = mode, id.hasSuffix("cancel") { throw CancellationError() }
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        if case .archiveRecoverableFailure = mode, id.hasSuffix("fail") {
            throw URLError(.timedOut)
        }
        if case .archiveTerminalFailure = mode, id.hasSuffix("fail") {
            throw HHAPIError.rateLimited(retryAfterSeconds: 60)
        }
        if case .archiveNotFound = mode, id.hasSuffix("missing") {
            throw HHAPIError.requestFailed(statusCode: 404, message: nil)
        }
        detailRequestCount += 1
        if detailRequestCount == 1 { try await beforeFirstDetailResponse?() }
        if case .delayedArchive = mode {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let employerID: String
        if case .filters = mode {
            // Search IDs use the "filter-" prefix, not the employer ID.
            switch id {
            case "filter-remote": employerID = "2798"
            case "filter-spb": employerID = "9999"
            default: employerID = "3529"
            }
        } else {
            employerID = id.components(separatedBy: "-").first ?? "3529"
        }
        let archived: Bool
        switch mode {
        case .archiveNotFound, .archiveRecoverableFailure, .archiveTerminalFailure, .archiveCancelled: archived = true
        default: archived = false
        }
        let employerName = employerID == "2798" ? "СберРешения" : employerID == "9999" ? "Альфа Банк" : "СБЕР"
        return .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerName, id: employerID),
                     area: .init(id: "1", name: "Москва"), salary: nil, alternateURL: nil,
                     description: "<p>Полное описание</p>", archived: archived)
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        searchRequestCount += 1
        if case .delayedRefreshFailure = mode, shouldFailSearch {
            try await Task.sleep(nanoseconds: 100_000_000)
            throw URLError(.timedOut)
        }
        switch mode {
        case .filters:
            let values: [HHVacancySummary]
            switch request.employerID {
            case "3529":
                values = [
                    makeSummary(id: "filter-moscow", employerID: "3529", employerName: "СБЕР", areaID: "1", areaName: "Москва"),
                    makeSummary(id: "filter-ekb", employerID: "3529", employerName: "СБЕР", areaID: "3", areaName: "Екатеринбург"),
                    makeSummary(id: "filter-unknown", employerID: "3529", employerName: "СБЕР", areaID: "999", areaName: "Минск")
                ]
            case "2798":
                values = [makeSummary(id: "filter-remote", employerID: "2798", employerName: "СберРешения", remote: true)]
            default:
                values = [makeSummary(id: "filter-spb", employerID: "9999", employerName: "Альфа Банк", areaID: "2", areaName: "Санкт-Петербург")]
            }
            return page(values, found: values.count, request: request)
        case .simple, .delayedArchive, .archiveNotFound, .archiveRecoverableFailure, .archiveTerminalFailure, .archiveCancelled,
             .delayedRefreshFailure:
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
    private func makeSummary(
        id: String,
        employerID: String,
        employerName: String,
        remote: Bool = false,
        areaID: String = "1",
        areaName: String = "Москва"
    ) -> HHVacancySummary {
        .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerName, id: employerID), salary: nil,
              area: remote ? nil : .init(id: areaID, name: areaName), alternateURL: nil, url: nil, snippet: nil,
              workFormat: remote ? [.init(id: "REMOTE", name: "Удалённо")] : nil,
              publishedAt: employerID == "3529" ? "2026-09-02T10:00:00+0300" : "2026-09-01T10:00:00+0300")
    }
}

private struct FixedTokenProvider: HHAccessTokenProviding {
    let accessToken: String? = "unit-token"
}

@MainActor
private final class PDFEnrichmentExporter: FavoriteVacanciesPDFExporting {
    var snapshots: [[VacancySearchResult]] = []
    var onExport: (() -> Void)?
    func export(vacancies: [VacancySearchResult], progress: @escaping @MainActor @Sendable (FavoritePDFExportProgress) -> Void) async throws -> FavoritePDFExportOutcome {
        onExport?()
        snapshots.append(vacancies)
        return .cancelled
    }
}

private actor SuspendedEnrichmentClient: HHVacancyAPIClient {
    private var requests = 0
    private let resume = TestAsyncSignal()
    private let onFirstRequest: @Sendable () -> Void
    init(onFirstRequest: @escaping @Sendable () -> Void) { self.onFirstRequest = onFirstRequest }
    nonisolated func validateVacanciesAccess() throws {}
    func resumeFirstRequest() async { await resume.signal() }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        requests += 1
        if requests == 1 {
            onFirstRequest()
            await resume.wait()
            throw URLError(.timedOut)
        }
        return .init(id: id, name: "Вакансия \(id)", employer: nil, area: nil,
            salary: nil, alternateURL: nil, description: nil, archived: true)
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        XCTFail("Unexpected search"); throw HHAPIError.invalidResponse
    }
    func areaTree() async throws -> HHAreaNode { XCTFail("Unexpected areas"); throw HHAPIError.invalidResponse }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries { XCTFail("Unexpected dictionaries"); throw HHAPIError.invalidResponse }
}

private struct FixedSummaryAPIClient: HHVacancyAPIClient {
    let rows: [HHVacancySummary]
    private let detailLoader: (@Sendable (String) async throws -> HHVacancyDetails)?
    init(rows: [HHVacancySummary], detailLoader: (@Sendable (String) async throws -> HHVacancyDetails)? = nil) {
        self.rows = rows
        self.detailLoader = detailLoader
    }
    func validateVacanciesAccess() throws {}
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        .init(items: rows, found: rows.count, pages: 1, page: 0, perPage: request.perPage)
    }
    func areaTree() async throws -> HHAreaNode { .init(id: "113", name: "Россия", areas: [.init(id: "1", name: "Москва")]) }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries { .init(experience: [], workFormat: [], schedule: []) }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        if let detailLoader { return try await detailLoader(id) }
        XCTFail("Search must not enrich"); throw HHAPIError.invalidResponse
    }
}

private actor PDFEnrichmentClient: HHVacancyAPIClient {
    var requests = 0
    private var error: Error?
    private var delay: UInt64
    init(error: Error? = nil, delay: UInt64 = 0) { self.error = error; self.delay = delay }
    func setError(_ error: Error?) { self.error = error }
    func setDelay(_ delay: UInt64) { self.delay = delay }
    nonisolated func validateVacanciesAccess() throws {}
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        requests += 1
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if let error { throw error }
        return .init(id: id, name: "Вакансия \(id)", employer: nil, area: nil, salary: nil,
            alternateURL: nil, description: "<p>Полные данные \(id)</p>")
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        XCTFail("PDF must not search"); throw HHAPIError.invalidResponse
    }
    func areaTree() async throws -> HHAreaNode { XCTFail("PDF must not load areas"); throw HHAPIError.invalidResponse }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries { XCTFail("PDF must not load dictionaries"); throw HHAPIError.invalidResponse }
}

private actor TestAsyncSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async { if !signalled { await withCheckedContinuation { waiter = $0 } } }
    func signal() { signalled = true; waiter?.resume(); waiter = nil }
}

private actor ConcurrentOperationTracker {
    private var activeOperations = 0
    private(set) var maximumConcurrentOperations = 0

    func begin() {
        activeOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperations)
    }

    func end() { activeOperations -= 1 }
}

private final class SlowRecordingFavoriteStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var activeSaves = 0
    private var maximum = 0
    private var saved: [FavoriteVacancyRecord] = []
    private var count = 0

    init(favorites: [FavoriteVacancyRecord] = []) { saved = favorites }
    func load() throws -> [FavoriteVacancyRecord] { lock.withLock { saved } }
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

private actor RetryWaitRecorder {
    var values: [UInt64] = []
    func append(_ value: UInt64) { values.append(value) }
}

private enum HTTPClientFactory {
    static func make(
        maximumRateLimitRetries: Int = 2,
        maximumTransientRetries: Int = 2,
        requestGate: HHRequestGate? = nil,
        retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { _ in }
    ) -> HHAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return HHAPIClient(
            session: URLSession(configuration: configuration),
            accessTokenProvider: FixedTokenProvider(),
            requestGate: requestGate ?? HHRequestGate(minimumDelayNanoseconds: 0),
            maximumRateLimitRetries: maximumRateLimitRetries,
            maximumTransientRetries: maximumTransientRetries,
            retrySleep: retrySleep
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


private enum LiveCancellationTransition: Int {
    case employer = 0, region = 1, favorites = 2
}

private enum LiveCancellationFailure: Error {
    case stopped, budgetExhausted, responseShape, http(Int), transport(Int), apiFailure
}

private final class LiveCancellationHTTPObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []

    var journal: String {
        lock.lock(); defer { lock.unlock() }
        return records.joined(separator: "\n")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let formatter = ISO8601DateFormatter()
        let entries = metrics.transactionMetrics.map { transaction in
            let timestamp = formatter.string(from: transaction.requestStartDate ?? transaction.fetchStartDate ?? metrics.taskInterval.start)
            let path = transaction.request.url?.path ?? "unknown"
            let status = (transaction.response as? HTTPURLResponse).map { String($0.statusCode) } ?? "no-http-response"
            return "\(timestamp) GET \(path) status=\(status)"
        }
        lock.lock(); records.append(contentsOf: entries); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // No additional redirect request outside the live group's explicit budget.
        completionHandler(nil)
    }
}

@MainActor
private final class LiveCancellationRun {
    static let shared = LiveCancellationRun()
    private let observer: LiveCancellationHTTPObserver
    private let session: URLSession
    private let client: HHAPIClient
    private var rows: [HHVacancySummary]?
    private(set) var stopped = false
    private(set) var requestCount = 0
    private var attempts: [String] = []
    var journal: String { (attempts + [observer.journal]).joined(separator: "\n") }

    private init() {
        let observer = LiveCancellationHTTPObserver()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
        self.observer = observer
        self.session = session
        self.client = HHAPIClient(session: session, requestGate: HHRequestGate(minimumDelayNanoseconds: 1_000_000_000), maximumRateLimitRetries: 0, maximumTransientRetries: 0)
    }

    private func begin(path: String) throws {
        guard !stopped else { throw LiveCancellationFailure.stopped }
        guard requestCount < 4 else { throw LiveCancellationFailure.budgetExhausted }
        requestCount += 1
        attempts.append("\(ISO8601DateFormatter().string(from: Date())) attempt=\(requestCount) GET \(path)")
    }

    private func stop(after error: Error) -> LiveCancellationFailure {
        stopped = true
        let safe: LiveCancellationFailure
        if let error = error as? URLError {
            safe = .transport(error.code.rawValue)
        } else if let error = error as? HHAPIError {
            switch error {
            case .forbidden: safe = .http(403)
            case .rateLimited: safe = .http(429)
            case .unauthorized: safe = .http(401)
            case .requestFailed(let status, _): safe = .http(status)
            default: safe = .apiFailure
            }
        } else {
            safe = .responseShape
        }
        attempts.append("Group stopped: \(safe)")
        return safe
    }

    func searchRows() async throws -> [HHVacancySummary] {
        if let rows { return rows }
        try begin(path: "/vacancies")
        do {
            let response = try await client.searchVacancies(.init(employerID: "3529", areaID: "1", perPage: 3))
            let parser = HHPublicationDateParser()
            guard response.items.count <= 3,
                  Set(response.items.map(\.id)).count == response.items.count,
                  response.items.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.employer?.id == "3529"
                      && parser.date(from: $0.publishedAt) != nil }) else {
                throw LiveCancellationFailure.responseShape
            }
            rows = response.items
            return response.items
        } catch { throw stop(after: error) }
    }

    func detail(id: String) async throws -> HHVacancyDetails {
        try begin(path: "/vacancies/\(id)")
        do {
            let response = try await client.vacancyDetails(id: id)
            let parser = HHPublicationDateParser()
            guard response.id == id, !response.name.isEmpty,
                  parser.date(from: response.publishedAt) != nil else {
                throw LiveCancellationFailure.responseShape
            }
            return response
        } catch { throw stop(after: error) }
    }
}

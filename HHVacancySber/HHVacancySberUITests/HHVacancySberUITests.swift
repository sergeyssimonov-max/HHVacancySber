import XCTest

final class HHVacancySberUITests: XCTestCase {
    private func launch(scenario: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HHVACANCYSBER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["HHVACANCYSBER_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    func testSearchShowsConfiguredVacanciesAndLazyDetails() {
        let app = launch()
        let search = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["СБЕР"].exists)
        app.buttons["expandVacancy.ui-1"].click()
        XCTAssertTrue(app.staticTexts["Полное описание вакансии."].waitForExistence(timeout: 5))
    }

    func testFilteringExpandedVacancyHidesDetailsAndAllowsReopening() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        app.buttons["expandVacancy.ui-1"].click()
        XCTAssertTrue(app.staticTexts["Полное описание вакансии."].waitForExistence(timeout: 5))

        choose("СберРешения", from: "employerFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["expandVacancy.ui-1"].exists)
        XCTAssertFalse(app.staticTexts["Полное описание вакансии."].exists)
        let hidden = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        hidden.name = "Expanded vacancy hidden by employer filter"
        hidden.lifetime = .keepAlways
        add(hidden)

        choose("Все работодатели", from: "employerFilterPicker", in: app)
        let details = app.buttons["expandVacancy.ui-1"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(details.label, "Подробнее")
        details.click()
        XCTAssertTrue(app.staticTexts["Полное описание вакансии."].waitForExistence(timeout: 5))
        let reopened = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        reopened.name = "Vacancy details reopened after clearing filter"
        reopened.lifetime = .keepAlways
        add(reopened)
    }

    func testInitialRefreshButtonMatchesToolbarButton() {
        let app = launch()
        let toolbarButton = app.buttons["searchVacanciesButton"]
        let emptyButton = app.buttons["emptyRefreshVacanciesButton"]
        XCTAssertTrue(toolbarButton.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyButton.exists)
        XCTAssertEqual(emptyButton.label, "Обновить выборку")
        XCTAssertEqual(emptyButton.frame.width, toolbarButton.frame.width, accuracy: 2)
        XCTAssertEqual(emptyButton.frame.height, toolbarButton.frame.height, accuracy: 2)
    }

    func testToolbarUsesOneAlignedRowWithoutExternalFilterLabels() {
        let app = launch()
        let mode = app.descendants(matching: .any)["vacancyListModePicker"]
        let employer = app.descendants(matching: .any)["employerFilterPicker"]
        let region = app.descendants(matching: .any)["regionFilterPicker"]
        let refresh = app.buttons["searchVacanciesButton"]

        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(employer.exists)
        XCTAssertTrue(region.exists)
        XCTAssertTrue(refresh.exists)
        XCTAssertFalse(app.staticTexts["Работодатель"].exists)
        XCTAssertFalse(app.staticTexts["Субъект"].exists)
        XCTAssertEqual(mode.frame.midY, employer.frame.midY, accuracy: 6)
        XCTAssertEqual(employer.frame.midY, region.frame.midY, accuracy: 6)
        XCTAssertEqual(region.frame.midY, refresh.frame.midY, accuracy: 6)
        XCTAssertLessThan(mode.frame.maxX, employer.frame.minX)
        XCTAssertLessThan(employer.frame.maxX, region.frame.minX)
        XCTAssertLessThan(region.frame.maxX, refresh.frame.minX)

        refresh.click()
        let status = app.descendants(matching: .any)["vacancyUpdateStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertLessThan(status.frame.maxX, refresh.frame.minX)
        XCTAssertEqual(status.frame.midY, refresh.frame.midY, accuracy: 6)
    }

    func testEmployerDropdownListsOptionsAndFiltersResults() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 3")

        choose("СберРешения", from: "employerFilterPicker", in: app)

        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 1")
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-1"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-2"].exists)

        choose("Все работодатели", from: "employerFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 3")
    }

    func testRegionDropdownCombinesWithEmployerAndCanShowNoMatches() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))

        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Москва", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].exists)
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 1")
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-2"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-3"].exists)

        choose("Свердловская область", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-1"].exists)

        choose("Удалённо", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 5))
    }

    func testEmptyResponseIsExplicit() {
        let app = launch(scenario: "empty")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 8))
    }

    func testSearchFailureIsExplicit() {
        let app = launch(scenario: "searchError")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["Не удалось загрузить вакансии"].waitForExistence(timeout: 8))
    }

    func testStatisticsPDFButtonIsAlignedAndAvailableForFilteredRows() {
        let app = launch()
        let report = app.buttons["exportStatisticsPDFButton"]
        let refresh = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertFalse(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, refresh.frame.maxX, accuracy: 2)
        refresh.click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, app.buttons["Экспорт в PDF"].firstMatch.frame.maxX, accuracy: 2)
        XCTAssertEqual(report.label, "Статистика в PDF")
        XCTAssertEqual(report.images.count, 0)
        XCTAssertEqual(report.frame.height, 32, accuracy: 2)
        XCTAssertEqual(report.frame.height, app.buttons["Экспорт в PDF"].firstMatch.frame.height, accuracy: 1)
        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Москва", from: "regionFilterPicker", in: app)
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 1")
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, refresh.frame.maxX, accuracy: 2)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Statistics PDF borderless command"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFavoritePDFCommandsHaveMatchingHeightAndNoLeadingStatisticsIcon() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        app.buttons["☆ В избранное"].firstMatch.click()
        let favoriteMode = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Избранное")).firstMatch
        XCTAssertTrue(favoriteMode.waitForExistence(timeout: 5))
        favoriteMode.click()
        let report = app.buttons["exportStatisticsPDFButton"]
        let favorites = app.buttons["exportFavoritesPDFButton"]
        let personal = app.buttons["exportVacancyPDF.ui-1"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.height, favorites.frame.height, accuracy: 1)
        XCTAssertEqual(report.frame.height, personal.frame.height, accuracy: 1)
        XCTAssertEqual(report.frame.midY, favorites.frame.midY, accuracy: 1)
        XCTAssertLessThan(favorites.frame.maxX, report.frame.minX)
        XCTAssertEqual(report.frame.maxX, personal.frame.maxX, accuracy: 2)
        XCTAssertEqual(report.images.count, 0)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Matching PDF commands in favorites"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStatisticsCommandRemainsAvailableForEmptyCombinedFilter() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Удалённо", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 5))
        let report = app.buttons["exportStatisticsPDFButton"]
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.label, "Статистика в PDF")
        XCTAssertEqual(report.frame.height, 32, accuracy: 2)
        XCTAssertEqual(app.staticTexts["displayedVacancyCount"].value as? String, "Показано вакансий: 0")
    }

    func testInformationSecurityLabelTakesPriorityAndPersistsInFavorites() {
        let app = launch(scenario: "security")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["informationSecurityLabel.ui-security"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["technologyBadge.ui-security"].exists)
        XCTAssertTrue(app.staticTexts["technologyBadge.ui-1"].exists)
        XCTAssertFalse(app.staticTexts["informationSecurityLabel.ui-2"].exists)
        app.buttons["favoriteVacancy.ui-security"].click()
        app.buttons["expandVacancy.ui-security"].click()
        XCTAssertTrue(app.staticTexts["Развиваем средства защиты данных и безопасные цифровые сервисы."].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Security card with plain label and full description"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Избранное")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["informationSecurityLabel.ui-security"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["technologyBadge.ui-security"].exists)
        XCTAssertTrue(app.buttons["favoriteVacancy.ui-security"].label.contains("В избранном"))
    }

    func testCancellingRefreshKeepsPreviousResults() {
        let app = launch(scenario: "slowRefresh")
        let button = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))

        button.click()
        XCTAssertTrue(waitForLabel("Отменить загрузку", of: button), "Refresh must turn the button into a cancel command")
        XCTAssertTrue(button.isEnabled)
        let loading = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        loading.name = "Refresh in progress with cancel command"
        loading.lifetime = .keepAlways
        add(loading)

        button.click()
        XCTAssertTrue(waitForLabel("Обновить выборку", of: button, timeout: 10), "Cancelled refresh must end promptly")
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].exists, "Previous results stay after cancellation")
        XCTAssertFalse(app.descendants(matching: .any)["collectionWarning"].exists)
    }

    func testCancellingFirstSearchReturnsToInitialScreen() {
        let app = launch(scenario: "slowSearch")
        let button = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(waitForLabel("Отменить загрузку", of: button))
        XCTAssertTrue(app.staticTexts["Загружаем вакансии всех настроенных работодателей…"].exists)

        button.click()
        XCTAssertTrue(waitForLabel("Обновить выборку", of: button, timeout: 10))
        let emptyButton = app.buttons["emptyRefreshVacanciesButton"]
        XCTAssertTrue(emptyButton.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyButton.label, "Обновить выборку")
        XCTAssertFalse(app.staticTexts["Вакансий не найдено"].exists)
    }

    func testPartialSearchShowsReceivedVacanciesAndWarning() {
        let app = launch(scenario: "partial")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-3"].exists, "The failed employer contributes no rows")

        let warning = app.descendants(matching: .any)["collectionWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("Выгрузка неполная"), warning.label)
        XCTAssertTrue(warning.label.contains("СберРешения"), warning.label)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Partial search warning"
        attachment.lifetime = .keepAlways
        add(attachment)

        let favoriteMode = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Избранное")).firstMatch
        XCTAssertTrue(favoriteMode.waitForExistence(timeout: 5))
        favoriteMode.click()
        XCTAssertTrue(waitForDisappearance(of: warning), "The warning belongs to the vacancy list, not to favorites")
    }

    private func waitForLabel(_ label: String, of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func choose(_ option: String, from pickerIdentifier: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[pickerIdentifier]
        guard picker.waitForExistence(timeout: 5) else {
            XCTFail("Missing picker \(pickerIdentifier)")
            return
        }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: picker
        )
        guard XCTWaiter.wait(for: [hittable], timeout: 5) == .completed else {
            XCTFail("Picker \(pickerIdentifier) is not ready for interaction")
            return
        }
        picker.click()
        let item = app.menuItems[option]
        guard item.waitForExistence(timeout: 5) else {
            XCTFail("Missing \(option) in \(pickerIdentifier)")
            return
        }
        item.click()
    }
}

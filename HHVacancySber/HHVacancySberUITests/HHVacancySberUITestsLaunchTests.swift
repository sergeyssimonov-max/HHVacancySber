import XCTest

final class HHVacancySberUITestsLaunchTests: XCTestCase {
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HHVACANCYSBER_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "СберВакансии"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

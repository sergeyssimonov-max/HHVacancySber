# HeadHunter API testing

HHVacancySber uses `https://api.hh.ru` as its API base. At runtime, requests use the application access token configured in `HHAuthConfig` through the centralized Bearer authorization and HH-User-Agent request builder. The application does not bootstrap or refresh tokens at runtime.

Normal unit and UI tests are offline and must not send production HeadHunter traffic. The single live smoke test is an explicit developer opt-in:

```bash
HH_LIVE_TESTS=1 xcodebuild \
  -project 'HHVacancySber/HHVacancySber.xcodeproj' \
  -scheme 'HHVacancySber' \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test \
  -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveVacancyReadSmoke
```

The smoke test performs at most two read-only GET requests: one minimal vacancy search (`/vacancies?page=0&per_page=1&area=1`) and, only when the search returns an item, one detail request for that vacancy. It performs no write operations and has a 12-hour cooldown. `HH_LIVE_TESTS_FORCE=1` is available solely as an explicit developer override for the cooldown and does not bypass the two-request or read-only limits.

An expanded production UI integration test is also available as an explicit opt-in:

```bash
HH_LIVE_UI_TESTS=1 xcodebuild \
  -project 'HHVacancySber/HHVacancySber.xcodeproj' \
  -scheme 'HHVacancySber' \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test \
  -only-testing:HHVacancySberUITests/HHVacancySberUITests/testLiveProductionSearchShowsMultipleVacancies
```

This test launches the production app composition, performs the normal configured search plan, waits for at least three real HeadHunter vacancy cards to appear, verifies the completed UI has no error state, and keeps a screenshot in the test result bundle. The production search plan can perform up to 33 read-only vacancy-search GET requests (five pages for each of five role queries and two pages for each of four expansion queries). It does not request vacancy details or perform writes unless a user explicitly interacts with a result card.

Production runtime automatic retries are disabled. Responses such as HTTP 429 and 5xx, as well as transport failures, are returned to the caller without automatic retry; the user may repeat the action manually.

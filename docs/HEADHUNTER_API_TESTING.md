# HeadHunter API testing

HHVacancySber uses `https://api.hh.ru` at runtime. Requests use the application token configured in `HHAuthConfig` through the centralized Bearer authorization and HH-User-Agent request builder. The application does not bootstrap or refresh tokens.

## Automated tests

The normal unit and UI suites are deterministic and do not send production traffic: unit tests use injected URL responses, while UI tests launch the DEBUG fixture composition selected by `HHVACANCYSBER_UI_TEST_MODE`. The shared scheme sets this flag for TestAction as well, so the unit-test host window also uses fixtures and cannot start archive checks against real favorites. Explicit opt-in live tests still construct their own clients.

Run the full local suite from the repository root:

```zsh
cd HHVacancySber
xcodebuild -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' test
```

CI runs the unit-test target without code signing:

```zsh
cd HHVacancySber
xcodebuild -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test -only-testing:HHVacancySberTests
```

## Limited live test

There are two separately enabled opt-in live API tests. The original authorization/details test follows. It uses the embedded application token, requests one search result, and then retrieves that vacancy's details. The test performs at most two read-only requests, does not log the token, and is skipped unless explicitly enabled:

```zsh
cd HHVacancySber
HHVACANCYSBER_RUN_LIVE_API_TEST=1 xcodebuild \
  -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  test -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveAPIUsesEmbeddedTokenAndRetrievesOneVacancyWithDetails
```

The additional technology-badge test makes at most **one read-only search request** for up to 20 Sber vacancies. It uses an ephemeral session with 15-second request and 20-second resource timeouts, without pagination, detail fetching or retries. An independent narrow title rule selects unmistakable developer/tester/DevOps/SRE/frontend/backend/fullstack roles, then checks the actual `VacancySearchResult.isTechnologyRelated` property used by the UI and its preservation during detail loading. It does not print tokens or response bodies. API and transport failures fail the test; a sample without such titles explicitly skips it, rather than claiming classification was verified. This smoke test does not assess recall or the visual appearance of the badge.

Run only the new test (the original live flag is not needed):

```zsh
cd HHVacancySber
TEST_RUNNER_HHVACANCYSBER_RUN_LIVE_TECHNOLOGY_TEST=1 xcodebuild \
  -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  test -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveAPITechnologyBadgeRecognizesExplicitTechnicalTitles
```

`TEST_RUNNER_` forwards the opt-in variable to the XCTest process with that prefix removed. Routine local and CI runs leave both live flags unset and create no hh.ru traffic. Keep both tests opt-in; running both explicitly permits at most three read-only API calls in total.

## Live cancellation group

Three additional opt-in tests verify hiding an expanded vacancy through employer
filter `2798`, region filter `subject:66`, and the favorites mode. Run the group
sequentially in one process, with the other live flags unset:

```zsh
cd HHVacancySber
TEST_RUNNER_HHVACANCYSBER_RUN_LIVE_CANCELLATION_TESTS=1 xcodebuild \
  -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO test \
  -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveCancellationWhenEmployerFilterHidesDetails \
  -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveCancellationWhenRegionFilterHidesDetails \
  -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveCancellationWhenFavoritesModeHidesDetails
```

The shared budget is **four GET requests**: one search for up to three Sber
vacancies in Moscow and one detail request for each of three distinct vacancies.
All network traffic uses HHAPIClient, with a one-second gate delay, ephemeral
session, 15/20-second request/resource timeouts, and no redirects or retries.
Any API or transport failure stops further requests in the group. Fewer than
three available vacancies skips the scenarios without additional searches.
Request start times, paths without query parameters, and actual HTTP status codes
from URLSessionTaskMetrics are attached to xcresult; credentials and bodies are
never attached. Search/detail response identities and publication-date parsing
are checked.

The tests use a bounded real search snapshot and local area-index fixture instead
of collecting the full employer directory. Filter/mode changes are applied to
ViewModel directly. Each genuine detail response is held at the test client
boundary before delivery to ViewModel. A filter/mode change must cancel the owned
Task; the late response must not populate the card, and loading must clear without
an error. This deterministically verifies cancellation and late-response handling
with live data; it does **not** demonstrate interrupting an unfinished HTTP transfer
or cancelling work on the hh.ru server. Ordinary runs and CI leave this flag unset.
Do not combine this group with other live groups under the same five-request budget.

## Runtime behavior

Production searches are read-only. A shared gate serializes requests and enforces at least one second between operations. Each logical request has a combined maximum of three HTTP attempts. HTTP 429 and transient HTTP 500/502/503/504 or short connection failures have bounded retry budgets with one- and two-second backoff. `Retry-After` is respected; an automatic wait above 60 seconds stops the operation, while the shared monotonic cooldown continues to prevent early requests, including after cancellation. Offline, TLS, authentication, 403 and CAPTCHA errors are not retried. The production session has 30-second request and 120-second resource timeouts.

The collector is best effort. A partition returning fewer unique vacancies than `found` is re-read once and the two reads are combined. Malformed vacancy items are skipped individually; a wholly malformed page does not prevent later pages from being read. Remaining shortfalls and failed partitions are reported by employer. Exhausted 429, 403 and CAPTCHA stop collection; if any vacancies were read, received pages are returned with issues for unfinished employers. Cancellation, missing token and 401 still abort. If nothing was read and a request failed, the previous result remains on screen. An incomplete result never replaces a previous complete result or satisfies the ten-minute cache; without a complete result, it is shown and persisted with its warning.

The accepted snapshot, including vacancies, locations, issues and completion time, is saved atomically and restored on startup. The refresh button always uses the network. Background archive checking yields to a scheduled or active search after its current request.

Every opt-in live client explicitly sets maximumRateLimitRetries to zero, preserving its request budget and immediate stop on 429/403. Normal tests inject the retry sleeper to verify delay values without waiting for real rate limits; a separate cancellation test uses a real suspended Task. The shared cooldown is process-local and does not persist across application restarts.

Additional live verification is a manual application run with the configured token. Do not add live traffic to the normal automated suite.

## Историческая выборочная проверка API HH — 05.09.2026

Выполнены **7 различных GET-запросов**, все получили **HTTP 200** и JSON.
Время: 18:36:15–18:36:22 МСК (15:36:15–15:36:22 UTC).
Использован application token из HHAuthConfig и те же Bearer, User-Agent,
HH-User-Agent и Accept, что в приложении. Транспорт — URLSession с ephemeral-сессией;
перенаправления отключены, повторных запросов и пагинации нет.
Токен, заголовки авторизации и полные тела ответов не сохранены в отчёте.

| № | GET api.hh.ru | HTTP | Результат |
|---|---|---|---|
| 1 | `/employers/11685629` | 200 | Единая Цифровая Платформа; ID 11685629; 7 открытых вакансий |
| 2 | `/vacancies?employer_id=11685629&per_page=3&page=0` | 200 | found=7; получены 3 вакансии, у всех employer_id=11685629 |
| 3 | `/employers/3529` | 200 | СБЕР; ID 3529; 3328 открытых вакансий |
| 4 | `/vacancies?employer_id=3529&per_page=1&page=0` | 200 | found=3328; получена 1 вакансия Сбера |
| 5 | `/employers/11036409` | 200 | ПУЛЬС; ID 11036409; 1 открытая вакансия |
| 6 | `/areas/113` | 200 | Россия; ID 113; 89 дочерних элементов справочника HH |
| 7 | `/vacancies/136954492` | 200 | Инцидент-менеджер; employer_id=11685629; описание 3824 символа |

Подтверждены совпадение ID работодателя в профиле, выдаче и деталях вакансии,
согласованность счётчика профиля с поиском и наличие непустого описания вакансии.
Проверка является выборочной: все 45 работодателей и полная выдача не проверялись.
Число вакансий — снимок на момент запросов, оно может измениться.

Первоначальный HTTP 403 был получен при проверке публичного API без токена.
Текущие успешные запросы подтверждают доступ с авторизацией приложения;
причина прежнего отказа отдельно не диагностировалась.

Санитизированные результаты: `output/hh-api-check/results-2026-09-05.json`.

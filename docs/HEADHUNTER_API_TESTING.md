# HeadHunter API testing

HHVacancySber uses `https://api.hh.ru` at runtime. Requests use the application token configured in `HHAuthConfig` through the centralized Bearer authorization and HH-User-Agent request builder. The application does not bootstrap or refresh tokens.

## Automated tests

The normal unit and UI suites are deterministic and do not send production traffic: unit tests use injected URL responses, while UI tests launch the DEBUG fixture composition selected by `HHVACANCYSBER_UI_TEST_MODE`.

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

Production searches are read-only. HHAPIClient permits at most two automatic retries for HTTP 429, holding the shared serial gate throughout the wait. The fallback delays are one and two seconds; a valid Retry-After delta or HTTP date can extend either delay up to 60 seconds. A server delay beyond that ceiling stops the operation rather than retrying early. HTTP 500, 502, 503 and 504 and short transport failures (timeout, lost connection, host unreachable, DNS lookup) get two separate bounded retries with the same one- and two-second backoff and Retry-After ceiling. HTTP 401, 403, CAPTCHA, other HTTP errors, offline and TLS failures are not retried. Exhausted 429 responses are surfaced to the caller and stop the background archive cycle.

The collector is best effort. A partition that returns fewer vacancies than `found` is re-read once and the two reads are combined. Pages read before a failed page are kept. A non-terminal failure ends only its partition or employer and is reported with the employer's expected and received counts. Authorization, 403, CAPTCHA, exhausted 429 and cancellation stop the whole search. If nothing was read and a request failed, the search fails and the previous result stays on screen. An incomplete result is shown with a warning and is not served from the ten-minute search cache.

Every opt-in live client explicitly sets maximumRateLimitRetries to zero, preserving its request budget and immediate stop on 429/403. Normal tests inject the retry sleeper to verify delay values without waiting for real rate limits; a separate cancellation test uses a real suspended Task. The gate is held during retry waits, but this is not a persistent session-wide blockade after the operation terminates.

Additional live verification is a manual application run with the configured token. Do not add live traffic to the normal automated suite.

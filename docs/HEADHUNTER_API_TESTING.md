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

There is exactly one opt-in live API test. It uses the embedded application token, requests one search result, and then retrieves that vacancy's details. The test performs at most two read-only requests, does not log the token, and is skipped unless explicitly enabled:

```zsh
cd HHVacancySber
HHVACANCYSBER_RUN_LIVE_API_TEST=1 xcodebuild \
  -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  test -only-testing:HHVacancySberTests/HHVacancySberTests/testLiveAPIUsesEmbeddedTokenAndRetrievesOneVacancyWithDetails
```

Keep live coverage to this single test. It must remain opt-in and bounded to two requests so routine local and CI runs cannot create hh.ru traffic.

## Runtime behavior

Production searches are read-only. Automatic retries are disabled except for the collector's single documented completeness retry when a partition changes while it is being read. HTTP 401, 403, 429, CAPTCHA, server, and transport failures are surfaced to the caller; the user may repeat the refresh manually.

Additional live verification is a manual application run with the configured token. Do not add live traffic to the normal automated suite.

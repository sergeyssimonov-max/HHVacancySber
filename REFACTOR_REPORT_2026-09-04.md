## 1. Итог

Восстановлена подпись счётчика: статусная строка показывает `Показано вакансий: N`, где `N` пересчитывается по текущим фильтрам; другие служебные сообщения туда не выводятся.
Baseline полного Debug выявил 4 упавших UI-теста и 6 одинаковых assertions; целевой прогон после исправления — 4/4, финальный полный Debug — 96 тестов, 1 штатный live-пропуск, 0 падений.
Unit `test + build + analyze` прошёл: 85 тестов, 1 штатный пропуск, 0 падений; Release `build + analyze` и 72 Python-теста также прошли.
Кроме возврата строки счётчика к `Показано вакансий: N`, архитектура, API, хранение, PDF pipeline и build-конфигурация не менялись; остальные исходные пользовательские правки сохранены.
`git diff --check`, синтаксис benchmark-скрипта, staged diff, project/scheme diff и проверка добавленных строк на секреты — чистые.
`/design` недоступен в этой Codex-сессии; визуальных production-изменений не было.
Приёмка с оговорками: Xcode не сохранил PDF/screenshot attachments, а полная матрица UI-состояний и бинарная детерминированность PDF metadata/document ID не подтверждены.

## 2. Инвентаризация и baseline

Рабочий корень: `/Users/mygga/Documents/ChatGPT/СберВакансии 2`; Xcode-команды выполнялись из `HHVacancySber`. Ветка `main`, исходный HEAD `6e76afd Handle macOS FSEvents metadata during DMG creation`. Origin: `https://github.com/sergeyssimonov-max/HHVacancySber.git`. `git fetch --dry-run`: первая sandbox-попытка завершилась кодом 128 из-за DNS, разрешённый сетевой повтор — код 0 без вывода. Локальная tracking-ссылка показывала `HEAD...origin/main = 3 0`; dry-run не обновляет её и не используется как доказательство актуального состояния remote.

Исходный `git status --short`:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
```

Это пользовательский dirty diff: 5 файлов, 57 добавлений, 20 удалений; staged и untracked файлов не было. Он изучен до правок, не откатывался, не добавлялся в index и не приписывается этому прогону.

Среда: Xcode 15.2 (15C500b), Swift 5.9.2, arm64. Точный `xcodebuild -quiet -project HHVacancySber.xcodeproj -list` после разрешённого запуска: код 0, 0,64 с; app, unit и UI targets, Debug/Release, единственная схема `HHVacancySber`. `Package.swift`, `Package.resolved`, внешние зависимости, lint/formatter configs, вторая схема и `AGENTS.md` не найдены. Устанавливать или обновлять инструменты не потребовалось.

`claude plugin list` прочитан без изменений: включены commit-commands, context7, frontend-design, rust-analyzer-lsp, svelte и typescript-lsp; выключены code-review, github и security-guidance. Наличие frontend-design в другом CLI не предоставляет callable `/design` в текущей сессии. Субагенты не использовались.

Прочитаны README, project.pbxproj, shared scheme, CI, `docs/HEADHUNTER_API_TESTING.md`, прошлые отчёты, release/verifier/benchmark scripts и их тесты, production source, unit/UI tests. Релиз, DMG, публикация и live HH API не запускались.

Карта кода и проверенные контракты:

| Область | Текущий контракт |
|---|---|
| Models / parsing | Value-модели; ISO8601 сначала без, затем с fractional seconds; formatters принадлежат потребителям. |
| API / gate | URLSession, обязательные заголовки, типизированные ошибки; actor сериализует запросы с интервалом 250 ms и отменяемой очередью; общего retry нет. |
| Collection | Последовательные employer/page запросы, reuse page 0, разбиение при лимите 2000, ID-dedupe, один completeness retry, cancellation между запросами. |
| Area cache | Cache 7 суток, stale fallback только при допустимом сетевом отказе, структурная проверка и atomic write. |
| Favorites | JSON schema v2, миграция v1, защита неизвестной схемы, atomic persistence. |
| View model | `@MainActor`, revision guards после await, локальные export snapshots, detached coalescing persistence driver. Search cache — 10 минут; details cache — сессионный, без TTL/cap. |
| Views | Initial/loading/error/empty/results/favorites/details, фильтры и PDF-команды в SwiftUI; HTML санитизируется до WKWebView. |
| PDF | Value snapshot, sanitize/format/layout/render, CG/PDFKit validation, atomic single-file и staged/backup/publish/rollback для частей, digest/identity/collision/recovery checks. |
| Tests / tooling | XCTest/XCUITest с моками, сигналами и URLProtocol; failure injection для файлов; Python unittest для release tooling. Benchmark `fatalError` на запрещённой сети — намеренный fail-fast. |

Точные активные идентификаторы `B1–B9` и `F001–F003` не найдены. `B13-DIST-001-R5-R6-R4` — release diagnostic, не скоринг. Историческое поле score собирается только в тесте миграции v1; runtime-скоринг не возвращался.

Точные baseline-команды до исправления:

```sh
# U/F/R — cwd HHVacancySber
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests build analyze
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor test
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor-release build analyze

# P/D/B — cwd корень
/usr/bin/python3 -m unittest discover -s scripts/tests -q
git diff --check
bash -n scripts/benchmarks/build.sh
```

| Baseline | Код | Результат | Wall time | Примечание |
|---|---:|---|---:|---|
| U, разрешённый точный повтор | 0 | 85 total / 1 skip / 0 fail | 105,38 с | testing 11,447 с; первая sandbox-попытка: 65 из-за testmanagerd, тесты не стартовали |
| F | 65 | 96 total / 1 skip / 4 failed tests | 187,60 с | testing 182,608 с; 6 assertions получили `label == ""` вместо `3/1/0` |
| R | 0 | build/analyze без диагностик | 17,25 с | Отдельный Release derived data |
| P | 0 | 72 tests, OK | 19,17 с | 18,661 с внутри unittest |
| D | 0 | Пустой вывод | 0,02 с | — |
| B | 0 | Пустой вывод | <0,01 с | — |

Baseline F упал в `testEmployerDropdownListsOptionsAndFiltersResults` (3 assertions), `testRegionDropdownCombinesWithEmployerAndCanShowNoMatches`, `testStatisticsCommandRemainsAvailableForEmptyCombinedFilter` и `testStatisticsPDFButtonIsAlignedAndAvailableForFilteredRows`. Во всех шести случаях элемент `displayedVacancyCount` существовал, но тест читал неверное AX-поле.

## 3. Изменения

| Файл / строки | Доказанная проблема | Красная проверка | Минимальная правка | Зелёная проверка |
|---|---|---|---|---|
| `HHVacancySber/HHVacancySber/VacancySearchViewModel.swift:96` | После уточнения контракта числовому значению нужна видимая подпись | Unit expectations для `3/1/0/5`: код 65, четыре падения | `String(count)` заменён на `"Показано вакансий: \(count)"` | Целевой unit-тест: код 0, testing 1,241 с |
| `HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift:65,70,76,87,128,173` | XCUITest macOS отдаёт полный текст этого SwiftUI `Text` через AX `value`; `.label` остаётся пустым | Проверка `.label` полного текста упала; xcresult показал `""` вместо `"Показано вакансий: N"` | Шесть assertions читают `.value as? String` и ожидают полный видимый текст | Целевые четыре UI-теста: 4/4, код 0, testing 94,649 с |
| `REFACTOR_REPORT_2026-09-04.md` | Нужен воспроизводимый отчёт текущего запуска | Не относится к production | Этот документ перезаписан по фактам текущего прогона | Финальные Git-проверки после записи |

Пробная строка `.accessibilityLabel(...)` в production view была полностью удалена после красного результата и в итоговый diff не входит. Возврат подписи совпадает с версией ViewModel в HEAD, поэтому сам ViewModel снова чист относительно HEAD.

Сохранены пользовательские изменения компактной статистической PDF-строки, кнопки начального обновления с геометрией toolbar и удаления служебных status messages. Числовой счётчик изменён по уточнению пользователя: подпись возвращена, а число продолжает следовать наложенным фильтрам.

## 4. Тесты

Новых тест-кейсов не добавлено и существующие проверки не ослаблены. Исправлена механика чтения результата в четырёх существующих UI-тестах. Добавленный пользователем `testInitialRefreshButtonMatchesToolbarButton` существовал до этого прогона и не приписывается ему.

| Проверка | Результат |
|---|---|
| Первая попытка production accessibility label | Код 65; те же 4 теста и 6 assertions упали; wall 104,06 с, testing 97,907 с; гипотеза отвергнута, строка удалена |
| Целевые четыре UI-теста после test-only исправления | Код 0; 4/4, 0 failures; wall 96,80 с, action 95,865 с, testing 94,018 с |
| Финальный U | Код 0; 85 total / 1 skip / 0 fail; wall 12,55 с, testing 10,926 с |
| Финальный F | Код 0; 96 total / 1 skip / 0 fail; wall 146,38 с, testing 145,169 с |
| Финальный P | Код 0; 72 tests, OK; wall 18,98 с, unittest 18,732 с |
| Красный unit после уточнения подписи | Код 65; 1 test, 4 assertions (`3/1/0/5`) |
| Зелёный unit после возврата подписи | Код 0; 1/1; testing 1,241 с |
| Зелёные UI-тесты полного текста после фильтров | Код 0; 4/4; testing 94,649 с |

Штатный skip — opt-in live HH test; его условие и число пропусков не менялись. UI — 11 тестов, unit — 85. Сеть, случайные данные, sleep-based новые синхронизации и новые зависимости не вводились. `Error writing attachment data` от Xcode наблюдался при целевом UI и unit прогоне; он не менял коды процессов и xcresult totals, но означает неполные screenshot/PDF attachments.

Отклонены: фиксация production accessibility API ради теста (не устранила проблему), дублирующие тесты, изменение ожидаемых чисел, ретраи UI assertions и запуск live API.

## 5. Экраны

Новых экранов и production-вёрстки нет. `/design` — `[НЕ ВЫПОЛНЕНО]`: callable-команда отсутствует, а исправление относится к XCUITest semantics, не к дизайну.

| Состояние / область | Текущее покрытие | Пробел |
|---|---|---|
| Initial / toolbar | Launch, геометрия initial refresh и toolbar, отсутствие внешних filter labels | Полный визуальный screenshot-аудит attachment не сохранился |
| Results / filters | Успешный поиск, lazy detail, employer и region filters, combined no matches, точный счётчик | Нет отдельного stale-result сценария |
| Empty / search error | Явный empty и search failure; statistics остаётся доступной при пустом combined filter | Loading и cancellation не приняты отдельными UI-тестами |
| Favorites / PDF commands | Режим избранного, согласованная геометрия personal/statistics buttons | Native save/replace/recovery dialogs, success/failure messages не покрыты полностью |
| Details | Успешная lazy загрузка в UI; переходы дополнительно покрыты unit | Нет отдельных UI-сценариев detail error/cancel/race |
| Persistence warnings | Unit state machine и сохранение входят в suite | Нет отдельного UI-теста warning/retry |

Подтверждённый владельцем UI-контракт: в `VacancySearchViews.swift:92–119` единственный текстовый статус имеет вид `Показано вакансий: N`, где `N` — количество после текущих фильтров; рядом могут находиться управляющие элементы экспорта. `statusMessage` и `statisticsPDFExportMessage` в эту строку выводиться не должны. Реализация соответствует контракту, а полные строки для `3`, `1` и `0` проверены зелёными UI-тестами.

## 6. PDF

PDF production-код этим прогоном не менялся. Проверен существующий pipeline:

- Экспорт использует локальный value snapshot до `await`; порядок стабилен относительно входного snapshot.
- HTML очищается, remote resources не загружаются; missing-data не подменяются нулями.
- A4/layout/pagination и разбиение частей сохранены; документы валидируются через CGPDFDocument/PDFKit до публикации.
- Один файл записывается атомарно; несколько частей проходят staged validation, backup/publish/rollback, identity/digest/collision checks. Recovery/quarantine и `.cleanup_forbidden` не упрощались.
- Существующие unit-тесты проверяют страницы, текст/порядок и однократность вакансий, ссылки и fallback-поля, статистические фильтры, фиксированную report date/filename, cancellation, rollback, сохранность чужого файла и восстановление backup. Все входят в зелёные 85 unit-тестов.
- Пользовательская правка типографики статистической строки проверяется unit assertions и прошла; она не является нашей правкой.

Визуальный рендер PDF по правилам PDF skill — `[НЕ ВЫПОЛНЕНО]`: успешный unit xcresult сообщил `Error writing attachment data`, а поиск внутри него не нашёл ни PDF, ни attachment-файлов. Поэтому текущий прогон доказывает структуру/текст/транзакционную безопасность тестами, но не визуальную целостность реального сохранённого артефакта.

Бинарная детерминированность metadata/document ID — `[НЕ ВЫПОЛНЕНО]`: `FavoriteVacanciesPDFExporter.swift:2056` создаёт `CGContext(..., nil)`, поэтому Quartz управляет частью метаданных/ID. Фиксированные report date/filename не равны byte-for-byte детерминированности. Изменение этого контракта требует отдельного решения.

Готовые Data частей удерживаются до публикации; реальный disk-full, crash/power-loss, peak RSS/CPU и межверсийная Quartz-идентичность не воспроизводились.

## 7. Намеренно не изменено

Не менялись архитектура, MainActor/actor boundaries, API parameters/headers, retry/cooldown, cache policies, JSON schema/migration, persistence ownership, фильтры/tie-breakers, локаль/шрифты/pagination PDF, recovery transaction, CI, project.pbxproj, scheme, signing/build settings, assets/icons, release tooling и benchmark fail-fast.

Не добавлялись dependency, lint/formatter, новая схема, абстракционные слои или suppressions. Не выполнялись commit, add, stash, reset, checkout, release, DMG, publication и live test. Пользовательские изменения не переписывались, кроме явно запрошенного возврата подписи счётчика и соответствующих test expectations.

## 8. Отложено

| Вопрос | Факт / граница | Минимальный следующий шаг |
|---|---|---|
| Полная UI-матрица и screenshots | Нет отдельных loading/stale/detail error-cancel/persistence warning/native dialog сценариев; attachments потеряны | Детерминированные UI fixtures и отдельная проверка сохранения attachments |
| Details cache без TTL/cap | Сессионный cache; изменение влияет на freshness/память/сеть | Согласовать freshness contract и измерить длительный workload |
| Progressive search / retries / cooldown | Выдача после полного сбора; один completeness retry | Определить контракт partial results/errors и разрешённые нагрузочные метрики |
| PDF Data buffers / oversized vacancy | Части удерживаются до publish; большой документ может дать высокий peak | Изолированный benchmark RSS/CPU на фиксированных данных |
| Recovery cleanup | Каталоги намеренно сохраняют backup и доказательства | Owner-approved symlink-safe lifecycle; не удалять автоматически |
| PDF metadata/document ID | Нет injection seam в CGContext | Согласовать production/test contract, затем повторяемое byte comparison |
| Disk-full/crash/OS matrix | Инъекция отказов не равна аппаратным и межверсийным сценариям | Отдельный стенд и поддерживаемая матрица Xcode/macOS |

Неподтверждённые случаи не исправлялись спекулятивно: это изменило бы контракты или архитектуру за пределами разрешённого минимального исправления.

## 9. Проверки

| Проверка | Итог |
|---|---|
| Debug unit `test -only-testing:HHVacancySberTests build analyze` | Код 0; 85 / 1 skip / 0 fail; wall 12,55 с |
| Полный Debug test | Код 0; 96 / 1 skip / 0 fail; wall 146,38 с |
| После возврата подписи: целевой unit | Код 0; 1/1; testing 1,241 с |
| После возврата подписи: четыре затронутых UI-теста | Код 0; 4/4; testing 94,649 с |
| Release build analyze | Код 0; wall 8,35 с; диагностик нет |
| Python unittest | Код 0; 72 tests, 18,732 с; OK |
| `git diff --check` | Код 0, пустой вывод |
| `bash -n scripts/benchmarks/build.sh` | Код 0, пустой вывод |
| Staged diff | Пуст |
| project.pbxproj / scheme diff | Пуст |
| Добавленные строки на типовые credential assignments | Совпадений нет; секреты не выводились |
| Внешний CI / release / DMG / live HH | `[НЕ ВЫПОЛНЕНО]` по запрету |
| Визуальный PDF/screenshot QA | `[НЕ ВЫПОЛНЕНО]`: Xcode attachment write failure |

Acceptance-порог полного Debug выполнен: 96 ≥ 87; число штатных пропусков фиксировано — 1; новых warnings компилятора/analyzer не зафиксировано. Локальная среда не выдаётся за внешний CI или полную OS/Xcode matrix.

## 10. Git

Исходно изменены пять пользовательских файлов, staged diff отсутствовал. После уточнения подпись `Показано вакансий: N` возвращена к состоянию HEAD, поэтому `VacancySearchViewModel.swift` больше не входит в итоговый Git diff. Шесть UI assertions используют AX `value` и проверяют полный текст; неуспешные production/accessibility гипотезы удалены. Дополнительно перезаписан этот tracked report.

После возврата подписи `git status --short` показывает пять modified paths: четыре оставшихся исходных файла плюс `REFACTOR_REPORT_2026-09-04.md`. Staged diff, project/scheme diff и `git diff --check` пусты; secret scan добавленных строк и `bash -n scripts/benchmarks/build.sh` завершились кодом 0. Коммиты, ветки, index, stash, remote и пользовательские файлы вне этой области не изменялись.

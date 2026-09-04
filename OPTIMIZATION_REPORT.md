# Отчёт по надёжности и ресурсной оптимизации HHVacancySber

Актуальное продолжение от **4 сентября 2026 года** находится в разделе «Повторная проверка после добавления статистического PDF» в конце этого документа. Разделы выше него — сохранённый исторический отчёт предыдущего этапа; его baseline и численные выигрыши не относятся к новым изменениям.

Дата проверки: 3 сентября 2026 года. Исходный коммит: `c8d268eacffa83c5fa5ac1960b2b69844a46ef6e`, ветка `main`.

Дополнение того же дня: по отдельному пользовательскому запросу после основных performance-замеров все заголовочные и основные PDF-шрифты уменьшены ещё на 2 pt. Таблицы ниже изолируют эффект предшествующей оптимизации pipeline и не приписывают typography change дополнительный выигрыш. После изменения типографики полный unit-набор был повторён.

## A. Repository baseline

- Стек установлен по `README.md`, Xcode project, CI и исходному коду: нативное macOS 13+ приложение на Swift 5 / SwiftUI + AppKit, Foundation `URLSession`, Core Graphics/AppKit PDF; Xcode project без Swift Package Manager и внешних runtime-зависимостей.
- Среда измерений: arm64, macOS 13.7.8 (22H730), Xcode 15.2 (15C500b), Swift 5.9.2. Release — штатная конфигурация Xcode `Release`; отдельного benchmark target нет.
- Persistence: JSON-файл избранного в Application Support; справочник регионов HH кэшируется на диске на 7 суток. Backend/frontend IPC отсутствует: это один процесс SwiftUI.
- Repository-specific `AGENTS.md`, lock-файлы, lint/format-конфигурация и отдельная stack specification не обнаружены. Действующая спецификация — `README.md`, project settings и CI `.github/workflows/ci.yml`.
- Перед работой staged и untracked изменений не было. Уже существовал unstaged diff в `HHVacancySberUITests/HHVacancySberUITests.swift` (+16/−2); он принадлежит пользователю и не редактировался в этой работе.
- Baseline: Debug build, Release build, `xcodebuild analyze`, 35 unit-тестов и 71 тест release tooling прошли. Отдельный lint/formatter отсутствует. Системные предупреждения Xcode о недоступном CoreSimulator в sandbox не являлись предупреждениями компилятора и исчезали при запуске Xcode вне sandbox.

## B. Measurement methodology

Измерения сделаны до изменения кода и после него на одном компьютере, в `-O`, с одним Swift toolchain и одинаковыми данными. PDF harness компилировался вместе с production `HHModels.swift` и `FavoriteVacanciesPDFExporter.swift`; каждый основной замер запускался в новом процессе три раза, ниже приведены медианы. `ru_maxrss` использован для peak RSS, `CFAbsoluteTimeGetCurrent` — для wall-clock. Отдельный проход через реальную публикацию измерял размер PDF.

Workload:

| Класс | Вакансии | HTML-абзацы на вакансию | Входной HTML, байт | Страницы | Части |
|---|---:|---:|---:|---:|---:|
| small | 10 | 12 | 33 380 | 10 | 1 |
| medium | 100 | 12 | 333 800 | 100 | 1 |
| large Favorite | 500 | 12 | 1 669 000 | 500 | 5 |
| stress-but-valid | 1 | 1 200 | 336 090 | 37 | 1 |

Данные синтетические, но используют реальные production model, HTML sanitizer, formatter, AppKit layout, pagination, Core Graphics renderer, 100-страничное разбиение и validator. Они включают кириллицу и Unicode. Сеть измерялась только на существующем actor mock с точной пагинацией; production HH не нагружался. Локальный microbenchmark sanitizer выполнен 5 раз по 1 000 преобразований.

Ограничения: Instruments недоступен в автоматическом тестовом контуре; достоверные allocation count, CPU time, startup latency и энергия не получены и поэтому не объявляются улучшенными. Peak RSS включает runtime процесса. Размер PDF измерен отдельным publish-проходом; он не включён в сопоставляемое время подготовки. Малые времена чувствительны к прогреву системного font registry.

## C. Исходные метрики

| Workload | Peak RSS, медиана | Wall-clock, медиана | PDF bytes |
|---|---:|---:|---:|
| small | 25 837 568 B (24,64 MiB) | 0,1796 s | 68 267 |
| medium | 45 645 824 B (43,53 MiB) | 1,3828 s | 380 155 |
| large Favorite | 149 258 240 B (142,34 MiB) | 6,8379 s | 1 908 920 |
| stress-but-valid | 63 225 856 B (60,30 MiB) | 1,2215 s | 120 772 |

- Baseline sanitizer: 7,0898 s median на 1 000 вызовов (5 запусков).
- Release `.app`: 2 092 KiB по `du`; сумма логических размеров файлов 2 126 276 B; executable 2 019 784 B.
- HH mock: обычный leaf из одной вакансии — 2 search-запроса; partitioned набор 2 001 уникальной вакансии — 24 запроса. Дубликатов на выходе нет. Live bytes, latency, status-code rate и retries не измерялись.
- Baseline repeated-export RSS не был инструментирован; для этой метрики доступно только финальное soak-наблюдение, поэтому сравнительного улучшения не заявлено.

## D. Найденные bottlenecks

1. `FavoriteVacanciesPDFExporter.swift`: весь Favorite сначала превращался на `@MainActor` в массив полных `NSAttributedString`, затем во все page objects, а worker ещё раз создавал полные PDF buffers. На 500 страницах peak RSS был 142,34 MiB. Severity: высокая для большого Favorite; затронуты память и UI.
2. Там же: пагинация каждой страницы создавала временный остаток всего непройденного attributed document; временные AppKit-графы жили дольше необходимого. Stress-документ давал 60,30 MiB RSS. Severity: средняя.
3. `VacancyHTMLAttributedText`: семь одинаковых `NSRegularExpression` компилировались при каждом sanitize. 1 000 вызовов занимали 7,0898 s. Severity: средняя в массовом PDF export, низкая для единичной карточки.
4. `VacancyCollectionService.swift`: count-probe `per_page=1` всегда повторно запрашивал page 0 с `per_page=100`. Это удваивало search-вызов для обычного небольшого leaf. Severity: средняя по числу запросов, без дефекта корректности.

## E. Выполненные optimization-порции

### Порция 1 — bounded PDF preparation

**Проблема.** Полная материализация formatted documents и всех страниц происходила до worker, часть CPU-bound AppKit работы выполнялась на main actor, а все страницы удерживались до публикации.

**Доказательство / baseline.** 500 вакансий: 149 258 240 B peak RSS, 6,8379 s; кривая памяти росла почти пропорционально общему числу сохранённых страниц.

**Гипотеза.** Форматирование и layout внутри единственного actor, немедленный render каждой порции максимум 100 страниц и освобождение page-local объектов сократят lifetime и число одновременно живущих представлений.

**Инварианты.** Snapshot и порядок входных вакансий; максимум 100 страниц в файле; HTML semantics; semantic completeness; atomic publication/rollback; main-actor progress; одна тяжёлая job; отсутствие внешних ресурсов.

**Изменение.** Worker теперь принимает immutable value snapshot, последовательно format/layout/render-ит вакансии, держит максимум одну 100-страничную порцию и сохраняет только компактные validated `Data` частей. Personal export также форматируется в worker. Для page-local layout добавлен `autoreleasepool`; cancellation проверяется между вакансиями, частями и страницами. При отмене directory/replacement выбора подготовленные buffers явно освобождаются.

**Correctness verification.** Добавлены тесты 101 вакансии → ровно 100+1 страниц в двух валидных PDF, main-thread progress, cancel → успешный следующий export, personal atomic file и oversized Unicode/continuous string без потери символов. Существующие transaction tests сохранены. Unit, UI, Release и Analyze прошли. Последующий typography test проверяет 18 pt для title, 13 pt для section heading, 9,5 pt для label и 7,5 pt для body.

**Результат измерения.** Сопоставимый prepare benchmark:

| Workload | Baseline RSS | Final RSS | Δ RSS | Baseline time | Final time | Δ time |
|---|---:|---:|---:|---:|---:|---:|
| small | 25 837 568 | 24 346 624 | −1 490 944 (−5,77%) | 0,1796 s | 0,13374 s | −25,53%* |
| medium | 45 645 824 | 27 852 800 | −17 793 024 (−38,98%) | 1,3828 s | 0,69865 s | −49,48% |
| large | 149 258 240 | 40 615 936 | −108 642 304 (−72,79%) | 6,8379 s | 3,1733 s | −53,59% |
| stress | 63 225 856 | 43 778 048 | −19 447 808 (−30,76%) | 1,2215 s | 1,18722 s | −2,81%* |

`*` Малый timing и 2,81% stress timing не считаются доказанным ускорением из-за font warm-up/noise. PDF sizes и page counts не изменились: 68 267 / 380 155 / 1 908 920 / 120 772 B и 10 / 100 / 500 / 37 страниц.

**Trade-offs.** Вместо page objects до выбора каталога удерживается до пяти compressed PDF `Data` общей длиной 1,91 MB для large workload. Это bounded по 100 страницам на render stage, но совокупные готовые buffers всё ещё линейны размеру итоговых PDF. Executable вырос на 46 624 B (+2,31%).

**Решение.** Оставить: крупный повторяемый выигрыш памяти, тяжёлая работа ушла с main actor, output contract подтверждён.

### Порция 2 — reuse compiled HTML regular expressions

**Проблема.** На каждую вакансию повторно компилировались семь постоянных regex.

**Доказательство / baseline.** 1 000 sanitize: 7,0898 s median.

**Гипотеза.** Один раз созданные immutable `NSRegularExpression` устраняют повторный parsing pattern без cache growth. Apple документирует `NSRegularExpression` как immutable и thread-safe: [Foundation NSRegularExpression](https://developer.apple.com/documentation/foundation/nsregularexpression).

**Инварианты.** Точные patterns, порядок замен, допустимые tags/URLs и malformed-input fallback.

**Изменение.** Семь expressions стали bounded static constants; no user data cache.

**Correctness verification.** Concurrent test из 100 tasks возвращает один и тот же sanitized Unicode result; опасные tags/attributes/URLs удаляются. Полный suite прошёл.

**Результат измерения.** 0,047589 s median; −7,042211 s, или −99,33% на microbenchmark. Значимый end-to-end эффект включён в PDF-таблицу порции 1; отдельно суммировать проценты нельзя.

**Trade-offs.** Несколько малых regex постоянно живут до завершения процесса; размер строго ограничен.

**Решение.** Оставить.

### Порция 3 — reuse первой HH search page

**Проблема.** `per_page=1` probe и последующий `page=0, per_page=100` были дубликатами одного leaf.

**Доказательство / baseline.** Mock: 2 запроса для leaf с одной вакансией; 24 для partitioned 2 001 IDs.

**Гипотеза.** Probe с production page size 100 можно одновременно использовать как первую страницу, сохранив `found` checks и ID-dedupe.

**Инварианты.** Полнота `result.count == found`, стабильные IDs, официальная глубина 2 000, partitioning, progress и единственная completeness retry на уровне employer.

**Изменение.** `probe` возвращает весь response; `fetchLeaf` принимает его, добавляет page 0 и начинает цикл с page 1.

**Correctness verification.** Новые request-count tests: 1 уникальный ID/1 request и 2 001 IDs/22 requests; существующие mismatch/completeness/partition tests прошли.

**Результат измерения.** Обычный leaf: 2 → 1 (−50%); fixture partitioning: 24 → 22 (−8,33%), или примерно 12,0 → 11,0 запроса на 1 000 уникальных вакансий. Duplicate ratio остался 0.

**Trade-offs.** Для oversized корневого запроса, который затем partition-ится, probe получает 100 summaries вместо 1; в fixture суммарно получено 2 101 response items вместо 2 004 (+97, +4,84%), хотя запросов меньше. Реальные bytes не измерялись. Для доступного leaf исчезает повторная передача всей page 0.

**Решение.** Оставить: число запросов снизилось в обоих измеренных сценариях, полнота сохранилась, а payload-регрессия ограничена probe oversized root и не размножается в последующих pages. Реальное соотношение обычных и oversized работодателей неизвестно; требуется production telemetry, прежде чем делать дальнейшую адаптацию.

## F. Отклоненные эксперименты

1. Прямая запись Core Graphics PDF в конечный writer могла убрать совокупный массив готовых `Data`, но усложнила бы уже защищённую digest/identity/backup/rollback transaction и повысила риск потери существующего файла. После batching итоговые buffers large workload — 1,91 MB при RSS 38,73 MiB; дополнительный риск непропорционален остатку. Изменение не делалось.
2. Единый долгоживущий `NSLayoutManager` вместо page-local layout выглядел перспективно для stress-документа, но потребовал бы менять paragraph-boundary semantics и поведение oversized block. Наблюдаемое конечное stress-ускорение всего 2,81% находится около шума; redesign отклонён.
3. Увеличение HH concurrency и поиск максимального RPS отклонены без эксперимента на production: текущий общий gate уже serial/bounded, а официальная документация не задаёт универсальный безопасный RPS. Нельзя проверять предел через 429/CAPTCHA.
4. Автоматическое удаление PDF transaction directory после успешной публикации отклонено: текущая реализация сознательно сохраняет recovery evidence и помечает cleanup forbidden. Без descriptor-relative, symlink-safe удаления такая «чистка» ухудшила бы security/correctness.
5. `clusters`, `responses_count_enabled`, progressive search UI и snapshot analytics оценены, но не внедрены: в продукте нет статистического persistence/aggregation контракта; добавление меняло бы назначение и архитектуру без workload и baseline.

## G. HeadHunter API

### Архитектура

`SwiftUI/ViewModel → VacancyCollectionService → HHAPIClient → shared HHRequestGate → URLSession → Decodable models → dictionary by vacancy ID → sorted VacancySearchResult → ViewModel/UI`. Справочник area имеет 7-дневный disk cache. Favorites сохраняют нормализованные value models. Detail Tier B загружается лениво при раскрытии карточки или явно нужном PDF export; массового N+1 при search нет.

### Safety

- OAuth application Bearer token берётся через provider; значение token не логируется и не выводилось при проверке.
- Оба `User-Agent` и `HH-User-Agent` содержат имя приложения и контакт, без маскировки под браузер.
- Все calls проходят через один actor gate: concurrency 1, равномерный минимум 250 ms между запросами, поэтому нет burst и не создаётся N tasks на N вакансий.
- 429 с `Retry-After`, CAPTCHA, 401/403 и server errors типизированы. CAPTCHA/429 считаются terminal для текущего bulk archive/enrichment, автоматического обхода и tight retry нет.
- `URLSession.data(for:)` поддерживает cancellation; service проверяет cancellation между страницами/работодателями, новый ViewModel search отменяет старый task. Gate waiter пока не cancellation-aware до получения slot.
- Специальный retry/backoff/circuit breaker отсутствует. Это консервативно исключает retry storm, но transient failure завершает сбор; единственная bounded повторная попытка относится к completeness mismatch. Explicit connect/total timeout не настроен — действуют URLSession defaults.

Актуальные правила сверены с [официальной документацией HH API](https://api.hh.ru/openapi/redoc): `per_page` до 100, выдача до 2 000 элементов, официальные date/filter partitions, application token и client identification. Документация также подтверждает `clusters`, `responses_count_enabled`; параметр `schedule` помечен deprecated в пользу новых work-полей. Неаутентифицированный доступ может потребовать CAPTCHA; приложение использует OAuth.

### Network efficiency и progressive loading

Измеренные before/after числа приведены в порции 3. Bytes, latency, retry rate, queue depth и time-to-first-visible не инструментированы. Search parsing выполняется один раз, raw `Data` не сохраняется после decode, ID dictionary дедуплицирует overlap. UI получает progress, но коллекция публикуется только после полного employer collection; page-by-page visible results отсутствуют. Prefetch отсутствует. Менять это без redesign state/error/completeness semantics не стали.

### Analytics

Отдельного statistics engine, timestamped raw snapshots, streaming accumulators и server aggregates в продукте нет. Search models сохраняют ID, employer, area, salary range/currency/gross и publication timestamp, не превращая `null` в ноль; детали добавляют skills/description. Полный сбор >2 000 использует area → date → experience/work format/legacy schedule partitions и ID-dedupe. Live search не объявляется immutable historical snapshot.

## H. PDF generation

Pipeline после изменения: `stable [VacancySearchResult] snapshot → single PDF actor → sanitize/format → page-local layout → ≤100-page batch → Core Graphics Data → PDF validation → staged atomic writes → identity-checked backup/publish/rollback → cleanup warning/recovery location`.

Baseline/final и scaling приведены в порции 1. Large Favorite: 500 вакансий, 500 страниц, 5 частей, 1 908 920 B; peak RSS 142,34 → 38,73 MiB, median 6,8379 → 3,1733 s. Это остаётся последовательной bounded job, без насыщения CPU параллельным rendering.

Надёжность:

- Snapshot ordering сохранён; нет page/item parallelism.
- Cancellation boundaries есть между vacancy/page/part/write stages; отменённая подготовка освобождается, следующий export проверен.
- Каждый staged PDF валидируется до замены destination. Transaction сохраняет исходные файлы, проверяет identity/digest и умеет rollback; partial output не возвращается как success.
- Permission/destination-replacement/rollback paths покрывались существующими tests. Реальный disk-full не инъецировался.
- Success transaction directory намеренно сохраняется и возвращается пользователю как cleanup warning; это существующий safety contract, а не утечка, исправленная данной порцией.
- Soak prepare/discard: 12 последовательных циклов по 500 вакансий, 500 страниц; 38,156 s, без failures. Resident bytes: 40,3 → 44,6 → 45,1 → 46,5 → 46,7 → 50,9 → 51,0 → 51,8 → 51,9 → 52,1 → 52,2 → 52,3 MB. Рост замедляется, но без Instruments это не доказывает отсутствие leak; filesystem publication в soak не повторялась.
- Unicode/кириллица/long unbroken string и 1 200-paragraph oversized content проверены; page strings полностью реконструируют вход, PDF validator видит все страницы. Remote fonts/images/CSS не загружаются.

Внутренний бюджет, основанный на измерении текущего arm64 Mac: для fixture из 500 страниц prepare должен оставаться ниже 64 MiB peak RSS, в одной тяжёлой job и с частью не более 100 страниц. Это regression budget для данного workload, не универсальный product limit.

## I. Очистка проекта

- После смены pipeline удалены ставшие неиспользуемыми `PDFAttributedDocument`, `VacancyPages` и helper `parts(for:)`; reference search подтвердил отсутствие consumers, сборка/тесты — отсутствие dynamic/build usage.
- Проверены `.bak`, `.old`, `.orig`, logs, debug dumps, `.DS_Store`, repo build/cache artifacts, abandoned manifests и пустые каталоги: доказанного repository garbage не найдено, поэтому файлы не удалялись.
- Внешних зависимостей нет; удалять dependency/lock file нечего.
- Временные benchmark binaries, sources, module cache и DerivedData создавались только в `/private/tmp` и удалены после финальной проверки; authoritative repository ими не загрязнён.

## J. Намеренно не изменено

- Progressive page publication, incremental statistics, long-term snapshots и server-side aggregates: требуют нового продуктового состояния, persistence schema и UI error semantics.
- HH gate scheduling/priority, cancellation-aware waiter, exponential retry/jitter, explicit timeouts и circuit breaker: разумные направления, но нет production telemetry по latency/failures/429 и безопасного baseline для параметров.
- `per_page` 100 не заменён адаптивным размером: отсутствуют реальные payload/first-result/UI-render measurements.
- Deprecated `schedule` partition не мигрирован: нужна сверка фактических dictionary values и backward-compatible completeness на реальных работодателях.
- PDF transaction/recovery implementation и сохранение transaction directory: security-critical; упрощение cleanup без доказательства опасно.
- Полный streaming writer, subprocess isolation, parallel renderer, font subsetting и cache страниц: текущий stack локальный, output мал, а память после batching в бюджете; сложность и риск выше доказанной пользы.
- Existing user diff в UI tests не форматировался и не «очищался».

## K. Финальные проверки

Фактически выполнено:

- `xcodebuild ... -configuration Debug ... build` — exit 0.
- `xcodebuild ... -configuration Release ... build` — exit 0.
- `xcodebuild ... analyze` — exit 0.
- `xcodebuild ... test -only-testing:HHVacancySberTests` после основной оптимизации — exit 0, 41 test, 1 skipped, 4,859 s; после typography change — exit 0, 42 test, 1 skipped, 5,310 s.
- `xcodebuild ... test -only-testing:HHVacancySberUITests` с `CODE_SIGNING_ALLOWED=NO` — infrastructure failure до выполнения: runner killed during bootstrap. Повтор без отключения подписи — exit 0, 7 tests, 99,259 s.
- `/usr/bin/python3 -m unittest discover -s scripts/tests -v` — 71 tests, 21,445 s, OK.
- Targeted HH request/completeness tests и PDF pagination/publication/cancel/personal/concurrency/typography tests входят в прошедшие 42 unit tests.
- Release `git diff --check` — чисто. Новые dependency/lock changes отсутствуют.
- PDF benchmark: 3 независимых процесса на каждый из 4 workloads; sanitizer: 5 запусков; soak: 12 циклов в одном процессе.
- Отдельные lint, formatter и benchmark команды в проекте отсутствуют и поэтому не запускались.

## L. Остаточные риски

1. Нет production HH telemetry: неизвестны реальные bytes, p50/p95 latency, 429/5xx, request queue wait и распределение размеров 11 работодателей. Live API сознательно не использован для нагрузочных измерений.
2. Shared HH gate serial и ровный, но waiter не реагирует на cancellation до своего slot; URLSession использует default timeouts; transient errors не retry-ятся. Изменять без наблюдаемости рискованно.
3. Search UI не progressive: первая вакансия видна только после полного согласованного сбора. Это известная UX/architecture граница, не regression.
4. PDF сохраняет все compressed part `Data` до выбора каталога/публикации; для 500 страниц это 1,91 MB, но при экстремально больших графических документах может расти. Текущий PDF не включает изображения.
5. Успешные transaction directories сохраняются по действующему recovery contract и требуют ручной cleanup warning. Безопасная автоматическая очистка не доказана.
6. Soak показывает рост resident set примерно до 52,3 MB и замедление роста, но не содержит baseline, allocation graph, open-handle count или повторную filesystem publication; отсутствие leak окончательно не доказано.
7. Совместная production-сессия «live HH + большой PDF + ручной UI» не запускалась, чтобы не нагружать HH и не автоматизировать production credentials. Её локальные составляющие проверены mock HH, background PDF actor, main-actor progress и UI suite, но end-to-end memory/latency этого сочетания не измерены.
8. Release bundle вырос на 44 KiB blocks (2 092 → 2 136 KiB); executable и logical bundle files выросли на 46 624 B. Это небольшой, но реальный trade-off за actor batching, cancellation и validation tests не входят в app binary.

---

# Повторная проверка после добавления статистического PDF — 4 сентября 2026

## A. Repository baseline

Исходная точка этого этапа — **рабочая копия**, а не чистый HEAD: `main`, `c8d268eacffa83c5fa5ac1960b2b69844a46ef6e`. Уже изменены PDF exporter, collector, ViewModel, views, unit/UI tests, README; этот отчёт уже был untracked. Staged diff пуст. Все эти изменения, включая шрифты PDF и 13 pt статусной строки, сохранены. Новые production-изменения этого этапа находятся только в `HHAPIClient.swift` и `VacancySearchViewModel.swift`.

Стек повторно сверен по README, project.pbxproj, shared scheme и `.github/workflows/ci.yml`: Swift 5 language mode, Swift 5.9.2, Xcode 15.2, arm64 macOS 13+, SwiftUI/AppKit, Foundation URLSession, Core Graphics PDF и JSON persistence. Runtime dependencies, package/lock-файлы, AGENTS.md и отдельная stack specification отсутствуют. CI canonical tests — Debug, release tooling — Python unittest; Release использует whole-module compilation.

Baseline: 58 unit-тестов (один opt-in live test пропущен), 71 Python-тест (19,744 s), Debug static analysis — успешно. Попытка выполнить unit suite непосредственно в штатном Release остановилась на `@testable import`: Release не включает `ENABLE_TESTABILITY`. Настройки продукта не менялись: функциональные тесты выполнены в Debug, измерения — в отдельном `swiftc -O` harness. Это ограничение команды, не дефект приложения. Release application binary baseline: 2 151 712 B. Его bundle после попытки `test` содержал test injection; размер такого bundle не используется для сравнения с чистым Release.

## B. Measurement methodology

Добавлены воспроизводимые `scripts/benchmarks/RuntimeBenchmarks.swift`, `build.sh`, README. Harness компилируется вместе с production-модулями; данные нормализованы, HH заменён actor-fixture. Сеть production не использовалась. Публичная HH OpenAPI specification скачана отдельно без токена; проверены search parameters, идентификация, ошибки и ограничения.

Измерения: `ProcessInfo.systemUptime`, `getrusage` user+system CPU и peak RSS (байты на macOS), `ps` для текущего RSS (KiB), `fcntl` для дескрипторов 0…1023. JSON содержит counters и semantic outcomes. По три независимых процесса на основной workload; soak — шесть записей в одном процессе. CPU/peak включают runtime, validation и PDFKit extraction; wall-clock включает 20 параллельных лёгких mock calls, heartbeat и диагностический `ps`. Это end-to-end synthetic diagnostic workload, а не чистый renderer microbenchmark и не полноценная сессия живого SwiftUI.

Изначальные sandbox PDF-прогоны не смешиваются с последующими unrestricted: sandbox менял доступ к font registry, число страниц pathological HTML и PDF bytes; `ps` возвращал unavailable (`-1`). Для таблицы ниже обе версии запускались unrestricted одинаковыми командами. PDF baseline binary `gate-fixed` уже содержит порцию 1, но PDF и enrichment-код в нём ещё исходные; `pdf`/`statistics` не вызывают gate, поэтому сравниваемый PDF pipeline одинаков. Результаты cancellation имеют отдельный original baseline binary.

Наблюдалась значительная фоновая вариативность (например, итоговые 500 страниц: 5,163…9,051 s). Поэтому небольшие отличия памяти/CPU не объявляются улучшением. Старые замеры 3 сентября не сравниваются с новыми: отличаются шрифты, fixture и включение публикации.

## C. Измеренные baseline → final

Точные поведенческие показатели (3 повтора каждого сценария):

| Сценарий | До | После | Разница |
|---|---:|---:|---:|
| Отмена queued HH request при активной операции 500 ms, медиана задержки | 483,65 ms | 0,072 ms | −483,58 ms, >99,9% |
| 100 favorites, первый detail бросает CancellationError: запросов | 100 | 1 | −99% |
| То же: вызовов exporter после cancellation | 1 | 0 | экспорт не продолжается |
| 100 favorites, первый detail возвращает 429: запросов | 100 | 1 | −99% |
| То же: вызовов exporter | 1 | 0 | явная остановка |
| Два экспорта 100 favorites: detail requests | 200 | 100 | −50% |
| Два экспорта: вызовов exporter | 2 | 2 | поведение сохранено |

Cancellation original range 469,88…494,82 ms; final 0,051…0,208 ms. Первое промежуточное исправление дало медиану 0,117 ms. Значим порядок величины, а не микросекундная точность scheduler.

PDF medians, 3 процесса на строку (время включает диагностику; renderer в этом этапе не менялся):

| Workload | Страницы | PDF bytes, до = после | Wall s до → после | CPU s до → после | Peak RSS B до → после |
|---|---:|---:|---:|---:|---:|
| 10 вакансий × 12 HTML-абзацев | 10 | 52 856 | 0,404 → 0,640 | 0,127 → 0,180 | 30 326 784 → 31 244 288 |
| 100 вакансий × 12 абзацев | 100 | 257 369 | 1,273 → 2,020 | 0,832 → 1,023 | 33 619 968 → 35 061 760 |
| 500 вакансий × 12 абзацев | 500 / 5 файлов | 1 296 520 | 5,202 → 5,252 | 3,966 → 4,039 | 64 634 880 → 59 277 312 |
| 1 вакансия × 1 200 абзацев | 32 | 96 859 | 0,974 → 0,973 | 0,698 → 0,693 | 32 735 232 → 35 962 880 |
| Статистика, 2 000 вакансий | 31 | 184 030 | 2,812 → 2,744 | 2,772 → 2,699 | 66 600 960 → 68 026 368 |

Ни ускорение PDF, ни снижение его RSS не заявляются. Малый/средний workload в этой серии медленнее; причинная связь с production diff не доказана (затронутые HH/enrichment-функции в этих режимах не вызываются), фоновые выбросы видны и на большом workload. Эти числа не используются как основание renderer-оптимизации. Размеры и page counts стабильны.

## D. Доказанные проблемы

1. `HHRequestGate.acquire`: suspended continuation не реагировала на cancellation. Cancelled task и её аргументы удерживались до получения slot; controlled trace показал ожидание практически всей оставшейся активной операции.
2. `preparedForPDF`: общий `catch` превращал cancellation/401/403/429/CAPTCHA в локальный fallback, поэтому bulk loop продолжал следующие запросы и вызывал exporter. Mock счётчик — 100 запросов вместо остановки после первого. Высокий приоритет: cancellation и соблюдение ограничений HH.
3. Та же функция записывала успешные details в существующий session cache, но не читала его. Повторный PDF заново запрашивал те же 100 IDs, хотя UI уже использует этот cache. Средний приоритет: избыточная сеть.

## E. Выполненные порции

### Порция 1 — cancellation-aware HH queue

**Гипотеза:** удаление отменённого waiter из actor-owned очереди немедленно завершит запрос без ожидания активного HTTP. **Инварианты:** один активный запрос, порядок оставшихся waiters, прежний pacing 250 ms после завершения, cancellation не забирает чужой slot, continuation возобновляется ровно один раз.

**Изменение:** waiter получает UUID и throwing continuation; cancellation handler отправляет actor сообщение. Проверяется cancellation до acquire и внутри регистрации continuation. Если slot уже передан, существующий `Task.checkCancellation` завершает task с нормальным release. Добавлен read-only queue count для диагностики/тестов. Сложность удаления O(queue length) оставлена простой: размеров, оправдывающих другую структуру, не обнаружено.

**Проверка:** отмена queued task до освобождения active operation, 200 операций с гонками cancel/release, cancellation during pacing, последующий успешный request, прежний serialization test. **Результат:** 483,65 → 0,072 ms median. **Trade-off:** маленький UUID на waiter и короткая actor task при cancellation; нет polling и network retry. **Решение:** оставить.

### Порция 2 — остановка PDF-enrichment

**Гипотеза:** cancellation и terminal HH errors нельзя трактовать как recoverable detail failure. **Изменение:** checks между favorites и перед exporter; cancellation после HTTP проверяется до cache update; cancellation и тот же набор access errors, что уже останавливает archive check, пробрасываются. ViewModel сбрасывает flags/progress через defer и сохраняет объясняющий статус. **Инварианты:** 404/timeout всё ещё дают явно помеченный local fallback; локальные полные details не требуют сети; оригинальные файлы не затрагиваются до writer.

**Проверка:** все шесть access errors, task cancellation in-flight, CancellationError от клиента, восстановление после ошибки, сохранение fallback каждого элемента и zero-request export persisted details. **Результат:** 100 → 1 requests; exporter 1 → 0 при остановке. **Trade-off:** после ограничения доступа bulk export теперь завершается ошибкой, а не пытается завершиться с локальными данными всех остальных карточек. Это намеренное safety-исправление, прямо требуемое заданием. **Решение:** оставить.

### Порция 3 — reuse существующего detail cache

**Гипотеза:** повторный экспорт может использовать тот же успешный session cache, который уже используется карточками. **Изменение:** lookup перед HTTP, без нового cache и без изменения persistence/schema/срока его жизни. **Инварианты:** source с полными details приоритетнее cache; ошибки не кэшируются; source ID/location/local metadata сохраняются.

**Проверка:** два экспорта имеют одинаковые IDs/details, во втором нет сети даже если mock теперь возвращал бы 429; после recoverable failure следующая попытка заново обращается к HH и получает полный документ. **Результат:** 200 → 100 requests, оба exporter calls сохранены. CPU 5,24 → 3,91 ms на synthetic preparation слишком мал для общего заявления об ускорении; доказан только счётчик сетевых запросов. **Trade-off:** прежняя session-cache freshness policy теперь применяется и к PDF. **Решение:** оставить.

## F. Отклонённые эксперименты и измерения

- Полный Release unit run без testability: отклонена смена production settings ради теста; использован canonical Debug suite и отдельный `-O` harness.
- Сравнение sandbox/unrestricted PDF: отклонено, поскольку различается font registry и layout. Sandbox RSS=-1 не интерпретировался как метрика.
- Первый statistics harness остановился на точной PDFKit-строке из-за уже известной macOS 13 подстановки кириллической `к` glyph-ом U+0138. Исправлена только normalization проверки, аналогично существующим tests; PDF-код не менялся. Все три страницы контрольного файла визуально проверены Poppler. Четыре scratch-каталога после этих прерванных harness runs удалены; это не runtime crash приложения.
- Новая оптимизация renderer/grouping/сортировок отклонена: нет измеренного production hotspot, а timing плавает. Не вводились streaming writer, parallel rendering, новые caches или зависимости ради искусственной скорости.

## G. HeadHunter API

Flow остался `UI → typed request → collector → HHAPIClient → shared actor gate → URLSession → Decodable → ID dedupe → normalized values → UI / local report`. Поиск не делает detail N+1. Local filters/statistics не обращаются к HH; page 0 reuse и проверка полноты сохранены. Повторный PDF теперь читает уже необходимый cache.

По [официальной спецификации](https://api.hh.ru/openapi/specification/public), просмотренной 4 сентября: `per_page ≤100`, depth 2 000, `page`, `date_from`/`date_to`, `clusters`, `describe_arguments`, `responses_count_enabled` поддерживаются; `schedule` deprecated. `HH-User-Agent` содержит приложение и контакт; anonymous search может требовать CAPTCHA. Обработка ошибок сверена с [HH errors](https://github.com/hhru/api/blob/master/docs/errors.md). Token не выводился и не менялся. RPS-limit не выдумывался: существующие 250 ms — локальная консервативная настройка, а не обещанная HH безопасная скорость.

Retries по runtime-контракту проекта отключены, кроме единственного completeness retry коллектора. 429/CAPTCHA завершают соответствующий поток; `Retry-After` сохраняется в typed error и тексте статуса, автоматического повторного запроса раньше этого срока внутри потока нет. Глобальная cooldown/breaker-политика и defaults URLSession не менялись. Очередь теперь promptly cancellable; producer loops последовательные. Нет тестов предела production API, обхода CAPTCHA, новых токенов или авторизационных потоков.

Row-level statistics берёт локальные name/date/employer/region/archive/salary-presence; missing date не становится нулём. Устойчивый report snapshot фиксируется перед save dialog, порядок — новая дата первой, invalid/missing последними. Отдельной salary-distribution, исторических снимков или incremental statistics engine нет; такие возможности не добавлялись. Полный collection публикуется согласованно после завершения, не progressive rows; изменение этого контракта требует отдельной работы. Network bytes/production latency/429 rate не измерялись; запросы/1000 и duplicates текущего collection подтверждаются прежними deterministic tests, не новым live сбором.

## H. PDF, soak и совместная работа

Pipeline: local snapshot → bounded sequential enrichment только где требуется → PDF worker actor → sanitize/layout → batches → validation → atomic/transaction publication. Statistics: compact report snapshot → тот же стиль/layout/renderer → validation → atomic single-file write. PDF production module, шрифты и внешний вид в этом этапе не менялись.

Large Favorite: 500 вакансий / 500 страниц / 5 файлов, 1 296 520 B, final median 5,252 s и 59 277 312 B peak RSS, успешная publication. Размер и число страниц совпали с baseline. Stress: 1 200 абзацев одной вакансии, 32 страницы; статистика: 2 000 элементов, 31 страница, присутствие последнего входного ID проверено после повторного открытия.

Soak statistics: 6 замен одного PDF на 500 вакансий, 9 страниц, 73 813 B каждый раз. Baseline RSS KiB: 43 376 / 44 656 / 50 416 / 60 128 / 67 456 / 70 912. Final: 38 528 / 45 344 / 49 424 / 49 376 / 53 408 / 55 536. Дескрипторы: 5 на каждом цикле, failures=0. Рост RSS остаётся наблюдаемым; этот короткий soak не доказывает отсутствие leak или стабилизацию. PDFKit extraction и allocator включены в процесс; без allocation graph attribution не делается. Для полного Favorite повторные independent-process публикации также прошли; длинный in-process Favorite-publication soak не выполнялся в этом этапе.

Heartbeat во время large PDF и 20 mock calls: final gaps 15,1…27,5 ms, hundreds of ticks. В statistics soak диагностическое чтение текста на main actor давало до 303 ms, поэтому этот максимум нельзя приписывать renderer/UI production. Дополнительный integration test одновременно готовит 100-страничный PDF, меняет фильтры 20 раз и загружает две карточки через mock; после PDF обновляет выдачу. Полный UI suite отдельно проверяет интерфейс на fixtures. Настоящая live HH + ручная UI-сессия не использовалась.

Файловые error/rollback/cancel tests сохранены, hard disk-full не симулировался. Recovery directories реального bulk exporter не удаляются автоматически: действует прежний safety contract. Временный benchmark удаляет только собственные synthetic job directories. Рабочий предел 100 страниц относится к batch обычных вакансий: одна очень длинная вакансия может составлять отдельную часть больше 100 страниц; это существующее поведение, а не строгий общий memory cap. Статистический single PDF также материализуется целиком. Старый budget 64 MiB для prepare не переносится автоматически на новый workload с publication/validation.

## I. Очистка

Проверены references, manifests/lock files, .bak/.old/.orig/log/pyc/.DS_Store, пустые каталоги и runtime build artifacts. Нового доказанного dead production code, unused dependency или repository garbage не найдено; пользовательские файлы не удалялись. Сохранён только полезный воспроизводимый benchmark source, не binaries/outputs. Временные Xcode builds, compiler caches, downloaded public spec, preview PDF/PNG и собственные четыре аварийные scratch-директории очищаются после проверки. Пользовательские Application Support и recovery directories не затрагиваются.

## J. Намеренно не изменено

Progressive search, новый analytics storage, global scheduler/priority, retry/circuit breaker, migration deprecated schedule, renderer streaming и PDF job redesign не выполнялись. У каждой такой задачи есть дополнительные контракты и риски; измерения данного этапа не обосновывают изменения. Session details cache остаётся прежним, без нового TTL/cap; его aging и рост в очень длинной сессии требуют отдельного workload. Bulk Favorite snapshot фиксирует membership, но sourcing live деталей между await допускает обновление коллекции; строгий единый момент снимка для такого случая не доказан. Statistics snapshot покрыт отдельными проверками фильтров/избранного. Не объявляем все перечисленные в задании направления «решёнными».

## K. Проверки текущего этапа

- `/usr/bin/python3 -m unittest discover -s scripts/tests -v`: 71 tests, OK, 19,744 s. Финальный повтор с `-q`: 71 tests, OK, 19,438 s. Release tooling не менялся.
- `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-opt2-baseline test -only-testing:HHVacancySberTests`: baseline и полный suite после каждой из трёх порций — exit 0. Промежуточная ошибка вывода generic continuation исправлена явным типом для Swift 5.9, повторный compile и tests успешны.
- Та же команда с `analyze` на исходном Debug: exit 0.
- `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-opt2-release build analyze`: exit 0, без новых compiler warnings. Executable 2 229 776 B, +78 064 B (+3,63%); чистый bundle 2 300 KiB. Это измеренный trade-off concurrency/error-handling, не уменьшение артефакта.
- Первый финальный Debug `test` без target exclusions выполнил 79 tests: 10 UI прошли, один новый integration test нашёл несогласованность fixture (`filter-moscow` details выдавал employerID `filter`, search выдавал `3529`). Исправлен только mock mapping, assertions не ослаблены. Полный повтор: **exit 0, 79 tests, 0 failures, 1 штатный live skip** (69 unit, включая 11 новых, и 10 UI); elapsed testing 120,826 s. Совместный PDF + filters + mock HH integration test прошёл.
- `bash -n scripts/benchmarks/build.sh`, `git diff --check`: успешно. Отдельного lint/formatter нет; type checking входит в сборки. DMG release script не запускался: он требует clean commit, а пользовательские изменения не коммитились.
- `bash scripts/benchmarks/build.sh <scratch>/binary`: exit 0; `gate`, `enrichment-cancel`, `enrichment-limit`, `enrichment-repeat`, `pdf 10/100/500`, `stress 1`, `statistics 2000`, `soak 500` выполнены. Все три страницы контрольного statistics PDF отрендерены через `pdftoppm` и осмотрены: кириллица, края строк и последний элемент читаемы.

## L. Остаточные ограничения

Нет production network telemetry, Instruments allocations/leak attribution, фактического disk-full или измеренного startup latency. Короткий soak показывает рост RSS, а не доказанное освобождение до исходного уровня. Сохранены известные границы: непрогрессивная публикация поисковых rows, session cache без TTL/cap, default timeouts, отсутствие глобального cooldown, recovery directories bulk PDF, single-document materialization statistics и очень длинных вакансий. UI delay benchmark — main-actor proxy с накладными расходами harness, не Instruments frame-time. Эти ограничения не скрыты и не компенсируются speculative optimization.

## 1. Итог

- Исправлена отмена загрузки описания, когда карточка скрывается фильтром или переключением режима.
- Дефект подтвержден красным тестом; добавлены 3 модульных теста и 1 UI-тест, проверки не ослаблялись.
- Полный Debug: 105 тестов (93 модульных + 12 UI), 3 прежних пропуска, 0 падений.
- Unit test/build/analyze, Release build/analyze и 72 Python-теста прошли; diff и bash-проверки чистые.
- Живых запросов к hh.ru — 0; токен не обнаружен в проверенных диагностических артефактах и отчете.
- Исходные пользовательские изменения сохранены; коммиты и выпуск не выполнялись; 5 UI-снимков извлечены и осмотрены.
- Приемка с оговорками: backoff, изменения PDF и полная UI-матрица отложены; CI текущего дерева не выполнен.

## 2. Инвентаризация и baseline

Рабочий каталог: `/Users/mygga/Documents/ChatGPT/СберВакансии 2`. Проверялась исходная рабочая копия вместе с пользовательскими изменениями, а не чистый HEAD. Среда: macOS 13.7.8 (22H730), arm64, Xcode 15.2 (15C500b), Swift 5.9.2. Заявленные требования README не изменены; другие версии не проверялись. Одна общая схема `HHVacancySber`, цели приложения, модульных и UI-тестов, конфигурации Debug/Release, Swift language mode 5.0. Runtime-зависимостей вне SDK нет. AGENTS.md, спецификация стека, lock-файлы, линтер и форматтер не создавались.

Прочитаны README, project.pbxproj, общая схема, `.github/workflows/ci.yml`, `docs/HEADHUNTER_API_TESTING.md`, `~/Downloads/MAINTENANCE_REFACTOR_REPORT.md`, корневые MAINTENANCE_REFACTOR_REPORT.md и OPTIMIZATION_REPORT.md. Начато с «Отложено» последнего REFACTOR_REPORT_2026-09-04.md и OPTIMIZATION_REPORT_2026-09-05.md. Исторические числа и старые ограничения сверялись с текущим кодом: cancellation-aware очередь и локальный export snapshot уже реализованы; нынешний baseline больше исторических 77 unit + 10 UI / 71 Python.

| Модуль | Реализация и границы |
|---|---|
| HHModels.swift | Decodable summary/details/справочники, value-модель VacancySearchResult, optional salary/date, локальная классификация технологических вакансий. HHPublicationDateParser: обычный ISO8601, затем fractional seconds; nil/невалидная дата → nil. ViewModel держит собственный MainActor parser, PDF создает отдельный. HTTP и JSON-сериализация используют свои форматтеры. |
| HHAPIClient.swift | Единственный прикладной HTTP transport — `session.data(for:)` внутри `data(for:)` и общего `HHRequestGate`. GET, typed errors, общий request builder, JSONDecoder. Default URLSession timeouts, автоматических HTTP-повторов нет. |
| VacancyCollectionService.swift | Последовательно работодатели → регионы → интервалы дат → experience/work_format/schedule; пагинация до доступных 2000 результатов, per_page=100. Первая probe-страница повторно используется в leaf. Дедупликация ID и проверка полноты. Только один дополнительный сбор работодателя при VacancyCompletenessError. Прогресс передается на MainActor; строки публикуются после завершения всего сбора. |
| VacancySearchViewModel.swift | @MainActor ObservableObject. Await: regions/collector, lazy details, archive details, PDF enrichment/worker, persistence driver. Поиск проверяет отмену перед публикацией; detail response защищен resultsRevision; экспорт фиксирует локальные строки/фильтры до await/диалога. После отмены archive loop общий persistFavorites сохраняет ранее полученное. |
| Драйвер persistence | Последний `(revision, values)` объединяет быстрые изменения; один saveTask, один последовательный detached save. Предупреждение относится к актуальной ревизии. Отмена вызывающей archive Task не отменяет принадлежащую ViewModel запись. |
| FavoriteVacancyStore.swift | JSON v2; миграция v1, неподдерживаемая версия не перезаписывается. JSONEncoder ISO8601, sortedKeys; `Data.write(options: .atomic)`. InMemory store защищен NSLock. |
| AreaDirectoryStore.swift | Валидирует root 113, уникальность ID, дерево и классификацию территории; дисковый кеш 7 дней, atomic write; явный stale snapshot после ошибки. CancellationError не превращается в stale success. Ошибка записи свежего дерева возвращает warning, сохраняя данные. |
| EmployerConfiguration / ApplicationSupportLocation | Проверка схемы/пустых и повторных ID, начальная атомарная запись bundled-конфигурации, единый каталог Application Support. |
| Кеши сессии | Полная выдача — 10 минут при search(), refresh явно обходит кеш. Успешные detail-данные — dictionary по ID без TTL/cap; используются карточкой и PDF enrichment, ошибки не кешируются. Нет объединения одновременно ожидающих запросов одного ID между разными операциями. Archive проверяет свежий remote status самостоятельно. |
| ContentView / VacancySearchViews | SwiftUI с LazyVStack, AND-фильтры; initial/loading/error/empty/data и detail loading/error/body. Действия делегированы ViewModel, локальные copied/exported — состояния кнопок. WKWebView: очищенный HTML, JavaScript выключен, navigation только about; внешние элементы удаляются sanitizer. |
| Жизненный цикл | .task запускает persistence/archive; существующий Timer 30 минут и возврат scenePhase.active запускают archive check с защитой от одновременного цикла. detailTask отменяется при ручном закрытии/смене карточки и теперь при скрытии фильтром/режимом. deinit отменяет detailTask/saveTask. Refresh/export и timer-created Task не имеют общего handle для отмены при уходе с окна. |
| FavoriteVacanciesPDFExporter.swift | MainActor — диалоги и прогресс, PDFExportWorker actor — форматирование/пагинация/рендер/запись. PreparedPart Data, staged/backup/публикация move, identity/digest, rollback и сохранение recovery. Подробности в разделе 6. |
| XCTest / XCUITest / Python | Один unit-файл, два UI-класса в общей схеме; URLProtocolStub/FixedTokenProvider, actor mocks, TestAsyncSignal, SlowRecordingFavoriteStore, PDF callbacks/FS-интерфейс для инъекции отказов. UI — DEBUG composition HHVACANCYSBER_UI_TEST_MODE. Python scripts/tests проверяют release tooling на фикстурах; настоящий выпуск не запускается. |

Карта сетевых путей (все используют один builder и gate):

| GET endpoint | Вызывающие пути | Параметры/кеш |
|---|---|---|
| `/vacancies` | ViewModel search/refresh → collector → searchVacancies; два opt-in live-теста | employer_id, area, page, per_page; date_from/date_to, experience, work_format, schedule по разбиению. Полная выдача кешируется ViewModel, page 0 переиспользуется коллектором. |
| `/vacancies/{id}` | loadVacancyDetails; preparedForPDF для personal/favorites; checkArchiveStatusesIfNeeded; исходный live-тест | Без query. Сессионный detailsCache для карточки/enrichment, сохраненный full snapshot избранного может исключить enrichment. Архивный цикл идет последовательно. |
| `/areas` | AreaDirectoryStore.load → areaTree при отсутствии свежего валидного кеша | Без query; выбирается root России; TTL 7 дней. |
| `/dictionaries` | Collector при глубоком разбиении по справочникам | Без query; отдельного кеша словарей нет. |

Общие заголовки: `Accept: application/json`, `User-Agent` и `HH-User-Agent` с `HHVacancySber/1.0` и контактным email, `Authorization: Bearer <значение провайдера>`. Токен отсутствует в URL/query. `NSWorkspace.open` — явное открытие ссылки пользователем во внешнем браузере, не второй transport API. UI/модульные тесты этого прогона не открывали hh.ru.

Ниже приведены фактически выполненные команды. `R` — корень выше; `X` — `R/HHVacancySber`. Время wall измерено внешним runner; внутреннее время XCTest/Python указано отдельно. Пропуски входят в testsCount xcresult. Результаты повторных инструментальных запусков отделены от первой ошибки песочницы.

| Каталог | Команда / запуск | Exit | Wall, с | Тесты / пропуски | Warnings / результат |
|---|---|---:|---:|---|---|
| R | `pwd` (inventory-pwd) | 0 | 0.003 | — | Нет |
| R | `git status --short` (inventory-status) | 0 | 0.009 | — | Нет |
| R | `git diff --stat` (inventory-stat) | 0 | 0.016 | — | Нет |
| R | `git log -1 --oneline` (inventory-log) | 0 | 0.007 | — | FSEvents diagnostic |
| R | `git remote -v` (inventory-remote) | 0 | 0.006 | — | Нет |
| R | `git fetch --dry-run` (inventory-git-fetch) | 0 | 1.123 | — | Нет |
| R | `git ls-remote origin refs/heads/main` (inventory-remote-head) | 0 | 1.101 | — | Нет |
| R | `xcodebuild -version` (inventory-xcode-version) | 0 | 0.129 | — | FSEvents diagnostic |
| R | `swift --version` (inventory-swift-version) | 0 | 0.603 | — | Нет |
| R | `gh --version` (inventory-gh-version) | 0 | 0.025 | — | Нет |
| R | `gh repo view sergeyssimonov-max/HHVacancySber --json name,isPrivate,defaultBranchRef` (inventory-gh) | 1 | 0.047 | — | DNS/network; повтор с системным доступом указан отдельно |
| R | `gh repo view sergeyssimonov-max/HHVacancySber --json name,isPrivate,defaultBranchRef` (inventory-gh-system) | 0 | 0.669 | — | Нет |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -list` (inventory-xcode-list) | 0 | 0.865 | — | DVT plist, CoreSimulator/XPC/cache permission diagnostics; одна схема / 3 цели |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests build analyze` (baseline-unit) | 65 | 5.822 | Не стартовали / — | testmanagerd sandbox restriction; compiler tests не стартовали, xcresult count недоступен |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests build analyze` (baseline-unit-system) | 0 | 104.820 | 90 / 3 | Нет |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test` (baseline-full) | 0 | 149.179 | 101 / 3 | Нет |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor-release build analyze` (baseline-release) | 0 | 14.183 | — | Нет |
| R | `/usr/bin/python3 -m unittest discover -s scripts/tests -q` (baseline-python) | 0 | 19.342 | 72 / 0 | Нет |
| R | `git diff --check` (baseline-diff) | 0 | 0.015 | — | Нет |
| R | `bash -n scripts/benchmarks/build.sh` (baseline-bash) | 0 | 0.002 | — | Нет |

Первая пакетная инвентаризация также включала буквально `pwd`, `git status --short`, `git diff --stat`, `git log -1 --oneline`, `git remote -v`, `git fetch --dry-run`, `xcodebuild -version`, `swift --version`, `gh --version`. Ее отдельные времена не измерены; таблица содержит последующий замер этих read-only проверок. Первый fetch завершился 128 (DNS); первоначальный xcodebuild -list — 0, 0,802 с, со служебными диагностическими сообщениями. В sandbox XCTest остановился до тестов: testmanagerd запрещен; это baseline-проблема среды, а не красный тест production-дефекта. Повтор с системным доступом прошел без разрушительных действий. Диагностика FSEvents не считалась ошибкой.

## 3. Бережность к hh.ru

| Правило | Было | Стало | Доказательство / тест |
|---|---|---|---|
| Единственный transport и User-Agent | Общий makeRequest/data, оба agent-заголовка с именем/контактом | Без изменений | testTypedAPIRequestUsesRequiredQueryAndHeaders, статический просмотр всех четырех путей |
| Частота и параллелизм | Общий actor, максимум 1 запрос; минимум 250 мс после окончания предыдущего | Без изменений | testRequestGateSerializesConcurrentOperations; cancellation race/pacing/queued waiter tests. 250 мс — настройка кода, не заявление об официальном лимите HH |
| 400/404 не повторять | Возврат ошибки без retry | Без изменений; добавлен счетчик запросов в тесте | testAPIDoesNotRetryHTTPOrTransportFailures: ровно 1 transport call для 400/404 |
| 429, Retry-After | Integer seconds сохраняются в typed error/тексте; ожидания нет, HTTP-date не разбирается | Без изменений; несоответствие требованию backoff зафиксировано | Существующий testAPIPreserves401RateLimitCaptchaAndNetworkErrors и новый счетчик для 429/17 |
| 403/CAPTCHA | Terminal error для текущих archive/enrichment циклов, без автоматического повтора | Без изменений | Existing CAPTCHA test; новый обычный 403 без CAPTCHA; archive/enrichment terminal tests |
| Backoff, потолок, глобальная блокировка | Backoff/cooldown/circuit breaker отсутствуют; HTTP retries=0 | Не добавлены: docs прямо запрещает automatic retries, задание запрещает менять scheduler/контракты без решения владельца | Новый тест фиксирует один вызов на 403/429/503/timeout/обрыв. Проверка backoff [НЕ ВЫПОЛНЕНО]: механизма нет |
| Остановка фонового цикла | После первого terminal отказа break; предыдущие обновления сохраняются | Без изменений | testArchiveCheckStopsAfterTerminalAPIError, cancellation/save consistency tests; запрет следующих циклов отсутствует |
| Ограниченные повторы коллектора | Только completeness retry, максимум еще один сбор работодателя | Без изменений | testCollectorRetriesThenRejectsIncompleteLeaf; HTTP failures не перехватываются как completeness |
| Кеш и отсутствие лишнего N+1 | Search TTL, detail cache, persisted full details, reuse page 0 | Без изменений политики | RepeatedFavoritePDFEnrichment / WithPersistedDetails / CollectorSearchRequestCount tests |
| Отмена ненужной загрузки | Фильтр скрывал карточку, оставляя detail Task | Task отменяется при скрытии | Новый красный → зеленый testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload |
| Live бюджет | Два независимых opt-in теста, суммарно до 3 GET при явном включении | Не включались, 0 запросов | Два live skip в каждом полном unit-прогоне; runner удаляет RUN_LIVE env из окружения дочернего процесса |
| Токен в диагностике | Production logger/print для HTTP отсутствует, UI фикстуры без токена | Без изменений схемы | Проверка точного значения в diff, логах, JSON-выгрузках и отчете без вывода значения; детали ниже |

Журнал живых запросов:

| Время | Конечная точка без параметров | Код ответа |
|---|---|---|
| — | Запросов к hh.ru не было | — |

Существующий первый live-тест отключает gate delay (`0`), утверждает found > 0, не проверяет публикационные даты и не ведет журнал времени/status. Второй делает один ограниченный поиск с отдельными таймаутами и проверяет технологическую метку. Это расхождения с желаемой live-методикой, а не результаты живого прогона. Пользовательские live-сценарии и документация не переписаны; до их включения следует отдельно согласовать паузу, shape/date assertions и журнал без секретов. CI не устанавливает ни один live-флаг. Проверки против реального HH [НЕ ВЫПОЛНЕНО] по установленному запрету включать их самостоятельно.

Участие токена: HHAuthConfig.appAccessToken → configuredAccessToken/normalizedAccessToken → HHDefaultAccessTokenProvider.accessToken → HHAPIClient.validateVacanciesAccess и makeRequest → единственный Authorization header. Runtime composition использует этот provider; тест конфигурации проверяет только наличие, unit HTTP factory передает синтетическое значение. Первый live-тест явно выбирает default provider, второй использует его по умолчанию. Значение не выводилось, не передавалось в аргументы shell, не копировалось в тесты или отчет. Временный runner читает его только в память для проверки/редактирования потенциального совпадения; во всех сохраненных command logs число совпадений равно 0. Ожидаемое присутствие встроенного значения в исходном HHAuthConfig и бинарнике приложения не считается утечкой и не изменялось.

Итоговая проверка точного совпадения встроенного значения в текстовых артефактах, Git diff и build diagnostic logs: 0 совпадений; список проверенных областей и счетчики сохранены в `/private/tmp/HHVacancySber-refactor-audit-20260905/secret-check.json`. Все пять финальных UI PNG осмотрены. Бинарники приложения из этой проверки исключены по действующему контракту встроенной авторизации.

## 4. Изменения

| Файл | Проблема и доказательство | Красный тест | Минимальная правка | Проверка и риск |
|---|---|---|---|---|
| HHVacancySber/HHVacancySber/VacancySearchViewModel.swift | reconcileExpanded сбрасывал expandedVacancyID, сохраняя активную detailTask. При скрытии employer/region/favorites мок принимал поздний ответ | testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload: 7 failure summaries; не пришла отмена во всех 3 случаях, карточка стала detailLoaded, в одном случае число запросов при повторном открытии 1 вместо 2 | В существующей ветке добавлен detailTask?.cancel(); метод развернут на несколько строк. Собственный diff +6/−1 | Те же assertions зеленые; полный unit build/analyze и UI. Низкий риск: уже существующий путь отмены loadVacancyDetails сбрасывает loading и не кеширует ответ; видимая карточка продолжает загрузку |
| HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift | Не было проверки реальной отмены при фильтрации, контроля видимой карточки и числа transport calls на ошибки | Один новый test красный, два теста контрольного покрытия зеленые до production-правки | 3 теста; optional beforeFirstDetailResponse callback в существующем MockAPIClient, TestAsyncSignal и штатные XCTest expectations. +119/−1 | Без новой абстракции над клиентом, сети и зависимостей; прежний initializer совместим через default nil; существующие assertions сохранены |
| HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift | Требовалась приемка перехода скрытая → повторно открытая карточка | UI-тест проверяет отображение; красное доказательство отмены — unit-тест, не UI | Один сценарий на прежних DEBUG fixtures, два keepAlways screenshot attachments. +28/−0 | Проверяет скрытие details, сброс подписи кнопки и повторное раскрытие; не заявляет измерение transport cancellation из UI |
| REFACTOR_REPORT_2026-09-05.md | Нужна воспроизводимая фиксация прогона и ограничений | Не применимо к отчету | Новый отчет | Только документация |

Классификация остальных результатов:

- **Безопасно исправляемые после красного теста:** только описанная отмена скрытой карточки. Массовых правок и косметической очистки нет.
- **Требующие решения о контракте/архитектуре:** backoff/cooldown, переходы после terminal отказа, live-методика, streaming PDF, числовые суффиксы коллизий и отказ от хеша, видимость export/recovery сообщений. Доказательства и следующий шаг — раздел 9.
- **Известные состояния:** буферы PDF, TTL/cap details, непрогрессивная выдача, отдельные несохраненные вложения Xcode; не объявлены новыми регрессиями.
- **Ложные срабатывания:** размер PDF exporter; различные UI/PDF tie-breakers; разные HTTP/persistence/date formatters; fatalError в benchmark-фикстурах; буквальный URL unwrap и try! статических регулярных выражений без внешнего входа. В production нет найденного force cast; оснований менять постоянные выражения нет.
- **Baseline-проблемы:** sandbox testmanagerd и DNS, устраненные разрешенным системным запуском. Ошибок исходного полного suite не было.

## 5. Тесты

| Новый тест | Цель / файл | До правки | Финальный test duration, с |
|---|---|---|---:|
| `testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload` | Отмена при employer/region/favorites, сброс loading, отсутствие cache от отмененного ответа и успешный reload; `HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift` | Красный: 6,538 с, 7 failure summaries; зеленый целевой: 0,442 с | 0.538 |
| `testFilterChangeKeepingExpandedVacancyVisiblePreservesInFlightDetails` | Видимая карточка сохраняет запрос и получает ответ; `HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift` | Контроль: зеленый еще до правки, 0,115 с | 0.110 |
| `testAPIDoesNotRetryHTTPOrTransportFailures` | Ровно 1 вызов на 5 HTTP-кодов и 2 transport errors; `HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift` | Покрытие существующего контракта: зеленый до правки, 0,006 с | 0.005 |
| `testFilteringExpandedVacancyHidesDetailsAndAllowsReopening` | UI скрывает детали, возвращает кнопку Подробнее и повторно открывает описание; два снимка; `HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift` | Не красное доказательство transport cancellation; новая UI-приемка | 25.791 |

| Набор | До | После | Изменение |
|---|---:|---:|---:|
| XCTest target, включая opt-in | 90 | 93 | +3 |
| XCUITest | 11 | 12 | +1 |
| Полный Debug total | 101 | 105 | +4 |
| Исполнены успешно, без skipped | 98 | 102 | +4 |
| Live внутри XCTest target | 2, оба skipped | 2, оба skipped | 0 |
| Opt-in PDF metrics внутри XCTest target | 1 skipped | 1 skipped | 0 |
| Пропусков всего | 3 | 3 | 0 |
| Python | 72 | 72 | 0 |

Существующие существенные проверки повторно выполнены: cancelled gate waiter и гонки отмены; одновременные archive checks; архивный 404 и recoverable timeout; сохранение после реальной Task.cancel; индекс избранного после удаления между await; неподдерживаемая JSON-схема; объединение записей; прежняя выдача при ошибке refresh; resultsRevision; локальный snapshot избранного и знаменатель прогресса; enrichment cache/terminal error/cancellation/fallback; PDF pagination, Unicode, metadata, порядок/единственность строк, отмена последней страницы, атомарная personal/statistics запись, staged validation failure, rollback/collision recovery.

Новый API matrix использует синтетические URLProtocol responses и ровно один вызов на каждый из 400, 404, 403, 429, 503, timeout и обрыв. Он дополняет прежнюю проверку типов ошибок счетчиком повторов; backoff не имитируется и не объявлен реализованным. Новых Python-тестов нет: scripts не менялись. Тесты с опросом состояния выполняют только ограниченное локальное ожидание мока, не HTTP polling. Случайные нагрузочные данные и новые зависимости не добавлялись.

Отклонены дубли тестов локального snapshot/parser/archive persistence, переписывание ожиданий имени статистического PDF под иной контракт, perf assertions по wall-time, новые live-вызовы ради красного теста, тесты приватных деталей transaction. Полная отдельная UI-матрица slow loading / stale-area warning / persistence failure / detail error-cancel / native dialogs остается непокрытой: прежняя fixture composition содержит default/empty/searchError; новый тест не выдает ее за полную матрицу.

## 6. PDF

Перечень действий экспортера по текущему коду:

1. ViewModel фиксирует исходную вакансию, массив избранного или статистический snapshot строк/режима/фильтров. Для personal/favorites последовательно подготавливает details с cache/local fallback; statistics не вызывает HH.
2. Worker actor очищает HTML, строит attributed text с прежними ru_RU/шрифтами/A4, сортирует статистику через HHPublicationDateParser. UI равные даты сортирует по названию/ID, статистика — по ID; это сохранено.
3. Пагинация использует NSTextStorage/NSLayoutManager и autoreleasepool, резервирует нижний отступ и переносит целый абзац, когда возможно. Очень длинная вакансия остается единым документом даже сверх обычных 100 страниц.
4. Favorites рендерятся частями обычно до 100 страниц; CGDataConsumer пишет в NSMutableData и рисует страницы по одной. Все полученные сжатые PreparedPart.data удерживаются до публикации. Personal/statistics также полностью материализуют pages и Data. **Постраничного файлового streaming без удержания документа нет.**
5. Worker проверяет количество страниц и видимое содержимое через Core Graphics; XCTest дополнительно открывает PDFKit и извлекает текст/метаданные.
6. MainActor показывает выбор каталога и подтверждение существующих имен. Отказ discards подготовленные buffers.
7. Favorites создают `.HHVacancySber-PDF-<transactionID>`, lease, cleanup-forbidden marker, staged и backup. Каждая часть atomically записывается в staged и валидируется до переноса оригиналов.
8. Capture authorizations проверяет состояние назначения; backupOriginals переносит оригинал и проверяет identity/digest. Publish move переносит готовый staged файл под итоговое имя, не перезаписывает неожиданно появившийся файл.
9. После commit служебный каталог сохраняется и возвращается как cleanup warning. При отказе/cancellation rollback помещает опубликованное в quarantine/staged, проверяет identity/digest, сохраняет конкурентно измененные файлы, восстанавливает доступные оригиналы; неоднозначность возвращается как PDFTransactionRecoveryError с путями.
10. Personal/statistics проверяют cancellation и валидность перед Data.write(.atomic). Отдельной multi-file transaction им не требуется; прямой записи частичного Data под финальным именем нет.

Прогресс favorites поступает на MainActor после каждой вакансии. Отмена проверяется между enrichment/vacancy/page/part/write стадиями; реальная Task.cancel и отмена диалога проверены. Рендер и запись происходят вне MainActor. При этом `pages(for:)` не имеет проверки отмены внутри каждой итерации layout, а UI не предоставляет отдельную кнопку отмены уже идущего worker; personal/statistics показывают не все стадии прогресса. Интерактивность большого PDF проверяется существующим mock integration test, но frame-time/Instruments в этом прогоне [НЕ ВЫПОЛНЕНО].

Восстановление: при остановке экспорта не удалять служебный каталог; сначала сохранить копии final/staged/backup и сведения об ошибке, проверить PDF через просмотрщик/PDFKit, сопоставить оригинальные имена в backup с назначениями. Сохранившийся оригинал можно скопировать под новым свободным именем, не затирая измененный параллельно final; автоматическое восстановление уже покрыто failure/collision tests. Нельзя рекурсивно удалять каталог по одному UUID/path: lease учитывает перемещение/подмену. Новый экран/автоочистка не добавлялись. **Фактическое ограничение UI:** export status/recovery path записываются в statusMessage, но текущая статусная строка рисует только счетчик; текстовый путь не гарантированно доступен пользователю в окне. Это вынесено на решение владельца, а не скрыто утверждением о законченной пользовательской процедуре восстановления.

Правило имени централизовано в PDFFileNameBuilder: NFC, нижний регистр, буквы/цифры, остальные символы в `_`, снятие повторных `.pdf`, fallback и обрезка по границам Character в пределах 240 UTF-8 байт. Personal: `yyyy_MM_dd_HH_mm_<название>.pdf`, vacancyID не добавляется. Favorites: `<дата>_избранные_вакансии`, при нескольких частях `_том_001_из_002`. Statistics: `<дата>_статистика_<режим>_<работодатель>_<регион>_<8 hex>.pdf`; каждому label отведено 48 UTF-8 байт, хеш различает одинаковые подписи с разными ID/режимами. Timestamp использует текущий часовой пояс.

Имена читаемы и очищены от `/`, `:`, управляющих и других небуквенных символов. Но числового суффикса для коллизий нет: действует подтвержденная замена/сохранение предыдущего файла; статистика содержит служебный хеш. Тесты StatisticsFilenameRetainsBothFiltersAndIsSafeForLongLabels, StatisticsFilenameDisambiguatesSameNamesWithDifferentIDsAndModes и RepeatedStatisticsExportsReplacePriorFilterContentsInSameFile прямо закрепляют нынешнее поведение. Изменить его без ослабления текущих проверок и согласования контракта нельзя. Полное покрытие всех ветвей sanitize/fallback/Unicode-budget отдельными XCTest [НЕ ВЫПОЛНЕНО]; это не выдается за выполненное требование числовых коллизий.

PDFKit в testFavoritePDFExportProducesBoundedValidPartsAndMainActorProgress проверяет 101 вакансию → 100+1 страниц, каждое имя ровно один раз в исходном порядке, creationDate и producer. Statistics tests проверяют 24 сочетания общего списка и 12 избранного, фильтры, порядок, пустые и многостраничные отчеты, missing/fractional dates и перезапись содержимого. Fixed snapshots дают семантическую повторяемость; CGContext вызывается с nil metadata, время/ID Quartz не фиксируются. Побайтовая детерминированность с закрепленными метаданными [НЕ ВЫПОЛНЕНО], metadata seam не добавлялся. Формат/локаль/PDF transaction не менялись.

## 7. Экраны

| Состояние / действие | Текущая реализация | Проверка |
|---|---|---|
| Первое открытие | Заголовок/инструкция, кнопка обновления, счетчик 0 | testLaunch, testInitialRefreshButtonMatchesToolbarButton |
| Loading без данных | ProgressView и текст загрузки; refresh disabled | ViewModel isLoading; отдельный детерминированный UI slow-loading [НЕ ВЫПОЛНЕНО] |
| Данные и фильтры | LazyVStack, AND-фильтры работодателя/субъекта, счетчик только «Показано вакансий: N» | SearchShowsConfiguredVacanciesAndLazyDetails, EmployerDropdown, RegionDropdown; unit filter transitions |
| Пустой API / пустое пересечение | «Вакансий не найдено» и refresh | EmptyResponseIsExplicit, RegionDropdownCombinesWithEmployerAndCanShowNoMatches, StatisticsCommandRemainsAvailableForEmptyCombinedFilter |
| Начальная ошибка | «Не удалось загрузить вакансии», описание и повтор | SearchFailureIsExplicit; fixture 503. Отдельный UI transport-offline [НЕ ВЫПОЛНЕНО], unit transport-errors выполнены |
| Ошибка refresh с прежними данными | Прежние rows, warning над списком | FailedRefreshDoesNotDiscardDetailLoadedWhileRefreshWasRunning и statistics stale-data tests; отдельный UI [НЕ ВЫПОЛНЕНО] |
| Details | Loading, error, HTML или сообщение отсутствия полного описания | LazyDetails unit/UI; новый cancel/reload unit и hide/reopen UI. Отдельные UI detail error/cancel [НЕ ВЫПОЛНЕНО] |
| Избранное / persistence | Toggle, собственная выдача, reset невалидных фильтров, warning записи | Unit normalization/persistence/migration; FavoritePDFCommands UI |
| PDF | Кнопки и favorites progress, native dialogs; workers вне MainActor | Существующие 3 UI PDF-command tests и worker/PDFKit tests; полноценные UI диалоги/ошибки [НЕ ВЫПОЛНЕНО] |

Макет и реализация views не менялись, новые бизнес-вычисления во view не добавлялись. Переходы фильтров исправлены в ViewModel. Отдельные statusMessage/statisticsPDFExportMessage не представлены общим visible error channel; возвращать их вместо счетчика запрещает принятый ранее контракт, нужен отдельный согласованный элемент UI.

Финальный полный прогон сохранил **5 PNG attachments**, все 5 успешно экспортированы (`xcresulttool export`, exit 0) и визуально осмотрены. В новом сценарии подтверждены фильтр СберРешения без скрытой карточки и открытое описание после возврата всех работодателей. Значения токена на снимках нет. Legacy launch screenshot содержит также рабочий стол; он не использовался как доказательство остальных UI-состояний.

| Снимок | Файл | Байт |
|---|---|---:|
| Matching PDF commands in favorites | [final-full-screenshot-1.png](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-screenshot-1.png) | 131578 |
| Expanded vacancy hidden by employer filter | [final-full-screenshot-2.png](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-screenshot-2.png) | 127849 |
| Vacancy details reopened after clearing filter | [final-full-screenshot-3.png](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-screenshot-3.png) | 135174 |
| Statistics PDF borderless command | [final-full-screenshot-4.png](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-screenshot-4.png) | 127579 |
| СберВакансии | [final-full-screenshot-5.png](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-screenshot-5.png) | 2828355 |

В baseline xcresult было 3 PNG payloadRef; попытка позднего извлечения baseline attachments [НЕ ВЫПОЛНЕНО], поскольку Xcode уже удалил старый bundle. Их JSON summaries сохранены. Финальные screenshots проверены фактическим извлечением, а не только ссылкой. Два PDF-вложения потерялись в промежуточном final-unit, но предупреждений об attachments в final-full output нет.

## 8. Намеренно не изменено

Архитектура, actor isolation, форматтеры HTTP/хранения, JSON schema, порядок равных дат, API parameters/headers, token provider, session cache policy, progressive search и scheduler, PDF layout/fonts/locale, filenames/replacement contract, transaction/rollback/recovery, assets, benchmark fail-fast, release tooling, требования к версиям, project.pbxproj, scheme, CI и build settings. Нет зависимостей, линтера, форматтера, AGENTS.md, второй схемы, новых слоев над тестовыми клиентами, сетевых путей или таймеров. Размер экспортера и старые пользовательские изменения не использовались как повод для реорганизации.

## 9. Отложено

| Приоритет / вопрос владельцу | Доказательство и граница | Следующее действие |
|---|---|---|
| Надежность сети: разрешены ли backoff/cooldown и новая блокировка? | Docs запрещает HTTP retry, задание требует ожидание Retry-After/backoff, но запрещает менять scheduler. 429 seconds только отображаются; 403/429 останавливают текущий archive/enrichment, новый activation/timer цикл снова возможен. При stale areas даже terminal API error превращается в fallback, затем поиск может продолжить HTTP | Отдельно утвердить контракт остановки всех операций/возобновления, HTTP-date и bounded delays; моки до реализации, без живой нагрузки |
| Live-методика | Первый opt-in тест gate=0, count-based assertion, нет проверки дат/журнала HTTP status; два live флага вместо исторического одного | Перед разрешением live согласовать изменение существующего теста/журнала, сохранить общий бюджет ≤5 и остановку на 403/429 |
| Recovery и export errors в UI | Worker возвращает пути/ошибки, statusMessage не отображается нынешней строкой счетчика | Согласовать отдельное сообщение/диалог; затем красный unit/UI тест видимости, не заменять счетчик |
| Имена PDF | Существующий contract — replacement + SHA suffix у statistics; запрос требует numeric suffix/no IDs | Утвердить совместимую смену naming/collision policy, затем новая спецификация и тесты всех ветвей |
| Память PDF и отмена layout | PreparedPart Data удерживаются до publish; personal/statistics materialize документ; pages(for:) без cancellation внутри layout-loop | Отдельный workload и решение о streaming/изменении pipeline; без разделения экспортера ради размера |
| Детерминированность PDF | CGContext nil metadata, auto Quartz timestamps/document ID | Разрешить injection/фиксирование metadata перед byte comparison |
| Кеш | У details нет TTL/cap/coalescing между concurrent consumers; /dictionaries не кешируется | Утвердить freshness и повторные HH-запросы, ориентироваться на измерения прошлого optimization report, не объявлять их новыми измерениями |
| Нагрузка UI / жизненный цикл | Вычисляемые фильтры/избранное от @Published массивов; refresh/export/timer tasks не имеют общего cancellation handle | Профиль и контракт при закрытии окна; не менять observability/batching без доказательства и решения о промежуточных состояниях |
| Полная матрица UI | Default/empty/searchError fixtures покрывают не все состояния и native dialogs | Отдельные детерминированные fixtures, unit переходы и UI attachments для каждого состояния |
| Внешняя приемка | Dirty tree на 3 локальных коммита впереди remote, CI для этого дерева отсутствует | Владелец делает commit/push и получает обязательный macOS CI; агент этого не выполняет |
| Стендовые ограничения | Нет Instruments/длительного soak, настоящего disk-full, crash/power loss, другой OS/Xcode | Отдельный стенд; новые инструменты не устанавливались, искусственные отказы не приравниваются к аппаратным |

Ни один из этих пунктов не объявляется устраненным. Отложенные изменения требуют иной политики/контракта либо отдельного подтверждения; в данном прогоне они не вносились.

## 10. Проверки

| Каталог | Команда / запуск | Exit | Wall, с | Тесты / пропуски | Warnings / результат |
|---|---|---:|---:|---|---|
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests/HHVacancySberTests/testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload -only-testing:HHVacancySberTests/HHVacancySberTests/testFilterChangeKeepingExpandedVacancyVisiblePreservesInFlightDetails -only-testing:HHVacancySberTests/HHVacancySberTests/testAPIDoesNotRetryHTTPOrTransportFailures` (red-details) | 65 | 17.905 | 3 / 0; 1 failed | Ожидаемый красный test: отмена скрытой карточки |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests/HHVacancySberTests/testHidingExpandedVacancyCancelsInFlightDetailsAndAllowsReload -only-testing:HHVacancySberTests/HHVacancySberTests/testFilterChangeKeepingExpandedVacancyVisiblePreservesInFlightDetails -only-testing:HHVacancySberTests/HHVacancySberTests/testAPIDoesNotRetryHTTPOrTransportFailures` (green-details) | 0 | 4.036 | 3 / 0 | Нет |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests build analyze` (final-unit) | 0 | 13.529 | 93 / 3 | 2 несохраненных PDF attachments, не compiler warnings |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor test` (final-full) | 0 | 176.187 | 105 / 3 | Нет |
| X | `xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath /private/tmp/HHVacancySber-refactor-release build analyze` (final-release) | 0 | 9.587 | — | Нет |
| R | `/usr/bin/python3 -m unittest discover -s scripts/tests -q` (final-python) | 0 | 18.566 | 72 / 0 | Нет |
| R | `git diff --check` (final-diff) | 0 | 0.015 | — | Нет |
| R | `bash -n scripts/benchmarks/build.sh` (final-bash) | 0 | 0.002 | — | Нет |
| R | `git diff --cached --exit-code` (final-staged) | 0 | 0.007 | — | Нет |
| R | `git diff --exit-code -- HHVacancySber/HHVacancySber.xcodeproj/project.pbxproj HHVacancySber/HHVacancySber.xcodeproj/xcshareddata/xcschemes/HHVacancySber.xcscheme .github/workflows/ci.yml HHVacancySber/HHVacancySber/HHAuthConfig.swift` (final-project) | 0 | 0.007 | — | Нет |

Фрагменты фактического xcodebuild output (не реконструкция TEST SUCCEEDED для quiet-режима):

`baseline-unit-system`: exit 0, wall 104.820 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/baseline-unit-system.log).

```text
2026-09-05 08:07:26.805 xcodebuild[26744:2171242] [MT] IDETestOperationsObserverDebug: 11.044 elapsed -- Testing started completed.
Testing started
```

`baseline-full`: exit 0, wall 149.179 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/baseline-full.log).

```text
2026-09-05 08:10:17.293 xcodebuild[26910:2174157] [MT] IDETestOperationsObserverDebug: 147.815 elapsed -- Testing started completed.
Testing started
```

`red-details`: exit 65, wall 17.905 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/red-details.log).

```text
2026-09-05 08:12:29.909 xcodebuild[27130:2181802] [MT] IDETestOperationsObserverDebug: 11.552 elapsed -- Testing started completed.
** TEST FAILED **
Testing started
```

`green-details`: exit 0, wall 4.036 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/green-details.log).

```text
2026-09-05 08:13:35.735 xcodebuild[27194:2190787] [MT] IDETestOperationsObserverDebug: 1.641 elapsed -- Testing started completed.
Testing started
```

`final-unit`: exit 0, wall 13.529 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/final-unit.log).

```text
2026-09-05 08:14:56.109 xcodebuild[27246:2192211] [MT] IDETestOperationsObserverDebug: 11.572 elapsed -- Testing started completed.
Testing started
```

`final-full`: exit 0, wall 176.187 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full.log).

```text
2026-09-05 08:18:33.261 xcodebuild[27302:2193987] [MT] IDETestOperationsObserverDebug: 174.830 elapsed -- Testing started completed.
Testing started
```

`final-release`: exit 0, wall 9.587 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/final-release.log).

```text
(stdout и stderr пусты)
```

`final-python`: exit 0, wall 18.566 с; [полный log](/private/tmp/HHVacancySber-refactor-audit-20260905/final-python.log).

```text
Ran 72 tests in 18.388s
OK
```

Из `xcresulttool get --format json` финального bundle:
```text
schemeCommandName: Test
actionResult.status: succeeded
metrics.testsCount: 105
metrics.testsSkippedCount: 3
testStatus: 102 Success, 3 Skipped; Failure отсутствует
```
Сохраненные метрики с идентификаторами и длительностями всех тестов: [final-full-xcresult.json](/private/tmp/HHVacancySber-refactor-audit-20260905/final-full-xcresult.json). Сам bundle: `/private/tmp/HHVacancySber-refactor/Logs/Test/Test-HHVacancySber-2026.09.05_08-15-37-+0300.xcresult`. Полные команды/exit/wall представлены также в одноименных JSON рядом с logs.

После записи отчета `git diff --check` повторен: exit 0, 0,015 с; [log](/private/tmp/HHVacancySber-refactor-audit-20260905/report-diff.log).

Локальная приемка сборок/тестов подтверждена фактическим output и xcresult, число тестов не уменьшилось и пропуски сохранились. Полная предметная приемка имеет оговорки из разделов 6–9. CI macOS для текущего незакоммиченного дерева [НЕ ВЫПОЛНЕНО]; чужой/исторический зеленый запуск не подменяет этот внешний гейт. `release.sh`, DMG, публикация и живой API не запускались.

## 11. Git

HEAD: `6e76afdfc7086a598c029ed132eacf9b814d8bfe` — `6e76afd Handle macOS FSEvents metadata during DMG creation`. Ветка main. Origin: `https://github.com/sergeyssimonov-max/HHVacancySber.git`, закрытый репозиторий, default branch main (gh). После успешного git fetch --dry-run отдельный git ls-remote показал remote main `389412131f2223dbb009dd3959ac15893be87b2f`, совпадающий с локальным origin/main; `git rev-list --left-right --count HEAD...origin/main` → `3 0`. Refs не обновлялись обычным fetch; remote дерево не выдавалось за текущий пользовательский diff.

До работы — 11 измененных отслеживаемых файлов и 1 неотслеживаемый, поименно:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
 M REFACTOR_REPORT_2026-09-04.md
 M docs/HEADHUNTER_API_TESTING.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? OPTIMIZATION_REPORT_2026-09-05.md
```

```text
 .../FavoriteVacanciesPDFExporter.swift             |  10 +-
 HHVacancySber/HHVacancySber/HHModels.swift         |  58 ++++
 .../HHVacancySber/VacancySearchViewModel.swift     |  22 +-
 .../HHVacancySber/VacancySearchViews.swift         |  29 +-
 .../HHVacancySberTests/HHVacancySberTests.swift    | 155 +++++++++
 .../HHVacancySberUITests.swift                     |  23 +-
 README.md                                          |   3 +-
 REFACTOR_REPORT_2026-09-04.md                      | 375 +++++++--------------
 docs/HEADHUNTER_API_TESTING.md                     |  16 +-
 scripts/benchmarks/README.md                       |   6 +-
 scripts/benchmarks/RuntimeBenchmarks.swift         |  57 +++-
 11 files changed, 469 insertions(+), 285 deletions(-)
```

После работы:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
 M REFACTOR_REPORT_2026-09-04.md
 M docs/HEADHUNTER_API_TESTING.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? OPTIMIZATION_REPORT_2026-09-05.md
?? REFACTOR_REPORT_2026-09-05.md
```

`git diff --stat` (untracked отчеты не входят):

```text
 .../FavoriteVacanciesPDFExporter.swift             |  10 +-
 HHVacancySber/HHVacancySber/HHModels.swift         |  58 ++++
 .../HHVacancySber/VacancySearchViewModel.swift     |  29 +-
 .../HHVacancySber/VacancySearchViews.swift         |  29 +-
 .../HHVacancySberTests/HHVacancySberTests.swift    | 275 ++++++++++++++-
 .../HHVacancySberUITests.swift                     |  51 ++-
 README.md                                          |   3 +-
 REFACTOR_REPORT_2026-09-04.md                      | 375 +++++++--------------
 docs/HEADHUNTER_API_TESTING.md                     |  16 +-
 scripts/benchmarks/README.md                       |   6 +-
 scripts/benchmarks/RuntimeBenchmarks.swift         |  57 +++-
 11 files changed, 622 insertions(+), 287 deletions(-)
```

Сверка SHA-256 всех 57 исходных файлов: изменились только `HHVacancySber/HHVacancySber/VacancySearchViewModel.swift`, `HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift`, `HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift`. Остальные 54 исходных файла совпадают побайтово; в трех измененных файлах собственный diff проверен относительно их исходного пользовательского содержимого. Дополнительно создан только текущий отчет. Исходный OPTIMIZATION_REPORT_2026-09-05.md сохранен без изменений. Staged diff пуст; project/scheme/CI/HHAuthConfig diff пуст.

Собственные изменения отделены от исходной копии файла в трех отдельных diff в `/private/tmp/HHVacancySber-refactor-audit-20260905/initial-*.swift.diff`. Не выполнялись git add/staging, commit, push, stash, reset, restore, clean, checkout или операции отмены/перезаписи истории. Тестовые output/xcresult располагаются только в `/private/tmp/HHVacancySber-refactor*`; они не добавлялись в Git. Xcode автоматически удаляет часть старых xcresult из своего LogStore; метрики/ошибки предыдущих прогонов сохранены в audit JSON до удаления. Скрипты аудита временные, не добавлены в проект; воспроизводимые build artifacts оставлены для проверки владельцем.

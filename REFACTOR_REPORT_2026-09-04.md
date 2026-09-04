## 1. Итог

Исправлены обработка отмены загрузки регионов, запись персонального PDF после отмены и потеря подразделения, даты и зарплаты краткой карточки в PDF.
Добавлено 8 unit-тестов; усилена проверка порядка 101 вакансии в двух PDF-томах.
Финальный полный Debug-прогон: 95 тестов, 94 успешны и один штатный live-пропуск; Release build/analyze и 71 Python-тест прошли.
Первый полный прогон упал на UI-меню; повтор без правок прошёл, причина единичного сбоя не установлена.
Архитектура, UI, формат хранения, типографика PDF, настройки сборки и прежние пользовательские изменения сохранены.
Откат, сохранение чужого файла и восстановление исходного PDF из резервной копии проверены.
Приёмка с оговорками: все UI-состояния и детерминированность PDF с фиксированными метаданными/ID не подтверждены; нужны отдельные тестовые контракты.

## 2. Инвентаризация и baseline

Рабочий корень: `/Users/mygga/Documents/ChatGPT/СберВакансии 2`; каталог Xcode-команд: его подкаталог `HHVacancySber`. Фактическая среда — Codex, не Claude Code CLI; установленный Claude CLI использован только для read-only инвентаризации расширений.

`pwd`, `git status --short`, `git diff --stat`, `git log -1 --oneline`, `git remote -v` выполнены. Ветка `main`, HEAD `c8d268eacffa83c5fa5ac1960b2b69844a46ef6e`, последний коммит `c8d268e Release 1.0 (4): harden vacancy search and filtering`. Origin: `https://github.com/sergeyssimonov-max/HHVacancySber.git`. `git fetch --dry-run`: первая sandbox-попытка — 128 (DNS), разрешённый повтор — 0, без вывода. Сравнение HEAD с локально сохранённой `refs/remotes/origin/main` через `git rev-list --left-right --count`: `1 0`; dry-run не обновляет tracking ref, это не утверждение о скачанном актуальном remote snapshot.

`xcodebuild -version`: Xcode 15.2, Build 15C500b. `swift --version`: Swift 5.9.2, arm64. Фактическая ОС в xcresult: macOS 13.7.8 (22H730), Mac Studio/M1 Max. `xcodebuild -quiet -project HHVacancySber.xcodeproj -list`: код 0, 0,425 с; одна общая схема HHVacancySber, app/unit/UI targets, Debug и Release. Sandbox-диагностика FSEvents/CoreSimulator и доступа к Xcode-кешам не является предупреждением компилятора; после разрешённого повторного запуска перечисление успешно. Диапазон других Xcode/macOS не проверялся.

`claude plugin list` выполнен без изменений: включены commit-commands, context7, frontend-design, rust-analyzer-lsp, svelte, typescript-lsp; выключены code-review, github, security-guidance. Наличие frontend-design в другом CLI не даёт callable `/design` в этой сессии. Расширения, зависимости и инструменты не устанавливались. Субагенты не привлекались.

Прочитаны README, цели/фазы/настройки project.pbxproj, shared scheme, CI, docs/HEADHUNTER_API_TESTING.md, оба предшествующих отчёта, release.sh, verifier, benchmark sources/build/readme и тесты release tooling. Исходные ограничения из «Отложено»/остаточных рисков рассматривались как кандидаты, не как разрешение на перепроектирование. AGENTS.md, CONTRIBUTING, отдельная спецификация стека, lint/formatter configs, пакетные/lock-файлы и вторая схема не найдены. Иконки и build references действующие.

Карта текущего кода:

| Область | Контракт и точки риска |
|---|---|
| HHModels.swift | Value models, HHPublicationDateParser: обычный ISO8601, затем fractional; экземпляры принадлежат потребителям. Денежный formatter защищён NSLock. HTTP/JSON-форматтеры имеют отдельные контракты. |
| HHAPIClient.swift | URLSession, идентификационные заголовки и типизированные ошибки; общий actor gate, один запрос, интервал 250 ms, отменяемая очередь. Нового retry/cooldown нет. |
| VacancyCollectionService.swift | Работодатели/страницы последовательно; reuse page 0; разбиение по регионам, датам, словарным фильтрам при глубине 2000; ID-dedupe; один completeness retry; отмена между запросами. |
| AreaDirectoryStore.swift | JSON-cache справочника на 7 суток; явный stale fallback при сетевом отказе, проверка структуры; атомарная запись. Исправлено различие ошибки и отмены. |
| FavoriteVacancyStore.swift | Схема v2, миграция v1, защита неизвестной схемы; атомарный JSON. Изменений нет. |
| VacancySearchViewModel.swift | MainActor, owned formatters, revision guards после await деталей; immutable локальный снимок экспорта до await; owned coalescing persistence driver, detached запись; archive cancel идёт через общий путь сохранения. |
| Кеши | Кеш деталей сессии без TTL/cap; кеш поискового snapshot имеет отдельное правило 10 минут. Их нельзя смешивать при оценке freshness. |
| VacancySearchViews.swift / ContentView.swift | Поиск, фильтры, все/избранное, карточки, lazy details, empty/error/progress, PDF-команды и статусная строка; HTML sanitization перед WKWebView. Изменений в этом прогоне нет. |
| FavoriteVacanciesPDFExporter.swift | Value snapshot → один worker actor → sanitize/format/layout/render → validated Data → atomic single-file либо staged/backup/publish/rollback. Identity/digest checks, quarantine и recovery paths сохранены. Готовые Data удерживаются до публикации. |
| Тесты/скрипты | XCTest unit и XCUITest, фиксированные моки, TestAsyncSignal, URLProtocol, callbacks для инъекции файловых отказов; Python unittest для release/verifier. Benchmark fatalError на запрещённой сети — намеренный fail-fast. |

Поиск точных `B1–B9` и `F-001–F-003` не выявил действующей функциональности с этими идентификаторами. В release tooling есть диагностический идентификатор `B13-DIST-001-R5-R6-R4`, он не является удалённым скорингом; миграционные фикстуры используют исторические поля намеренно. Скоринг не возвращался, кандидаты не удалялись по одному совпадению строки.

Команды baseline выполнены **до production-правок**. Ниже «время action» взято из startedTime/endedTime xcresult; это не wall всего процесса.

Обозначения точных команд:

```sh
# U — cwd HHVacancySber
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor test -only-testing:HHVacancySberTests build analyze

# F — cwd HHVacancySber
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor test

# R — cwd HHVacancySber
xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-refactor-release build analyze

# P / D / B — cwd корень
/usr/bin/python3 -m unittest discover -s scripts/tests -q
git diff --check
bash -n scripts/benchmarks/build.sh
```

| Baseline | Код | Всего / пропущено / упало | Продолжительность | Существенный вывод |
|---|---:|---:|---|---|
| U | 0 | 77 / 1 / 0 | action 28,999 с; testing 9,502 с | succeeded |
| F | 0 | 87 / 1 / 0 | action 140,499 с; testing 139,933 с | succeeded |
| R | 0 | — | Первое время не записано; измеренный повтор real 1,12 с | Без диагностик |
| P | 0 | 71 / 0 / 0 | 19,767 с | OK |
| D | 0 | — | Отдельный таймер не фиксировался | Пустой вывод |
| B | 0 | — | Отдельный таймер не фиксировался | Пустой вывод |

Фактический stdout/stderr xcodebuild baseline (существенные строки, не реконструкция по памяти):

```text
2026-09-04 05:41:59.561 xcodebuild[20955:1002149] [MT] IDETestOperationsObserverDebug: 9.502 elapsed -- Testing started completed.
Testing started
2026-09-04 05:44:47.301 xcodebuild[22027:1006391] [MT] IDETestOperationsObserverDebug: 139.933 elapsed -- Testing started completed.
Testing started
```

Коды 0 получены от процессов; числа и succeeded — из xcresult, поскольку quiet-вывод не печатает totals. Неуспешных тестов baseline не было. Единственный пропуск — opt-in live HH; он не включался.

## 3. Изменения

Все пути в таблице относительно корня. Производственные исправления внесены последовательно; до следующего исправления запускался полный U. Прежний dirty diff не откатывался.

| Файл / строки | Проблема и доказательство | Красный тест | Минимальная правка | Проверка / риск |
|---|---|---|---|---|
| HHVacancySber/HHVacancySber/AreaDirectoryStore.swift:121,132 | catch превращал CancellationError в stale success либо unavailable; клиент, игнорирующий отмену, мог записать поздний ответ | Два area cancellation tests; 2/2 упали | Проверить Task cancellation после await; пробросить CancellationError до общего catch; +3 строки | U: 79/1/0, код 0. Низкий риск: обычный offline fallback и cache-write warning сохранены |
| HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift:1763 | Отмена после последней отрисованной страницы не проверялась перед atomic write; новый файл появлялся, старый заменялся | PersonalPDFCancellationOnLastPage…; упал | Один Task.checkCancellation после validate и перед write | U: 80/1/0, код 0. Кооперативная отмена, не обещание прервать уже начатый syscall |
| Тот же файл:210,220,228 | Отсутствующие details скрывали имеющиеся summary department/date/salary | PDFFallbackPreservesSummaryFields…; 3 missing-field assertions | Использовать существующие fallback-свойства; оставить приоритет details даты | U: 81/1/0, код 0. Восстановленные поля могут увеличить объём текста, правила вёрстки не менялись |
| HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift | Недостаточное доказательство перечисленных веток и бережности multi-part | 4 новых regression tests до fixes | 8 новых tests всего, локальный mock; дополнены assertions прежнего 101-vacancy test | U: 85/1/0, код 0. Нет новых зависимостей, ослабления или удаления тестов |
| REFACTOR_REPORT_2026-09-04.md | Нужен отдельный отчёт текущего прогона | Не относится к production | Этот документ | Прежние отчёты не переписывались |

Фактические сообщения красных xcresult:

```text
failed - Cancellation must not return a stale snapshot
failed - Cancellation was replaced with unavailable
failed - A late successful response must not complete a cancelled load
XCTAssertFalse failed

failed - Cancellation on the final page must prevent publication
XCTAssertFalse failed
XCTAssertEqual failed: ("34913 bytes") is not equal to ("34380 bytes")

XCTAssertTrue failed - Lost summary department
XCTAssertTrue failed - Lost summary publication date
XCTAssertTrue failed - Lost summary salary
```

Красные команды — Debug xcodebuild с теми же project/scheme/destination/derivedDataPath, действием `test` и `-only-testing:HHVacancySberTests/HHVacancySberTests/<полное имя теста>`; первая команда имела два таких селектора.

| Порция | Красный action / код / totals | Зелёный полный U action / код / totals |
|---|---|---|
| Area | 05:46:23.202–05:46:29.648, 6,446 с; 65; 2/0/2 | 05:47:02.706–05:47:13.013, 10,307 с; 0; 79/1/0 |
| Personal cancellation | 05:48:06.828–05:48:13.485, 6,657 с; 65; 1/0/1 | 05:48:45.746–05:48:56.595, 10,849 с; 0; 80/1/0 |
| Fallback fields | 05:50:07.581–05:50:14.306, 6,725 с; 65; 1/0/1 | 05:50:38.135–05:50:48.677, 10,542 с; 0; 81/1/0 |
| Дополнительные assurance tests | Не объявляются красными; production не менялся | 06:51:35.813–06:51:53.501, 17,688 с; 0; 85/1/0 |

Классификация: три перечисленных дефекта — доказанные локальные исправления. Недоступный пункт UI-меню в финальном прогоне — отдельное наблюдение, не автоматически production-регрессия. Неполная видимость export status — кандидат для красного UI-теста. Кеш, буферы, progressive search — архитектурные/нагрузочные вопросы. Различные tie-breakers/форматтеры, recovery directories и fixture fatalError — ложные кандидаты на механическую очистку.

## 4. Тесты

Все 8 новых тестов находятся в `HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift`. Время — duration конкретного теста из успешного assurance xcresult 06:51:35, не стоимость всей сборки.

| Новый тест (полное имя после test) / строка | Цель | Чем падал до исправления | Время, с |
|---|---|---|---:|
| AreaDirectoryCancellationNeverBecomesStaleSuccessOrUnavailable / 199 | CancellationError с существующим stale cache и без cache; исходные байты неизменны | Возвращал stale snapshot либо unavailable | 0,006319 |
| AreaDirectoryTaskCancellationDoesNotPublishLateResponse / 222 | Настоящий Task.cancel во время приостановленного запроса; поздний ответ не публикуется | Возвращался success и создавался cache | 0,001202 |
| PersonalPDFCancellationOnLastPageNeverPublishesAndAllowsRetry / 1122 | Реальная отмена в didRenderPage, новый/существующий destination, успешный retry | Новый файл появлялся, старые байты заменялись | 0,078833 |
| PDFFallbackPreservesSummaryFieldsInPersonalAndFavoriteDocuments / 1160 | PDFKit: два типа экспорта, все проверяемые summary fields, title/snippet по одному разу | Терялись department/date/salary | 0,049081 |
| PDFFallbackDoesNotOverrideAvailableDetailFields / 1200 | PDFKit: details остаются приоритетными; чужие summary значения отсутствуют | Assurance, до отдельной production-правки не падал | 0,015635 |
| PDFPublicationFailureAndCancellationRestoreOriginalsAndRetainRecovery / 1221 | Отказ и настоящая отмена между двумя частями; byte-exact rollback, quarantine valid PDF, marker | Assurance; новой production-правки не потребовалось | 1,661304 |
| PDFStagedValidationFailureLeavesOriginalUntouched / 1260 | Отказ validation до backup/publish не меняет оригинал | Assurance; новой production-правки не потребовалось | 0,025930 |
| PDFCollisionRetainsBackupForNonDestructiveManualRecovery / 1282 | Чужой файл не затирается; backup сохраняется и копируется для восстановления | Assurance; новой production-правки не потребовалось | 0,030654 |

Ранее существовавший `testFavoritePDFExportProducesBoundedValidPartsAndMainActorProgress` дополнен извлечением текста обоих томов: все 101 title-line ровно по одному разу, в исходном порядке через границу частей; CreationDate и Producer присутствуют. Это усиление существующего теста, не девятый новый тест.

Числа: unit 77 → 85 (76 → 84 успешных, штатный skip 1 → 1); UI 10 → 10, новых UI-тестов нет; Python 71 → 71, новых нет. Проверки без live-сети, случайного input и дополнительных package dependencies. Детерминированные сигналы используются вместо задержек для управления отменой. Существующие проверки фильтров статистики, archive persistence, snapshot и request gate сохранены и входят в U/F.

Отклонённые кандидаты: тесты приватной реализации/дублирование прежних фильтров; искусственное ослабление menu assertion ради green; byte-equality PDF при плавающих Quartz metadata; живой HH для воспроизведения ошибки; новые release-тесты без правок release tooling. Не утверждается, что весь набор полей HH на всех комбинациях missing-data исчерпывающе покрыт.

## 5. Экраны

Новые экраны не создавались, существующие не заменялись. `/design` [НЕ ВЫПОЛНЕНО]: callable-команды нет, продуктовая/UI-правка в этом прогоне не предпринята. Макетов нет, SwiftUI-реализации сверх исходного dirty состояния нет. Это не приёмка каждого возможного состояния экрана.

| Экран/область | Существующий контракт | Фактическое UI-покрытие | Пробел |
|---|---|---|---|
| Поиск / все вакансии | Начальное состояние, загрузка, список, empty, ошибка; обновление и локальные фильтры | testLaunch, testSearchShowsConfiguredVacanciesAndLazyDetails, testEmptyResponseIsExplicit, testSearchFailureIsExplicit | Отдельная приёмка loading/stale после ошибки не добавлена |
| Toolbar / фильтры | Одна строка, работодатель + субъект, включая отсутствие совпадений | testToolbarUsesOneAlignedRowWithoutExternalFilterLabels, testEmployerDropdownListsOptionsAndFiltersResults, testRegionDropdownCombinesWithEmployerAndCanShowNoMatches | Зафиксирован единичный сбой открытия/поиска пункта «СБЕР»; причина не доказана |
| Избранное | Добавление, режим, PDF-команды | testFavoritePDFCommandsHaveMatchingHeightAndNoLeadingStatisticsIcon | Нет отдельного UI-теста каждого persistence warning / archive transition |
| Детали | Lazy load одной карточки, содержимое/ошибка | Успешная lazy-карточка в testSearchShowsConfiguredVacanciesAndLazyDetails; переходы дополнительно unit | Не все UI-состояния detail error/cancel приняты |
| Статус / PDF | Доступность, высота и правое выравнивание команд; combined-filter empty допускает report | testStatisticsPDFButtonIsAlignedAndAvailableForFilteredRows, testStatisticsCommandRemainsAvailableForEmptyCombinedFilter | Нативные save/replace/recovery dialogs не прогнаны по каждому состоянию |

Снимки: существующие UI-тесты прикладывают keepAlways screenshots отдельных состояний, геометрия/доступность проверяются assertions, не только картинками. Историческое ограничение Xcode `Error writing attachment data` сохраняется как риск; в assurance-прогоне были предупреждения о записи PDF attachments. Полнота всех UI-снимков [НЕ ВЫПОЛНЕНО], не выводится из зелёного статуса тестов. Нового дизайна или визуальной приёмки каждого экрана не заявлено.

Кандидат: `VacancySearchViews.swift:98` показывает общий statusMessage под условием isLoading; сообщения personal/favorites export после завершения могут не попадать в эту полосу. До изменения нужен воспроизводимый red UI-test и согласование контрактов ошибок/предупреждений; в этом прогоне представления не изменены.

## 6. PDF

Проверен существующий pipeline, без смены формата или локали:

- Статистика фиксирует локальную конфигурацию, rows и названия фильтров до диалога; имя различает режим/ID/фильтры, санитизируется и ограничивается UTF-8 бюджетом. Список — от свежей даты к старой, invalid/missing в конце, равные даты по ID.
- Избранное фиксирует локальные значения/состав до await; remote details не образуют атомарный HH snapshot. Worker сохраняет порядок входа, без параллельной перестановки.
- HTML очищается, удалённые изображения/шрифты не загружаются. Локальные date/number policies и reduced fonts сохранены. Missing не превращается в ноль; существующие details приоритетны, теперь используются доступные summary department/date/salary.
- A4, page-local layout и разбиение по абзацам; части обычно до 100 страниц. Одна очень длинная вакансия может быть отдельной частью больше 100 страниц — это не новый абсолютный cap.
- Сначала render/validation, затем atomic single-file write либо staged parts. Многофайловая публикация проверяет identity/digest, backup, коллизии; rollback не затирает чужой результат, сохраняет quarantine/backup с явными recovery paths.
- Готовые PDF Data удерживаются до публикации; statistics материализуется целиком. Измерений нового выигрыша RSS/CPU нет.

Бережность через PDFKit: 101 вакансия → 100+1 страниц, каждый заголовок ровно один раз в правильном порядке; fallback personal/favorites → по одной читаемой странице, title/snippet/link/department/date/salary и notice сохранены; обратный тест приоритета деталей исключает подмену. Существующие statistics tests проверяют обе оси фильтра, избранное, empty/multipage, замены содержимого, даты, имена и snapshot; они не написаны заново в этом прогоне.

Отказ и отмена: staged validation failure сохраняет оригинал; отмена последней страницы personal не оставляет новый final-файл и сохраняет старые байты; retry успешен. Ошибка и cancel перед второй частью после публикации первой восстанавливают оба оригинала byte-exact, а новый первый том находится в recovery quarantine и открывается PDFKit. Это не глобально атомарная многофайловая транзакция для внешних наблюдателей во время публикации; проверено конечное безопасное состояние после обработки отказа.

Восстановление практически выполнено тестом: конфликтующий чужой файл оставлен без изменений; сохранённый backup скопирован в **новое** имя, открывается PDFKit, байты равны исходным. Применимая процедура владельца: не удалять recovery directory; проверить указанные error paths, скопировать backup в свободное имя, проверить файл и только затем отдельно решать замену конфликтующего destination. `.cleanup_forbidden` и сохранение каталогов не упрощались. Реальный disk-full, crash/power-loss посреди syscall [НЕ ВЫПОЛНЕНО]; есть инъекция отказов, не их полная аппаратная эквивалентность.

Метаданные: PDFKit подтвердил наличие CreationDate (Date) и Producer (String). Poppler pdfinfo тестового файла: A4 595,28 × 841,89 pt, 1 страница, PDF 1.3, 39 343 байта, producer Quartz PDFContext, CreationDate/ModDate 04.09.2026 05:50:44 MSK; без JavaScript, forms, encryption. Проверено текущее окружение, не межверсийная идентичность.

Навык PDF использован для независимого визуального QA: два реальных XCTest PDF экспортированы из зелёного xcresult, оба одностраничных fallback-документа отрендерены Poppler и просмотрены целиком; восстановленные поля читаемы, обрезаний не обнаружено. Типографика и layout code не менялись. Артефакты проверки: `/private/tmp/HHVacancySber-refactor-pdf.upAtEw`; это синтетические тестовые данные, не пользовательский экспорт.

**Детерминированность при закреплённых CreationDate и document ID — [НЕ ВЫПОЛНЕНО].** `pdfData` создаёт CGContext с nil auxiliary metadata (`FavoriteVacanciesPDFExporter.swift:2048`), Quartz формирует метаданные/ID сам. Инъекция `now` у exporter фиксирует имя/контекст отчёта, но не эти поля. Нельзя выдать сравнение текста или размеров за детерминированность файла. Минимальный следующий шаг — согласовать тестовый способ фиксации обоих полей без изменения production PDF-контракта; затем сравнить повторные результаты. Renderer и trailer ради этой проверки не переписывались.

## 7. Намеренно не изменено

Архитектура, MainActor/worker isolation, форматтеры разных контрактов, HTTP-параметры, схема JSON v2, приоритеты и tie-breakers, внешний вид экранов, PDF-шрифты/локаль/пагинация, transaction/recovery — сохранены, кроме трёх доказанных локальных исправлений выше. Не вводились зависимости, линтер, форматтер, AGENTS.md, вторая схема и слои абстракции.

Не менялись авторизация и её значения, project.pbxproj, scheme, CI, signing/build settings, требования macOS/Xcode, release tooling, assets/icons, fail-fast fixtures. Release/DMG/publication и live HH не выполнялись. Python suite тестирует скрипт на фикстурах; реальный выпуск продукта не запускался.

Прежние пользовательские правки включают статистический PDF, стили PDF-команд и статусной строки, network/collection оптимизации, date parsing, snapshot/persistence fixes. Они сохранены и не приписываются этому прогону. Размер PDF-модуля не считается самостоятельным дефектом.

## 8. Отложено

| Вопрос | Доказательство / граница | Минимальный следующий шаг |
|---|---|---|
| Детали сессии без TTL/cap | Действующий cache lifetime; изменение затронет freshness/сеть | Согласовать freshness contract и длительный workload; измерить рост |
| Progressive search / retries / cooldown | Действующая выдача после полного сбора; единственный completeness retry, defaults URLSession | Сначала определить частичные результаты/ошибки и собрать разрешённые метрики; не нагружать live HH |
| Итоговые PDF buffers / huge vacancy | Data всех частей удерживаются, oversized отдельно | Изолированный benchmark peak/lifetime на фиксированных данных; отдельное решение о writer |
| Безопасная очистка recovery | Каталоги намеренно сохраняют доказательства и backup | Отдельный контракт owner-approved symlink-safe cleanup; не удалять автоматически |
| Полная UI-приёмка и сохранение screenshots | Не все состояния перечисленных экранов имеют свой UI-тест | Детерминированные сценарии ошибок/loading/persistence; проверить attachments отдельно |
| Нестабильность menu UI-test | Один полный прогон не нашёл «СБЕР», baseline и неизменённый повтор прошли | При следующем воспроизведении сохранить hierarchy/screenshot и локализовать причину |
| Видимость export status | Условие isLoading в status bar | Red UI-test завершения/отказа PDF, затем решение по контракту отображения |
| PDF фиксированные metadata/ID | CGContext получает nil, нет injection seam | Согласовать тестовый механизм; binary determinism до этого не заявлять |
| CPU/RSS/leaks/disk-full/OS matrix | В этом прогоне не измерялись/не воспроизводились | Отдельные профили и стенд; старые benchmark-цифры не переносить сюда |

Неподтверждённые крайние сценарии не исправлялись спекулятивно. Связь UI-menu сбоя с текущими cancellation/PDF-правками не установлена. Не выполнялись обновления инструментов ради диагностики.

## 9. Проверки

Финальные команды используют cwd и точные U/F/R/P/D/B из раздела 2. F и R запускались с префиксом `/usr/bin/time -p`.

| Проверка | Фактический итог |
|---|---|
| U после всех новых unit-тестов | Код 0; xcresult succeeded, 85 / 1 skip / 0 fail; action 17,688 с, testing 11,433 с |
| Полный F, первая финальная попытка | Код 65; 95 / 1 skip / 1 fail; real 158,35 с, testing 153,415 с |
| Полный F, неизменённый повтор | Код 0; xcresult succeeded, 95 / 1 skip / 0 fail (85 unit + 10 UI); real 144,71 с, action 143,718 с, testing 143,321 с |
| R: Release build analyze | Код 0; real 11,99 с, user 0,66, sys 0,23; без диагностик xcodebuild |
| P: Python | Код 0; 71 tests, 19,551 с, OK |
| D: git diff --check | Код 0, пустой вывод, включая повтор после создания отчёта |
| B: bash -n scripts/benchmarks/build.sh | Код 0, пустой вывод |
| Дополнительно bash -n scripts/release.sh | Код 0; только syntax, не выпуск |
| Credentials / project / scheme / CI | Diff по auth/config/project/CI пуст; SHA-256 всех 48 tracked files сравнены с исходной рабочей копией, изменены только AreaDirectoryStore, PDF exporter и unit tests. Собственный diff просмотрен: credentials не добавлены/не выведены |
| Внешний macOS CI | [НЕ ВЫПОЛНЕНО] в этой сессии: push/публикация запрещены. Локальные проверки не выдаются за внешний CI |
| Полный диапазон OS/Xcode | [НЕ ВЫПОЛНЕНО], доступна только фактическая среда выше |

Фактический вывод первой финальной F-попытки:

```text
2026-09-04 06:54:57.842 xcodebuild[35520:1140035] [MT] IDETestOperationsObserverDebug: 153.415 elapsed -- Testing started completed.
Failing tests:
    HHVacancySberUITests.testRegionDropdownCombinesWithEmployerAndCanShowNoMatches()
    HHVacancySberUITests.testRegionDropdownCombinesWithEmployerAndCanShowNoMatches()
** TEST FAILED **
Testing started
real 158.35
user 7.03
sys 4.92
```

Две строки Failing tests относятся к двум assertions **одного** теста. xcresult: `failed - Missing СБЕР in employerFilterPicker` (helper около строки 182) и `XCTAssertTrue failed` в том же тесте. Totals именно 95/1 skip/1 fail, не два упавших теста. UI-файл не редактировался для повтора.

Повтор полного F без изменения кода завершён успешно. Фактический вывод:

```text
2026-09-04 06:59:14.564 xcodebuild[37232:1158966] [MT] IDETestOperationsObserverDebug: 143.321 elapsed -- Testing started completed.
2026-09-04 06:59:14.564 xcodebuild[37232:1158966] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-09-04 06:59:14.564 xcodebuild[37232:1158966] [MT] IDETestOperationsObserverDebug: 143.321 sec, +143.321 sec -- end
Testing started
real 144.71
user 3.87
sys 2.40
```

Процесс вернул 0. Проверен `/private/tmp/HHVacancySber-refactor/Logs/Test/Test-HHVacancySber-2026.09.04_06-56-50-+0300.xcresult`: action `succeeded`, testsCount `95`, testsSkippedCount `1`, failures отсутствуют, issues пуст. Число тестов выросло 87 → 95, пропуск не изменился; все 10 UI-тестов этого повтора успешны. Это не доказательство причины предыдущего menu-сбоя и не замена отсутствующих UI-сценариев.

Фактический вывод финальных R/P:

```text
real 11.99
user 0.66
sys 0.23
----------------------------------------------------------------------
Ran 71 tests in 19.551s

OK
```

Исходные и промежуточные metrics извлечены xcresulttool до ротации Xcode logs; Xcode хранит ограниченное число bundles. Текущие DerivedData сохранены в `/private/tmp/HHVacancySber-refactor` и `/private/tmp/HHVacancySber-refactor-release` для диагностики. Исторические bundles, автоматически удалённые Xcode, не объявляются доступными. Приложение с живыми пользовательскими данными не запускалось.

## 10. Git

Исходный `git status --short`:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHAPIClient.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/VacancyCollectionService.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
?? MAINTENANCE_REFACTOR_REPORT.md
?? OPTIMIZATION_REPORT.md
?? scripts/benchmarks/
```

В `scripts/benchmarks/` исходно три untracked-файла: README.md, RuntimeBenchmarks.swift, build.sh; они не менялись. Два прежних untracked-отчёта также не менялись.

Исходный diffstat: 9 файлов, 1831 добавление, 194 удаления. Числа изменённых строк по файлам: PDF exporter 474, HHAPIClient 33, HHModels 16, collector 54, ViewModel 103, views 93, unit tests 1164, UI tests 83, README 5. Это накопленные прежние изменения, не собственная работа текущего прогона.

Финальный `git status --short`:

```text
 M HHVacancySber/HHVacancySber/AreaDirectoryStore.swift
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHAPIClient.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/VacancyCollectionService.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
?? MAINTENANCE_REFACTOR_REPORT.md
?? OPTIMIZATION_REPORT.md
?? REFACTOR_REPORT_2026-09-04.md
?? scripts/benchmarks/
```

Финальный `git diff --stat` (новый untracked-отчёт штатно не входит):

```text
 .../HHVacancySber/AreaDirectoryStore.swift         |    3 +
 .../FavoriteVacanciesPDFExporter.swift             |  481 +++++--
 HHVacancySber/HHVacancySber/HHAPIClient.swift      |   33 +-
 HHVacancySber/HHVacancySber/HHModels.swift         |   16 +
 .../HHVacancySber/VacancyCollectionService.swift   |   54 +-
 .../HHVacancySber/VacancySearchViewModel.swift     |  103 +-
 .../HHVacancySber/VacancySearchViews.swift         |   93 +-
 .../HHVacancySberTests/HHVacancySberTests.swift    | 1437 +++++++++++++++++++-
 .../HHVacancySberUITests.swift                     |   83 +-
 README.md                                          |    5 +
 10 files changed, 2111 insertions(+), 197 deletions(-)
```

Собственные tracked-изменения относительно сохранённого начального рабочего содержимого: AreaDirectoryStore +3/−0; PDF exporter +4/−3; unit tests +273/−0. Всего **+280/−3 в трёх файлах**, плюс новый отчёт. Контрольные суммы остальных 45 tracked-файлов совпадают с началом; прежние правки внутри PDF/tests сохранены, собственный production diff проверен отдельно.

HEAD прежний, staged diff пуст. Не выполнялись git add, staging, commit, push, stash, reset, restore, clean, checkout или операции отмены истории. Пользовательские Application Support, PDF, recovery directories и untracked-файлы не удалялись. Удаления в тестах ограничены собственными синтетическими temporary directories через defer; пользовательские данные в эти тесты не передавались.

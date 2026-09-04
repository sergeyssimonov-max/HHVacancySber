## 1. Итог

Удалены только проверенные временные сборки и индексы; диагностические xcresult и PDF/PNG сохранены в карантине.
Объём временных артефактов с учётом карантина уменьшился на 264,2 МиБ по du; код не сокращался.
Все 54 исходных файла сохранены побайтово; в репозитории добавлен только этот отчёт.
До и после: 95 unit/UI-тестов, один штатный пропуск, без падений; Release build/analyze и 71 Python-тест успешны.
Сборка Debug с нуля подтверждена; схема, ресурсы, PDF-экспортер, CI и настройки не менялись.
Оговорки: индекс ссылок SourceKit-LSP и запуск /design недоступны; неподтверждённый код не удалялся.
Карантин опустошает владелец после решения по сохранённой диагностике.

## 2. Мера

Начальный замер du -sk: репозиторий 3676 KiB, .git 2636, HHVacancySber 588, scripts 308, docs 4, .github 4.
Старые временные каталоги: refactor 380612 KiB, refactor-release 81508 KiB, refactor-pdf.upAtEw 232 KiB.
Library DerivedData проекта: 20 KiB, только измерен; изменение запрещено ограничением на внешние пути.
48 tracked-файлов: Swift 16 / 7608 строк / 345211 байт; Python 4 / 3290 / 143297; ресурсы 19 / 209 текстовых строк / 123428 байт; прочие 9 / 4412 / 188451. PNG не интерпретировались как текст.
Сняты SHA-256 всех 48 tracked и 6 прежних untracked-файлов; финальная сверка всех 54 совпала. Строки считаются по текущему содержимому git ls-files, не по чистому HEAD; binary PNG не включены в строки.

| Показатель | До | После | Разница |
|---|---:|---:|---:|
| Старые /private/tmp/HHVacancySber-* (KiB) | 462352 | 0 | −462352 |
| Карантин этого прогона (KiB) | 0 | 191804 | +191804 |
| Старые временные данные + карантин (KiB) | 462352 | 191804 | −270548 = −264,207 МиБ |
| Временные сборки самого прогона | 0 | 0 | Удалены после проверки, не считаются отдельным выигрышем |
| Репозиторий без нового отчёта, включая .git (KiB) | 3676 | 3676 | 0 |
| Репозиторий с новым отчётом (KiB) | 3676 | 3712 | +36, только отчёт |
| .git (KiB) | 2636 | 2636 | 0 |
| HHVacancySber / scripts / docs / .github (KiB) | 588 / 308 / 4 / 4 | 588 / 308 / 4 / 4 | 0 |
| Library DerivedData проекта (KiB) | 20 | 20 | 0 |
| Tracked Swift: файлы / строки / байты | 16 / 7608 / 345211 | 16 / 7608 / 345211 | 0 |
| Tracked Python: файлы / строки / байты | 4 / 3290 / 143297 | 4 / 3290 / 143297 | 0 |
| Tracked resources: файлы / текстовые строки / байты | 19 / 209 / 123428 | 19 / 209 / 123428 | 0 |
| Прочие tracked: файлы / строки / байты | 9 / 4412 / 188451 | 9 / 4412 / 188451 | 0 |
| Все tracked / untracked-файлы | 48 / 6 | 48 / 7 | +1 отчёт |
| Git objects count / size | 308 / 2.45 MiB | 308 / 2.45 MiB | 0 |
| Git packs / in-pack / garbage | 0 / 0 / 0 | 0 / 0 / 0 | 0 |

Сумма старых временных каталогов — 451,516 МиБ; карантин — 187,309 МиБ. Изменение объёма — очистка build/cache, а не сокращение кода. Новый отчёт отдельно увеличивает размер репозитория. du — учёт блоков по путям, не гарантия изменения свободных APFS-блоков: df -h показал 164 GiB доступно в начале и 155 GiB в конце на том же томе. Общесистемное изменение вне измеренных путей не атрибутируется очистке и не исследовалось за пределами разрешённого scope.

Чистая Debug build/analyze: 9,51 → 9,88 с (+0,37 с); unit+build+analyze с новым DerivedData: 28,56 → 25,12 с; полный test: 163,74 → 144,75 с. Это по одному наблюдению, не доказательство ускорения или замедления от очистки.

## 3. Реестр кандидатов

Фаза 2 завершена и записана до первого удаления. Все размеры — du -sk (KiB), все временные корни проверены stat: обычные каталоги владельца mygga, не symlink. lsof +D по семи точным временным путям не показал открытых файлов (пустой вывод, код 1). Исходные пути сопоставлены с прошлым отчётом и текущими командами; runtime recovery/Application Support в них не входят.

| Путь | KiB | Класс / Git | Доказательство | Решение / восстановление |
|---|---:|---|---|---|
| /private/tmp/HHVacancySber-refactor | 380612 | Старые DerivedData, вне Git | info.plist, Build/Products, ModuleCache, Index, Logs; указан в прошлом отчёте | Удалить регенерируемую часть; Logs/Test 184312 KiB уже в карантине. U/F одной командой, менее 5 минут по новому baseline; исторический сбой не регенерируется |
| /private/tmp/HHVacancySber-refactor-release | 81508 | Старые Release DerivedData, вне Git | Содержит результаты прежнего Release build/analyze | Удалить; одна R, новый baseline 16,89 с |
| /private/tmp/HHVacancySber-refactor-pdf.upAtEw | 232 | Уникальные тестовые PDF/PNG, вне Git | Четыре файла прошлого QA | Не уничтожать: проверенная копия в карантине, удалить только оригинал временного каталога |
| /private/tmp/HHVacancySber-cleanup | 199520 | Baseline DerivedData этого прогона, вне Git | Создан текущими U/F | Logs/Test 3728 KiB сохранены, 109 файлов проверены SHA; остальное удалить и восстановить одной U/F |
| /private/tmp/HHVacancySber-cleanup-release | 82548 | Baseline Release этого прогона | Создан R | Удалить; одна R |
| /private/tmp/HHVacancySber-cleanup-cold | 103696 | Baseline чистой Debug-сборки | Создан отдельной build analyze | Удалить; повтор той же команды измерит чистую сборку |
| /private/tmp/HHVacancySber-cleanup-probe | 2924 | Индекс неудачного LSP-probe | Создан только запросом SourceKit; нет исходников | Удалить cache; повтор LSP создаёт его заново, ссылок не подтвердил |
| /Users/mygga/Library/Developer/Xcode/DerivedData/HHVacancySber-gaoobrltknlwemgzwfyzpidwxpzb | 20 | Внешний проектный cache | Измерен read-only | Оставить: ограничение на изменения вне repo/quarantine/private tmp важнее общего предложения чистить DerivedData |
| Три пары PNG и два Contents.json в asset catalogs | См. раздел 6 | Дубликаты SHA, tracked | Каждый файл имеет собственную build/resource ссылку | Оставить все экземпляры |
| xcshareddata/swiftpm/configuration внутри workspace | 0 файлов | Пустая автоматически созданная структура | find -type f пуст; manifests/lock нет | Оставить: не пакетная зависимость, не доказанный мёртвый код |

Классы без кандидатов в дереве вне .git: .bak/.old/.orig, .pyc, .DS_Store/AppleDouble, .log/.crash/.diag/.ips, swap/tmp, посторонние zip/dmg/app, xcuserdata/персональные схемы, build/Products/xcresult. Git ignored-вывод дополнительных файлов не показал. Неприкосновенные untracked-отчёты/benchmarks не рассматриваются как мусор. Внешние crash/общие кеши не сканировались и не трогались.

## 4. Удалено безвозвратно

Фаза 3 завершена: семь точных путей из реестра удалены командой с явными абсолютными аргументами, без масок/find -delete/xargs rm; код 0. Безвозвратно удалены только регенерируемые build/cache/index части. Исходные временные Logs/Test и PDF/PNG имеют проверенные копии в карантине и не потеряны.

Сразу после удаления find /private/tmp -maxdepth 1 -name HHVacancySber-* не вывел путей. Затем та же отдельная Debug build analyze в /private/tmp/HHVacancySber-cleanup-cold восстановила сборку с нуля: код 0, real 9,88 с против baseline 9,51 с (+0,37 с; единичные замеры, не вывод о скорости). Фаза 3 записана до перехода к фазе 4. Репозиторий не чистился, git diff --check чист.

| Безвозвратно удалённая часть | Класс | Восстановление одной командой из раздела 10 |
|---|---|---|
| /private/tmp/HHVacancySber-refactor, кроме сохранённого Logs/Test | Debug build/cache/index | U или F с derivedDataPath /private/tmp/HHVacancySber-refactor |
| /private/tmp/HHVacancySber-refactor-release | Release build/cache | R с derivedDataPath /private/tmp/HHVacancySber-refactor-release |
| /private/tmp/HHVacancySber-cleanup, кроме сохранённых baseline/final Logs/Test | Debug build/cache/index | U или F |
| /private/tmp/HHVacancySber-cleanup-release | Release build/cache | R |
| /private/tmp/HHVacancySber-cleanup-cold | Debug build/cache/index | C |
| /private/tmp/HHVacancySber-cleanup-probe | Временный LSP index-db | Новый SourceKit-LSP probe с -index-db-path внутри этого пути; ценного результата запрос не дал |

После фазы 7 вновь созданные cleanup (199268 KiB), cleanup-release (82548 KiB) и cleanup-cold (103852 KiB) удалены повторно точными абсолютными путями; перед этим lsof не показал открытых файлов, final xcresult скопированы и проверены. Код удаления 0. Финальный поиск HHVacancySber-* в /private/tmp пуст. PDF/PNG из refactor-pdf.upAtEw и все сохранённые xcresult относятся к карантину, а не к безвозвратной потере.

## 5. Карантин

Создан `/Users/mygga/.hhvacancysber-cleanup/2026-09-04-0707`.
Для незакрытого вопроса прошлого прогона скопированы `private/tmp/HHVacancySber-refactor/Logs/Test` (2159 файлов) и `private/tmp/HHVacancySber-refactor-pdf.upAtEw` (4 файла), SHA-256 копий совпадают. Исторические результаты не объявляются регенерируемыми. Инструкция — README.md в карантине.

Дополнительно: `private/tmp/HHVacancySber-cleanup/Logs/Test` — baseline, 109 файлов; `after/private/tmp/HHVacancySber-cleanup/Logs/Test` — финальная приёмка, 109 файлов. Все копии проверены SHA-256; финальный полный xcresult читается прямо из карантина. Префикс after разделяет снимки, далее сохранён исходный путь.

Всего 2381 файл данных плюс README.md, 191804 KiB. Исторический failed UI-run не воспроизводится гарантированно ни за пять минут, ни одной командой, поэтому сохранён независимо от размера. Повторная сборка нового результата занимает менее пяти минут по baseline, но не заменяет прежнее наблюдение. Стоимость доступа к сохранённым данным — открыть PDF/PNG или выполнить xcresulttool get без восстановления сборки.

Владельцу: сохранить карантин до решения по UI-menu и PDF-диагностике; открывать данные на месте. Если нужен старый путь, сначала проверить отсутствие новых файлов там, затем скопировать конкретный сохранённый элемент, не сливая bundles и не перезаписывая новые данные. После проверки владелец сам решает, что удалить из карантина. Автоматического опустошения/публикации не было.

## 6. Мертвый код, ресурсы и остатки предка

Статический поиск охватил код, tests, scripts, project, Info.plist, asset Contents.json, scheme, CI, README/docs; auth values исключены из вывода. Счётчики Swift учитывали упоминания без строки объявления, отдельно внутри/вне файла. Нет static let с нулём упоминаний; низкая видимость сама по себе не была основанием удаления.

Нулевые прямые ссылки у VacancySearchViews.swift:268 makeCoordinator, :269 makeNSView, :273 updateNSView, :279 webView — callbacks NSViewRepresentable/WKNavigationDelegate, вызываются framework; оставлены. collectByDictionaries (:155 коллектора) имеет 1 внутренний вызов; runPersistenceDriver (:308 ViewModel) — 1 внутренний; openVacancyURL (:376) и copyVacancyURL (:382) — по 1 внешнему из closures карточки; updateArchiveStatus (:60 FavoriteVacancyStore) — 2 внешних вызова. AppComposition и DEBUG fixtures достижимы из @main. Декодируемые типы HHModels участвуют в моделях/PDF, не скоринг. Импорты имеют потребителей SDK; транзитивные импорты не чистились ради вкуса.

SourceKit-LSP доступен, initialize сообщил referencesProvider=true, но два probe завершились EOF: could not find manifest, or not a SwiftPM package; could not open compilation database for VacancySearchViewModel.swift. Перекрёстные ссылки через индекс [НЕ ВЫПОЛНЕНО]; пустого ответа об отсутствии usages не получено. Установка/новая compile database не предпринимались. Поэтому неподтверждённого удаления кода нет.

Python: все top-level helper functions verifier/render_icon имеют локальные или внешние вызовы; unittest discovery выполняет методы тестов. Release ссылается на verifier (:1166,2403), README — на render_icon (:47), benchmark build.sh — на RuntimeBenchmarks (:16), CI — на unittest. Мёртвый Python не доказан.

SHA-дубликаты (байты каждого файла пары): appicon_128x128@2x = appicon_256x256@1x — 8532; appicon_16x16@2x = appicon_32x32@1x — 1087; appicon_256x256@2x = appicon_512x512@1x — 19994. Полные пути всех PNG имеют префикс HHVacancySber/HHVacancySber/Assets.xcassets/AppIcon.appiconset/ и расширение .png; оба имени каждой пары перечислены в AppIcon Contents.json. HHVacancySber/HHVacancySber/Assets.xcassets/Contents.json и HHVacancySber/HHVacancySber/Preview Content/Preview Assets.xcassets/Contents.json — по 63 байта, но принадлежат разным подключённым каталогам. AppIcon/AccentColor заданы project.pbxproj:471–472,499–500; SVG используется render_icon и README. Удалений ресурсов нет.

Действующего скоринга и точных B1–B9/F-001–F-003 нет. CI legacy_* — проверка отсутствия старого имени; тест :72 проверяет миграцию исторических полей; HHModels:622 legacy — локальная адаптация salary, не скоринг. B13-DIST-001-R5-R6-R4 в release.sh — используемая диагностика отказов выпуска. Всё оставлено. DeskPalette — действующая палитра представлений, не удалённая подсистема.

Фаза 5 завершена и записана до фазы 6: порций удаления исходников/ресурсов нет, поэтому нет правок project.pbxproj, откатов и сокращения тестов. Безопасность отсутствия изменений дополнительно проверяется финальными SHA-256 и полным набором тестов.

## 7. Проект и конфигурации

Фаза 6 завершена и записана до финальной приёмки: одна shared scheme HHVacancySber, три target, Debug/Release. xcodebuild -list baseline: 0, real 0,65 с; после очистки тот же состав. Все 16 tracked Swift-файлов имеют Sources references. Осиротевших ссылок на удалённые файлы нет — исходники не удалялись. XCRemoteSwiftPackageReference/XCSwiftPackageProductDependency: 0; manifests/lock отсутствуют, пустой workspace swiftpm-каталог не означает зависимость.

Предложения удалить цели, конфигурации, build phases или шаги CI не обоснованы: app/unit/UI используются схемой, Debug тестируется, Release собирается, ресурсы подключены. Build settings, scheme, Info.plist, entitlements и ci.yml неприкосновенны и не менялись. Правок проекта не требуется.

## 8. Оставлено намеренно

Все прежние dirty/untracked-файлы, Library DerivedData, Application Support, runtime PDF recovery, авторизация и неприкосновенные файлы задания.

Фаза 4: посторонних файлов, xcuserdata/персональных схем, swap, архивов и бинарников для перемещения нет. Удалений/перемещений в дереве не выполнялось. xcodebuild -list: одна прежняя схема/три цели/Debug–Release, код 0, real 0,67 с. Повтор Debug build/analyze: код 0, real 1,06 с, без диагностик. Результат записан перед фазой 5.

## 9. Отложено

Из прошлого отчёта: UI-menu нестабильность, полнота UI-состояний и attachments, PDF metadata/ID determinism, кеши/буферы/progressive search. Очистка эти вопросы не решает.

Минимальные дальнейшие действия: для UI-сбоя использовать сохранённый failed xcresult и воспроизводимый сценарий; для метаданных PDF согласовать тестовый контракт, не менять формат в задаче очистки; для TTL/buffers/progressive loading сначала определить нагрузку и поведение. Полноценный индекс usages потребует настроенного Xcode-aware окружения владельца; по недоступному индексу код не удалять. Уникальных исходников/резервных копий, требующих отдельного решения на удаление, не найдено.

## 10. Проверки

Фаза 1 завершена и записана до начала фазы 2; на тот момент удалений не было. Baseline xcresult скопированы в карантин с исходным относительным путём: 109 файлов, SHA-256 совпали. Время ниже — real от /usr/bin/time -p, не сумма CPU.

Точные команды, Xcode из `/Users/mygga/Documents/ChatGPT/СберВакансии 2/HHVacancySber`, остальные из корня:

```sh
# U
/usr/bin/time -p xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-cleanup test -only-testing:HHVacancySberTests build analyze
# F
/usr/bin/time -p xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-cleanup test
# R
/usr/bin/time -p xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-cleanup-release build analyze
# C — отдельная чистая Debug-сборка
/usr/bin/time -p xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-cleanup-cold build analyze
# L
/usr/bin/time -p xcodebuild -quiet -project HHVacancySber.xcodeproj -list
# P / D / B / S — корень
/usr/bin/python3 -m unittest discover -s scripts/tests -q
git diff --check
bash -n scripts/benchmarks/build.sh
bash -n scripts/release.sh
```

| Проверка | До очистки: код / тесты / секунды | После очистки: код / тесты / секунды |
|---|---|---|
| U (с новым DerivedData) | 0 / 85, skip 1, fail 0 / 28,56 | 0 / 85, skip 1, fail 0 / 25,12 |
| F, полный unit + UI | 0 / 95, skip 1, fail 0 / 163,74 | 0 / 95, skip 1, fail 0 / 144,75 |
| R, Release build analyze | 0 / — / 16,89 | 0 / — / 15,79 |
| C, чистый Debug build analyze | 0 / — / 9,51 | 0 / — / 9,88 |
| L, схема/цели | 0 / прежние / 0,65 | 0 / прежние / 0,67 |
| C, инкрементальный после фазы 4 | — | 0 / — / 1,06 |
| P | 0 / 71, skip 0, fail 0 / 19,883 | 0 / 71, skip 0, fail 0 / 19,860 |
| D/B/S | 0 / пустой вывод | 0 / пустой вывод |

Существенный фактический вывод xcodebuild (totals отдельно прочитаны из xcresult):

```text
2026-09-04 07:07:04.267 xcodebuild[41614:1188120] [MT] IDETestOperationsObserverDebug: 11.134 elapsed -- Testing started completed.
Testing started
real 28.56
2026-09-04 07:10:38.177 xcodebuild[44114:1199968] [MT] IDETestOperationsObserverDebug: 161.359 elapsed -- Testing started completed.
Testing started
real 163.74
2026-09-04 07:20:00.321 xcodebuild[52823:1250614] [MT] IDETestOperationsObserverDebug: 11.122 elapsed -- Testing started completed.
Testing started
real 25.12
2026-09-04 07:22:48.659 xcodebuild[53853:1254614] [MT] IDETestOperationsObserverDebug: 143.546 elapsed -- Testing started completed.
Testing started
real 144.75
```

U/F baseline и финальные U/F имеют xcresult action succeeded; один skip — штатный живой HH, не включался. Набор фактически содержит 85 unit и 10 UI, а не устаревшие 77 + 10 из контекста задания. Новых тестов в очистке 0, assertions не менялись. Предупреждений компилятора в этих quiet-прогонах нет. Утверждений о полноте screenshot attachments не делается.

Финальный F проверен уже из копии карантина: `after/private/tmp/HHVacancySber-cleanup/Logs/Test/Test-HHVacancySber-2026.09.04_07-20-24-+0300.xcresult`; succeeded, 95 tests, skip 1, issues пуст. Все 109 файлов финального Logs/Test совпали с оригиналами по SHA-256. Финальный Release вывел только time: real 15.79 / user 0.65 / sys 0.25, xcodebuild без диагностик; Python: Ran 71 tests in 19.860s, OK.

Фаза 7 завершена и записана перед фазой 8: тестов не меньше baseline, skip прежний, Debug с нуля и Release успешны, схема прежняя, исходные 54 файла совпадают по SHA-256. Финальные regenerated build/cache каталоги подлежат удалению после сохранения результатов, чтобы проверка очистки не оставляла новый сборочный груз. Это не новая правка исходников.

Диагностика вспомогательных проверок: SourceKit-LSP не дал индекс usages; две первоначальные Ruby-выборки потребовали UTF-8 и синтаксис Ruby 2.6, исправленные read-only повторы успешны. Это не ошибки приложения/тестов. Внешний CI [НЕ ВЫПОЛНЕНО]: без push он не запускался; локальные проверки не выдаются за внешний гейт. release.sh не запускался как выпуск — только bash -n и его unittest-фикстуры; DMG, live HH и публикации отсутствуют.

## 11. Пригодность почвы

Debug с чистого DerivedData собирается, все 10 UI-тестов и unit PDF-сценарии проходят. Представления, экспортер, styles, ресурсы и тесты побайтово прежние; очистка не блокирует работу над экранами и PDF. Save/export/rollback/filter coverage берётся из существующих тестов, не из предположения по сборке.

Запуск `/design` [НЕ ВЫПОЛНЕНО]: callable-команда отсутствовала и до очистки. Новый макет/визуальная приёмка каждого состояния не входят в эту очистку; удалением ничего для них не изменено. Известные вопросы метаданных PDF и неполных screenshot attachments не закрываются автоматически. Для дальнейшего дизайна нужен доступный инструмент в окружении владельца; плагины не устанавливались.

## 12. Git

Фактическая среда — Codex на macOS 13.7.8 / Xcode 15.2 (15C500b) / Swift 5.9.2 arm64. claude plugin list прочитан, состав не изменён. Субагенты не запускались.
HEAD `c8d268eacffa83c5fa5ac1960b2b69844a46ef6e`, main. Origin `https://github.com/sergeyssimonov-max/HHVacancySber.git`. git fetch --dry-run: 0; git ls-remote подтвердил hash удалённой main `389412131f2223dbb009dd3959ac15893be87b2f`, совпадающий с локальной origin/main. HEAD...origin/main: 1 0, текущий HEAD на один коммит впереди. git count-objects -vH: count 308, size 2.45 MiB, packs/in-pack/garbage 0. Staging/commit/stash/история не менялись.

Исходный status: 10 modified — AreaDirectoryStore.swift, FavoriteVacanciesPDFExporter.swift, HHAPIClient.swift, HHModels.swift, VacancyCollectionService.swift, VacancySearchViewModel.swift, VacancySearchViews.swift в HHVacancySber/HHVacancySber; HHVacancySberTests.swift, HHVacancySberUITests.swift в своих targets; README.md. Untracked: MAINTENANCE_REFACTOR_REPORT.md, OPTIMIZATION_REPORT.md, REFACTOR_REPORT_2026-09-04.md, scripts/benchmarks/README.md, scripts/benchmarks/RuntimeBenchmarks.swift, scripts/benchmarks/build.sh. Исходный diffstat: 10 files, 2111 insertions, 197 deletions. git status --short --ignored не выявил дополнительных ignored paths.

Исходный git status --short:

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

Финальный git status --short (ignored-проверка не добавила путей):

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
?? CLEANUP_REPORT_2026-09-04.md
?? MAINTENANCE_REFACTOR_REPORT.md
?? OPTIMIZATION_REPORT.md
?? REFACTOR_REPORT_2026-09-04.md
?? scripts/benchmarks/
```

git diff --stat до и после одинаков:

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

Собственная правка в репозитории — только новый untracked CLEANUP_REPORT_2026-09-04.md, поэтому она не входит в git diff --stat. Все 48 tracked и 6 прежних untracked-файлов совпадают с началом по SHA-256, в том числе авторизация, схема, project, CI, resources, исходники и тесты. Значения credentials не выводились и не добавлялись. Staged diff пуст, HEAD и remote-tracking ref прежние. Не выполнялись add, commit, push, PR, stash, reset, restore, clean, checkout, gc/prune или переписывание истории.

Фаза 8: передан карантин с инструкцией; завершающие git diff --check, bash -n release.sh/build.sh и сверка статуса чисты относительно собственных изменений. Старые отчёты с путями /private/tmp не переписывались: перенесённые диагностические артефакты доступны по отображению путей в разделе 5.

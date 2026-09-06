## 1. Итог

- Принята одна production-оптимизация: проверка архивов использует проверяемый индекс избранного вместо полного поиска после каждого `await`.
- На 1 000 записей медиана wall/CPU снизилась на 28,76%/28,74%, на 5 000 — на 22,47%/22,46%; порядок запросов и сохранение результата не изменены.
- Правок надежности не потребовалось: atomic JSON write, PDF staging/backup/rollback, отмена и actor-isolation не ослаблены.
- Доказанного выигрыша памяти нет; session details cache измеренно растет примерно на 22–23 KiB на запись и оставлен без нового контракта.
- PDF после изменения совпал по 3 страницам, 40 428 байтам и извлеченному тексту; побайтовая идентичность недостижима без управления Quartz metadata/document ID.
- Полный Debug: 98 тестов, 2 штатных пропуска, 0 падений; unit `test + build + analyze`: 87/2/0; Release analyze и 72 Python-теста успешны.
- Приемка с оговорками: Instruments не получил authorization, время первого кадра не измерено, лимит/TTL кеша и единый структурированный UI error требуют решения владельца.
- Исходные пользовательские изменения сохранены; staging, commit, stash, reset, checkout, release/DMG и живая сеть не использовались.

## 2. Процедура замера

Исходное дерево: `/Users/mygga/Documents/ChatGPT/СберВакансии 2`, HEAD `6e76afdfc7086a598c029ed132eacf9b814d8bfe` (`Handle macOS FSEvents metadata during DMG creation`). На входе были только пять пользовательских modified-файлов: `FavoriteVacanciesPDFExporter.swift`, `VacancySearchViews.swift`, оба XCTest-файла и `REFACTOR_REPORT_2026-09-04.md`; 167 добавлений, 275 удалений, staged/untracked отсутствовали. SHA-256 исходного рабочего diff: `98851cea9dc34f3c129448dbd1bbfc6c7161cc6ccafc34a5b1e7b4b87e7f07cd`. Они не использовались как разрешение на дополнительные правки.

Среда: macOS 13.7.8 arm64, Xcode 15.2 (15C500b), Swift 5.9.2. Release собирался с нуля в пяти отдельных `derivedDataPath`; benchmark собирался `swiftc -O` вместе с production sources. Перед каждой timed-серией вне sandbox проверялось отсутствие `xcodebuild`, `swiftc`, `swift-frontend`, `clang`, `xctrace` и Instruments. Сборки, тесты и timed benchmark не выполнялись параллельно.

Неизменная матрица использовала только локальные actor-fixtures; методы неожиданной сети завершаются намеренным `fatalError`. Каждый штатный прогон создавал собственный `HHRuntimeBench-<UUID>` и удалял его с временными storage/export/recovery файлами.

| Сценарий | Фиксированный набор | Что проверялось |
|---|---:|---|
| gate | active 500 ms + queued cancellation | задержка отмены и serialization |
| enrichment | 100 избранных | cancel/rate-limit, повторный экспорт, число detail/export вызовов |
| session cache scaling | 100 / 1 000 / 5 000 | повторное получение деталей, RSS/CPU/wall |
| search | 1 000, 10 страниц | collector, точное число результатов и запросов |
| archive | 100 / 1 000 / 5 000 | последовательные details, обновление каждой записи и сохранение |
| personal/favorites PDF | 10 / 100 / 500 | render, PDFKit validation, transaction publish, страницы/байты |
| stress | 1 вакансия × 1 200 HTML-абзацев | Unicode, многостраничный layout |
| statistics | 2 000 | snapshot, render, atomic write, повторное открытие и последний ID |
| soak | 500 × 6 циклов | замена одного PDF, RSS и дескрипторы |

До и после — не меньше пяти отдельных процессов; в таблицах указаны медиана и полный размах `min–max` как процент медианы. Холодный Release отделен от прогретого парного A/B PDF 10. Порог разрешения: выигрыш меньше 5% не принимается; если размах больше 5%, меньшая разница считается неразличимой. Для регрессии больше 2% требуется объяснение или откат.

Инструменты: `/usr/bin/time -lp`, `getrusage`, heartbeat main actor, PDFKit, PDFInfo/Poppler, XCTest `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`. Opt-in XCTest выполнен ровно с пятью итерациями. `xcrun xctrace` 15.2 видел шаблоны Allocations/Leaks, но обе записи завершились `Failed to gain authorization`; `[НЕ ВЫПОЛНЕНО]` allocation/leak attribution. `[НЕ ВЫПОЛНЕНО]` время до первого кадра: App Launch trace требует той же недоступной авторизации, а signpost в приложении отсутствует. Ничего по памяти из этих двух недоступных измерений не утверждается.

Отбракованы без использования в выводах: первая матрица передала `"pdf 10"` одним аргументом; один финальный stress ошибочно запустил 1 200 вакансий по 1 200 абзацев и был остановлен; первый size probe искал внутреннее имя target вместо фактического `СберВакансии.app`. Все три ошибки оператора исправлены повторными измерениями, production-код ими не менялся; два оставшихся после SIGINT пустых UUID-каталога проверены и удалены через `rmdir`.

## 3. Надежность

| Класс | Доказательство | Цена отказа | Решение |
|---|---|---|---|
| Доказанный защитный механизм: JSON | `FavoriteVacancyStore.swift:207-210`: encode и `.atomic`; ViewModel coalescing driver `:299-325` | потеря/откат избранного | Не менять; migration, unsupported schema, retry и cancellation тесты зелены |
| Доказанный защитный механизм: PDF | `FavoriteVacanciesPDFExporter.swift:1447-1649,1690-1833`: stage, validate, backup, publish, rollback/recovery | готовый частичный файл либо потеря прежнего | Не менять; failure injection и PDFKit проверки зелены |
| Доказанный reentrancy-риск оптимизации | `VacancySearchViewModel.swift:345-355`: между выбором ID и записью есть `await`; пользователь может удалить/пересортировать favorite | обновление соседней записи и неверное сохранение | Кешированный индекс всегда сверяется с текущим ID; при stale строится заново (`:368-381`) |
| Измеренное узкое место | прежний `favorites.firstIndex` после каждого archive response давал 0,177 s/1 000 и 6,044 s/5 000 | CPU/main actor, без потери данных | Принята индексная карта; запросы остаются последовательными, сохранение одно |
| Доказанный открытый риск: disk/rights | atomic write/transaction выбрасывают ошибки; есть tests с file-system failure injection | невозможность сохранить либо manual recovery | Существующую диагностику сохранить; реальный disk-full не воспроизводился |
| Измеренный открытый риск: cache | `detailsCache` в `VacancySearchViewModel.swift:58,242-249,508-514` не имеет cap/TTL | рост RSS и устаревание деталей | Только предложение владельцу, production не менялся |
| Предположение: observability cost | `favorites` — `@Published`, archive меняет элементы по одному | оставшаяся нелинейность CPU | Без Instruments и без изменения UI/actor контракта не оптимизировать |

Production-правка является алгоритмической оптимизацией, а не исправлением надежности. Поэтому красного reliability-теста для нее нет: до правки корректный линейный поиск проходил. До изменения был добавлен и запущен зеленый invariant-тест с приостановленным первым запросом и удалением favorite во время `await`; после изменения он подтверждает, что индекс перепроверяется, соседняя запись получает статус и итоговое хранилище совпадает с ViewModel. Отдельные reliability-изменения без красного теста не вносились.

Новых пределов не введено. Измеренный кандидат для session cache — максимум 1 000 деталей (около 28,8 MB peak RSS в fixture) и TTL 30 минут, равный интервалу проверки архивов; свежесть такого TTL не доказана продуктовым контрактом, поэтому требуется решение владельца. Существующий предел PDF — 100 страниц на файл — сохранен и проверен набором 101.

## 4. Память

Peak RSS ниже — process `ru_maxrss`; изменение archive-кода не лежит на PDF/search путях. Проценты меньше собственного размаха не считаются выигрышем.

| Место | До, медиана | После, медиана | Изменение | Размах до / после | Вывод |
|---|---:|---:|---:|---:|---|
| archive 1 000 | 25 165 824 B | 24 461 312 B | −2,80% | 28,58% / 34,96% | неразличимо |
| archive 5 000 | 145 309 696 B | 138 346 496 B | −4,79% | 19,00% / 34,97% | неразличимо |
| PDF 10, paired | 25 739 264 B | 26 116 096 B | +1,46% | 4,90% / 23,46% | неразличимо |
| PDF 100 | 28 082 176 B | 28 901 376 B | +2,92% | 3,85% / 16,78% | шум, см. раздел 10 |
| PDF 500 | 60 768 256 B | 63 569 920 B | +4,61% | 6,39% / 3,76% | меньше baseline-размаха |
| stress, 1×1 200 | 33 030 144 B | 34 078 720 B | +3,17% | 22,90% / 13,89% | неразличимо |
| statistics 2 000 | 65 667 072 B | 64 569 344 B | −1,67% | 6,06% / 7,23% | неразличимо |
| soak 500×6 | 54 394 880 B | 54 411 264 B | +0,03% | 17,50% / 31,11% | неразличимо |

Зависимость PDF остается измеримой: 10/100/500 вакансий дали после 26,1/28,9/63,6 MB peak RSS, при неизменных 55 425/275 515/1 365 922 байтах PDF. `preparedParts` (`FavoriteVacanciesPDFExporter.swift:1664,1696-1725`) удерживает готовые `Data` до transactional publish, но сами итоговые 1,37 MB при 500 вакансиях объясняют лишь часть RSS. Цель непостоянной памяти не достигнута; без allocation trace и с риском ослабить откат streaming rewrite отклонен.

Session cache fixture: 100/1 000/5 000 деталей — 8 617 984/28 819 456/120 717 312 B peak RSS и примерно 0,0038/0,0318/0,1572 s. Наклон на крупных наборах около 22–23 KiB на деталь. Цена предлагаемого cap — повторный HH-запрос после вытеснения; цена TTL — риск выбрать неправильную свежесть. Ничего не внедрено без решения владельца.

В soak все шесть наблюдений имели ровно 5 открытых дескрипторов; текущий RSS внутри процесса рос не монотонно между независимыми запусками. Без Leaks trace это не доказательство ни утечки, ни ее отсутствия.

## 5. Процессорное время и отзывчивость

| Этап | До wall / CPU, медиана | После wall / CPU, медиана | Изменение wall / CPU | Размах wall до / после | Решение |
|---|---:|---:|---:|---:|---|
| archive 100 | 4,609 / 4,601 ms | 4,132 / 4,118 ms | −10,35% / −10,50% | 4,14% / 109,56% | не доказано: холодный выброс |
| archive 1 000 | 176,721 / 176,613 ms | 125,893 / 125,858 ms | −28,76% / −28,74% | 1,83% / 1,65% | принято |
| archive 5 000 | 6,0439 / 6,0427 s | 4,6859 / 4,6856 s | −22,47% / −22,46% | 2,60% / 2,60% | принято |
| search 1 000 | 2,491 ms | 2,523 ms | +1,29% | 1,08% / 2,81% | без регрессии >2% |
| PDF 10, paired warm | 409,0 / 127,878 ms | 407,2 / 128,018 ms | −0,45% / +0,11% | 6,38% / 4,47% | эквивалентно |
| PDF 100 | 1,2584 / 0,8361 s | 1,2798 / 0,8445 s | +1,70% / +1,00% | 0,83% / 1,24% | ниже 2% |
| PDF 500 | 5,1464 / 4,0648 s | 5,2208 / 4,0983 s | +1,44% / +0,82% | 2,59% / 0,58% | ниже 2% |
| stress 1×1 200 | 0,9446 / 0,6740 s | 0,9596 / 0,6800 s | +1,58% / +0,89% | 1,39% / 7,87% | шум |
| statistics 2 000 | 1,8665 / 1,8189 s | 1,8787 / 1,8274 s | +0,65% / +0,47% | 1,97% / 0,41% | эквивалентно |
| soak 500×6 | 3,0526 / 2,6605 s | 3,0570 / 2,6757 s | +0,15% / +0,57% | 2,58% / 7,55% | эквивалентно |

Archive fixture делает ровно N последовательных detail-вызовов, так что выигрыш относится к локальному этапу сопоставления ответа. Вместо повторного прохода по `favorites` строится карта O(n), но после каждого `await` индекс валидируется по текущему массиву. Новый параллелизм, detached processing или передача форматтеров между акторами не вводились.

Оставшаяся archive scaling 1 000→5 000 равна примерно ×37 по времени при ×5 данных. Возможная причина — поэлементные `@Published` mutations/COW и observability, но это предположение без allocation/time profile. Батч или перенос с main actor изменил бы наблюдаемое поведение/изоляцию, поэтому остановлен.

Heartbeat после: PDF 10/100/500 и stress держали maximum gap около 12,6–12,7 ms. Soak median maximum gap 281 ms включает намеренную синхронную PDFKit extraction/`ps` диагностику harness и не является временем SwiftUI frame. XCTest SDK render metric: wall 2,095044 s, CPU 2,095563 s, peak physical 39 569 KiB; размах wall 1,26%, peak 0,75%.

## 6. Швы

| Свойство | Было | Стало | Проверка / ограничение |
|---|---|---|---|
| Archive после `await` | корректный линейный поиск текущего массива | проверяемый cached index, rebuild при stale | `testArchiveCheckRevalidatesFavoriteIndexAfterRemovalDuringRequest`; текущий favorite удаляется во время suspended request |
| Archive cancellation | завершенные обновления сохранялись, оставшиеся не запрашивались | без изменений | cancellation/task-cancellation tests и финальный suite |
| PDF progress | snapshot до первого `await`, callback на main actor | production без изменений; тест усилен | 101/101, знаменатель всегда 101, неубывание, финал ровно один раз |
| PDF cancellation/publication | prepared data освобождаются; stage/backup/rollback не оставляет частичный final | без изменений | middle/last-page cancellation, staged validation, publication failure, retry tests |
| Snapshot фильтров/избранного | frozen value snapshot | без изменений | существующие mutation-during-export tests |
| Recovery | backup/recovery directory и terminal recovery error | без изменений | interrupted publication/rollback/collision tests; ручной UX — вопрос владельцу |
| PDF semantic determinism | одинаковые данные, страницы и текст | без изменений | baseline/after: 3 страницы, 40 428 B, text SHA-256 `24d3e7fdcb38b3d164873f8b0fb0c85a674d7055ca5f3141f705fd5c450c0fe0` |
| PDF byte determinism | отсутствует injection Quartz CreationDate/ModDate/document ID | не достигнуто | SHA-256 файлов различен; менять metadata означает контракт формата PDF |
| Ошибка сети/диска/прав на экране | используются `errorMessage`, `favoritesWarning`, PDF message; не единый typed UI state | без изменений | статусная строка по явному контракту показывает только `Показано вакансий: N`; новый structured surface требует решения владельца |

PDF визуально отрендерен Poppler по всем трем страницам: A4, текст читается, clipping не обнаружен. Первичное впечатление о наложении строк на уменьшенном thumbnail было ложным; координаты PDF и просмотр исходного разрешения подтвердили раздельные строки. Формат, локаль, порядок и разбиение production PDF не менялись.

## 7. Размер приложения

| Составляющая Release app | До | После | Изменение |
|---|---:|---:|---:|
| Сумма logical file bytes | 2 339 350 | 2 340 518 | +1 168 B (+0,050%) |
| `Contents/MacOS/СберВакансии` | 2 229 952 | 2 231 120 | +1 168 B (+0,052%) |
| `Assets.car` | 87 752 | 87 752 | 0 |
| `AppIcon.icns` | 14 243 | 14 243 | 0 |
| `employers.json` | 2 931 | 2 931 | 0 |
| `_CodeSignature/CodeResources` | 2 906 | 2 906 | 0 |
| `Info.plist` / `PkgInfo` | 1 558 / 8 | 1 558 / 8 | 0 |
| Disk usage | 2 300 KiB | 2 300 KiB | 0 |

Пять cold Release `build analyze`: до 14,63 s median, 14,58–17,67 s (21,12%); после 14,87 s, 14,71–16,59 s (12,64%), +1,64%. Все build/analyze завершились кодом 0 без analyzer diagnostics. Рост executable — цена двух коротких helpers и словаря, 0,05% приложения; он меньше порога и не оправдывает возврат ускорения 22–29%.

Ресурсы не удалялись: это область cleanup. Build settings, symbol stripping и WMO не менялись по запрету. dSYM находится вне `.app`; предложение менять настройки без отдельного решения и измерения отсутствует.

## 8. Отклоненные оптимизации

| Кандидат | Возможный выигрыш | Почему отклонен |
|---|---|---|
| Streaming PDF вместо `preparedParts` | уменьшить удержание 1,37 MB итоговых buffers и часть 60–64 MB RSS | Allocations недоступен; риск изменить validation/staging/rollback и получить partial final выше выигрыша |
| Cap 1 000 + TTL 30 min для details cache | ограничить fixture peak примерно 29 MB вместо 121 MB на 5 000 | политика свежести/повторных HH-запросов — новый продуктовый контракт; нужен владелец |
| Батч archive mutations или перенос с main actor | убрать часть оставшихся 4,69 s на 5 000 | меняет промежуточную наблюдаемость и actor-isolation; профиль причины отсутствует |
| Параллельная проверка архивов/рендер | потенциально снизить wall time | нарушает детерминированный порядок, pacing и явный запрет нового параллелизма |
| Фиксация Quartz metadata/document ID | побайтово одинаковый PDF | меняет PDF metadata/формат; нет существующего injection-шва |
| Вывести structured errors в статусную строку | единое место диагностики | конфликтует с подтвержденным UI-контрактом `Показано вакансий: N`; нужен отдельный совместимый surface |
| Удаление assets/смена strip settings | максимум 104 926 B известных ресурсов без executable | ресурсы — cleanup, настройки запрещены; доказанного мусора нет |
| Микроправки PDF/search/gate | единицы процентов или микросекунды | ниже разрешения либо шире размаха, цена читаемости не оправдана |

Отдельно отклонены ошибочные измерения из раздела 2. Они не являются performance regression и не подменяют повторные корректные пять прогонов.

## 9. Сводка

| Показатель | До: медиана (размах) | После: медиана (размах) | Δ | Итог |
|---|---:|---:|---:|---|
| Archive wall 1 000 | 176,721 ms (1,83%) | 125,893 ms (1,65%) | −28,76% | доказано |
| Archive CPU 1 000 | 176,613 ms (1,67%) | 125,858 ms (1,56%) | −28,74% | доказано |
| Archive wall 5 000 | 6,0439 s (2,60%) | 4,6859 s (2,60%) | −22,47% | доказано |
| Archive CPU 5 000 | 6,0427 s (2,59%) | 4,6856 s (2,46%) | −22,46% | доказано |
| Archive RSS 1 000 / 5 000 | 25,17 / 145,31 MB | 24,46 / 138,35 MB | −2,80% / −4,79% | неразличимо |
| Search 1 000 | 2,491 ms (1,08%) | 2,523 ms (2,81%) | +1,29% | эквивалентно; 10 запросов |
| PDF 10 paired wall | 409,0 ms (6,38%) | 407,2 ms (4,47%) | −0,45% | эквивалентно |
| PDF 100 wall / CPU | 1,2584 / 0,8361 s | 1,2798 / 0,8445 s | +1,70% / +1,00% | ниже 2% |
| PDF 500 wall / CPU | 5,1464 / 4,0648 s | 5,2208 / 4,0983 s | +1,44% / +0,82% | ниже 2% |
| Stress wall / CPU | 0,9446 / 0,6740 s | 0,9596 / 0,6800 s | +1,58% / +0,89% | ниже 2%; after spread 7,87% |
| Statistics wall / CPU | 1,8665 / 1,8189 s | 1,8787 / 1,8274 s | +0,65% / +0,47% | эквивалентно |
| Soak wall / CPU | 3,0526 / 2,6605 s | 3,0570 / 2,6757 s | +0,15% / +0,57% | эквивалентно; 5 FD ×6 |
| Gate queued cancellation | 0,0348 ms (218,9%) | 0,0522 ms (50,5%) | +0,0174 ms | ниже 0,1 ms; untouched path |
| Enrichment cancel/repeat | 1 request/0 export; 100 requests/2 exports | те же точные counts | 0 | контракт неизменен |
| Release cold build/analyze | 14,63 s (21,12%) | 14,87 s (12,64%) | +1,64% | ниже 2% |
| App logical/executable | 2 339 350 / 2 229 952 B | 2 340 518 / 2 231 120 B | +0,050% / +0,052% | оплачено алгоритмикой |
| PDF 100 semantic | 3 pages / 40 428 B / text hash | то же | 0 | совпало |
| XCTest render metric | — | 2,0950 s wall; 2,0956 s CPU; 39 569 KiB peak | baseline нет | измерительный потолок |

Суммарный доказанный эффект ограничен archive-проверкой: минус около 51 ms на 1 000 и 1,36 s на 5 000 локальных fixture-записей при прежнем числе запросов и одном сохранении. Память, PDF rendering, search, startup и размер приложения не улучшены. Не достигнуты: bounded details cache, непостоянная память PDF, byte-identical metadata и Instruments attribution.

## 10. Проверка на регрессию

Функциональных регрессий не найдено: полный xcresult `succeeded`, PDF pages/text/size совпали, archive order/cancellation/persistence тесты повторены. Запросов стало ровно столько же: archive N, search 10, enrichment contract counts неизменны.

Измерения больше 2%, не вызвавшие откат:

- PDF RSS +2,92%/+4,61% и stress RSS +3,17% меньше соответствующего объединенного размаха 16,78%/6,39%/22,90%; archive-код не участвует в PDF path, поэтому это шум, а не доказанная регрессия.
- Gate +50% — рост всего 0,0174 ms при baseline-размахе 218,9%; путь не менялся, абсолютная отмена осталась меньше 0,1 ms.
- Enrichment-limit wall изменялся на десятки микросекунд при одном request и нуле export; ниже разрешения короткого процесса.
- Полный Debug testing вырос с 145,169 до 155,074 s (+6,82%): XCUITest на macOS, при этом 96 tests успешны, 2 штатно пропущены и падений нет; production archive unit path занимает миллисекунды. Отдельный unit testing — 11,532 s против прежних 10,926 s, но добавлены два test cases и один пятиитерационный тест по умолчанию делает быстрый skip.
- App увеличился на 1 168 B (+0,05%), что явно оплачено индексной картой и намного ниже порога.

PDF byte SHA-256 различается (`1b77f6…` baseline и `e81b8a…` after), потому что Quartz записал разные wall-clock CreationDate/ModDate и document ID. Producer, PDF 1.3, A4, отсутствие encryption/forms/JavaScript, размер, страницы и нормализованный текст совпали. Пункт приемки metadata при закрепленных значениях не подтвержден и требует контрактной правки, поэтому итог содержит оговорку.

## 11. Тесты

| Тест / файл | Цель | Чем падал до | Финал и время |
|---|---|---|---|
| `testArchiveCheckRevalidatesFavoriteIndexAfterRemovalDuringRequest`, `HHVacancySberTests.swift:712` | реальная reentrancy: удалить первый favorite во время suspended archive request, обновить второй и сохранить точный snapshot | не падал: это invariant guard для performance rewrite, не reliability fix | Success, 0,109 s; до и после production-правки зеленый |
| усиленный `testFavoritePDFExportProducesBoundedValidPartsAndMainActorProgress`, `:1023` | фиксированный denominator 101, monotonic progress, final ровно один раз, 100+1 pages | существующий тест был зеленым; новые assertions проверяют ранее незафиксированный шов без production-правки | Success, 1,105 s |
| `testOptInPDFRenderingMetrics`, `:1746` | SDK wall/CPU/memory на prebuilt long pages, ровно 5 итераций | измерительный тест, red phase неприменим | явный run Success, 14,296 s; default Skip 0,0007 s |
| `RuntimeBenchmarks` search/archive modes | офлайн collector и scaling archive с exact counts | новые измерительные режимы, не обязательные tests | `swiftc -O` и все пятисерийные прогоны Success |

Явный opt-in запуск:

```sh
HH_RUN_PERFORMANCE_TESTS=1 xcodebuild -quiet -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/HHVacancySber-opt3-metrics test -only-testing:HHVacancySberTests/HHVacancySberTests/testOptInPDFRenderingMetrics
```

Пять измерений wall: 2,112310 / 2,089487 / 2,108792 / 2,095044 / 2,085878 s; CPU: 2,111659 / 2,089681 / 2,109166 / 2,095563 / 2,085965 s; peak physical: 39 815 / 39 733 / 39 569 / 39 520 / 39 520 KiB. Он не включен в обязательный performance gate и имеет большой запас — измеряет, а не навязывает хрупкий ceiling.

До текущего задания было 85 unit + 11 UI = 96 tests и один live skip. После добавлены два unit cases: 87 unit + 11 UI = 98, штатные skips — live HH и opt-in metric. Reliability-кандидаты без воспроизводимого red test, live-сеть, sleep-retry и новые зависимости отклонены.

## 12. Отложено

- **Владельцу — session cache:** согласовать cap (измеренный ориентир 1 000) и TTL (кандидат 30 min), допустимость повторных HH-запросов и UX устаревших деталей.
- **Владельцу — HH snapshot:** фоновые детали не могут быть атомарным снимком внешнего HH без версии/etag или изменения API-контракта; локальный export snapshot уже фиксирован.
- **Владельцу — recovery:** автоматический rollback тестируется; подтвердить, достаточно ли текстового пути recovery directory и ручной процедуры либо нужен отдельный экран/команда.
- **Владельцу — structured errors:** status line обязана оставаться `Показано вакансий: N`; для единого typed error нужен новый совместимый UI-шов.
- **Владельцу — byte determinism:** решить, разрешено ли задавать PDF CreationDate/ModDate/document ID; сейчас semantic determinism есть, byte determinism нет.
- **Рефакторинг:** профиль оставшейся archive observability/COW стоимости и потенциальный batch только после решения об изменении промежуточного UI поведения.
- **Оптимизация:** allocation/leak/App Launch traces после предоставления Instruments authorization; устанавливать инструмент не требуется и не предлагалось.
- **Cleanup:** доказать неиспользуемые assets отдельно; app bundle сейчас лишь 2,34 MB.
- **Невоспроизводимые риски без сети/реального FS:** timeout/обрыв/варианты HH ответа, настоящий disk-full и permission revocation отмечены, но production load/live test запрещены.

## 13. Проверки

| Команда / проверка | До | После | Код, число, время |
|---|---|---|---|
| Debug `test -only-testing:HHVacancySberTests build analyze` | 85 total / 1 skip / 0 fail | 87 / 2 / 0 | 0; testing 11,532 s; analyzer без diagnostics |
| Полный Debug `test` | 96 / 1 / 0 | 98 / 2 / 0 | 0; xcresult `succeeded`; testing 155,074 s |
| Целевые archive tests | старый алгоритм + invariant green | новый алгоритм: revalidation/cancel/not-found green | 0; трехтестовый action 1,452 s |
| Opt-in XCTMetric | отсутствовал | 1 test, 5 iterations | 0; test 14,296 s, action 15,988 s |
| Release `build analyze`, fresh derived | 5/5 | 5/5 | 0 у каждой сборки; medians 14,63/14,87 s |
| Python unittest | 72 OK | 72 OK | 0; 18,525 s после |
| Benchmark compile `swiftc -O` | baseline binary | after binary | 0 / 0 |
| `/usr/bin/time -lp` matrix | ≥5 на режим | ≥5 на режим | 0 у принятых прогонов; ошибочные отбракованы |
| PDFKit/Poppler fixture 100 | 3 pages, 40 428 B | 3 pages, 40 428 B | text hash совпал; metadata bytes — нет |
| Instruments Allocations/Leaks | template доступен | trace не записан | `[НЕ ВЫПОЛНЕНО]`: authorization |
| First frame | нет signpost/trace | не измерено | `[НЕ ВЫПОЛНЕНО]`: authorization и нет безопасного шва |
| `git diff --check`; отчет через `git diff --no-index --check /dev/null` | пусто | whitespace diagnostics отсутствуют | 0 для tracked; ожидаемый 1 у no-index означает наличие нового файла |

Точные финальные Xcode-команды использовали project `HHVacancySber/HHVacancySber.xcodeproj`, scheme `HHVacancySber`, `platform=macOS,arch=arm64` и отдельные каталоги `/private/tmp/HHVacancySber-opt3-final-*`. `release.sh`, DMG, publish и live HH не запускались.

## 14. Git

Исходный `git status --short`:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M REFACTOR_REPORT_2026-09-04.md
```

Собственные изменения этого задания:

- `VacancySearchViewModel.swift`: проверяемая индексная карта для archive lookup; файл был чист на входе.
- `RuntimeBenchmarks.swift` и `scripts/benchmarks/README.md`: offline search/archive modes и требование пяти прогонов; оба файла были чисты на входе.
- `HHVacancySberTests.swift`: один reentrancy invariant, один opt-in XCTMetric и усиление progress assertions; существующий пользовательский diff того же файла сохранен.
- `OPTIMIZATION_REPORT_2026-09-05.md`: новый отчет; прежний `OPTIMIZATION_REPORT.md` не перезаписан.

Пользовательскими и нетронутыми по смыслу остаются изменения PDF typography, SwiftUI/status presentation, UI tests и `REFACTOR_REPORT_2026-09-04.md`; они не откатывались и не приписываются optimization. Перед записью отчета общий working diff был 8 файлов, 314 добавлений и 282 удаления; SHA-256 `862c17907ed5669560695d1f338204ca6dabf809ddec26bcb58478e8da0b93df`.

Staged diff отсутствует. Не выполнялись `git add`, commit, push, fetch, stash, reset, checkout/restore, clean, branch/history operations. Финальный status и stat после добавления этого отчета приведены проверкой ниже; отчет остается untracked по запрету staging.

Финальный `git status --short`:

```text
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M REFACTOR_REPORT_2026-09-04.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? OPTIMIZATION_REPORT_2026-09-05.md
```

Финальный tracked `git diff --stat`: 8 файлов, 314 добавлений, 282 удаления. Новый отчет: 254 строки до этой финальной вставки, 37 221 B; он не входит в tracked stat. `git diff --cached --stat` пуст.

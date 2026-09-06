## 1. Итог

- По подтверждённому решению владельца добавлены максимум два повтора HTTP 429 с Retry-After и паузами; 403 не повторяется. Живые тесты сохраняют прежний бюджет: повторы в них отключены.
- Автоматический экспорт избранного сохраняет занятые имена и создаёт `_2`, `_3` и далее. Исправлен доказанный тестом выход за байтовый бюджет имени при Unicode-нормализации macOS.
- Проверки: 116 модульных тестов (6 штатных пропусков), 13 UI, отдельный пятиитерационный XCTMetric и 72 Python — успешно; Debug и все 10 Release build/analyze — код 0.
- Production-ускорение и снижение памяти не заявляются. Новые изменения относятся к согласованному поведению и надёжности; рисковые оптимизации отклонены.
- Приемка с оговорками: фиксированные метаданные и побайтовая повторяемость PDF не достигнуты; Instruments не получил авторизацию; реальный disk-full, энергия, первый кадр и CI текущего dirty tree не подтверждены.
- Пользовательские изменения сохранены. Живых запросов, staging, commit, push и операций с историей — ноль.

## 2. Процедура замера

Рабочая копия: /Users/mygga/Documents/ChatGPT/СберВакансии 2, HEAD 6e76afdfc7086a598c029ed132eacf9b814d8bfe.
Начальное дерево: 15 modified + 7 untracked файлов. Источники прочитаны: README, проект/схема/CI, API testing,
OPTIMIZATION_REPORT.md, отчёт 05.09, scripts/benchmarks и ~/Downloads/MAINTENANCE_REFACTOR_REPORT.md.
Прежние числа относятся к другим деревьям и не заменяют новые измерения.
Среда: Xcode 15.2 / Swift 5.9.2, arm64 macOS 13.7.8; настройки не менялись.

Runtime harness собран штатным build.sh в -O вместе с текущими production sources; сеть заменена actor-fixture.
Каждый сценарий использует UUID-каталог хранения/экспорта и удаляет только свои synthetic-файлы при штатном завершении.
На каждую версию: один первый процесс отдельно и пять повторных процессов; медианы ниже относятся к пяти повторам.
Это первые/повторные процессы, а не гарантированный холодный кеш ОС: системные кеши не очищались.
До каждого timed-процесса проверено отсутствие xcodebuild, swiftc, swift-frontend, clang, xctrace, Instruments.
Нет параллельных сборок/тестов/замеров. Проверка процессов исключает конкурирующие сборки, но не всю фоновую работу ОС.
Права одинаковые вне sandbox, включая font registry и ps.
Порог различимости — max(5%, полный размах/медиана до и после). Меньший эффект не объявляется выигрышем.

Инструменты: /usr/bin/time -l, getrusage, PDFKit; существующий opt-in XCTest использует XCTClockMetric/XCTCPUMetric/XCTMemoryMetric.
Итоговый RSS включает исходные модели и runtime. Создание values происходит до внутреннего таймера harness,
но внутри process time/RSS. Fixture также создаёт модели во время mock calls, поэтому это не изолированное время коллектора/сети.
Heartbeat включает накладные расходы PDFKit и ps; не является временем кадра SwiftUI.

Пять чистых Release-сборок каждой версии. Первую baseline-сборку сделали до правок; ещё четыре — из отдельной копии,
где исходные production-файлы восстановлены и проверены по начальному SHA-256. Тестовые файлы этой копии не являются
исходным baseline; Release build/analyze не запускает их. Смена пути копии дала разницу bundle 112 B,
поэтому побайтовый размер сравнивается с первой сборкой из настоящего рабочего пути.
Серия после сообщения «Продолжай» возобновлена с первого незавершённого прогона; завершённые сборки не перезаписывались.

| Первый процесс, сценарий | До, с | После, с |
|---|---:|---:|
| pdf 10 | 0.476674 | 0.551668 |
| pdf 100 | 1.268401 | 1.343798 |
| pdf 500 | 5.171402 | 5.380667 |
| search 1000 | 0.381186 | 0.398336 |
| archive 1000 | 2.383883 | 2.546388 |
| archive 5000 | 17.284955 | 17.111484 |
| enrichment-repeat 1000 | 11.340552 | 11.376560 |
| gate 100 | 0.541829 | 0.534457 |

Все JSON, time, логи и экспериментальные PDF: /private/tmp/HHVacancySber-perf-20260906.

## 3. Надежность и бережность к hh.ru

**Подтверждённый контрактный разрыв.** HHAPIClient раньше завершал 429 без повторов, что закрепляли документация
и testAPIDoesNotRetryHTTPOrTransportFailures. Владелец отдельно разрешил до двух повторов только для 429.
Красный testRateLimitRetriesTwiceThenReturnsSuccessfulResponse: вместо трёх запросов — один, успешный ответ не получен.
Минимальная правка в HHAPIClient: цикл внутри существующего serial gate, максимум три URLSession-попытки всего;
никакого параллелизма, прежние параметры запроса и авторизация сохранены.

Retry-After принимает секунды или HTTP-date; fallback — 1 и 2 секунды. Каждая пауза не меньше указанной сервером.
Если сервер просит больше 60 секунд, операция завершается ошибкой без раннего повтора. Это продуктовый потолок
автоматического ожидания (до 120 секунд на две паузы), а не объявленный лимит HH. Число повторов зажато в 0…2.
При 401/403/CAPTCHA/других HTTP и transport errors повторов нет. Во время паузы gate удерживается;
конкурентная операция не обгоняет повтор. Реальная отмена Task прерывает сон и освобождает gate.
После окончательной ошибки archive cycle останавливается существующим кодом ViewModel.
Общая блокировка всей сессии после завершения операции не вводилась: остальные действия могут снова обратиться к клиенту.

Подтверждение: тесты потолка, disabled live budget, HTTP-date, превышения 60 секунд, malformed header, backoff,
отмены и очереди. Старый запрет повторов сохранён для остальных ошибок; исключение 429 изменено по решению владельца.
Цена: до двух дополнительных read-only попыток после 429 и их ожидание. Ускорением это не считается.

**Имена PDF.** Красный тест коллизии: экспорт отменялся вместо записи нового файла. Новый план выбирает отсутствующий
путь и публикует через существующую транзакцию с expectedState absent. Позднее появление файла вызывает отказ/откат,
а не замену. Перебор ограничен 10000 кандидатами на имя; это защитный потолок файловых проверок, с явной ошибкой
«Выберите другой каталог». Предел проверяется тем же швом на двух занятых именах, без создания 10000 файлов.

**Unicode.** Новый тест длинного имени упал: URL macOS мог представить «ё» в разложенной форме, превышающей 240 B.
Подсчёт теперь резервирует максимум байтов для NFC/NFD каждого символа. Санация/суффикс/порядок имени остаются в PDFFileNameBuilder.

Журнал живых запросов: **0**. Ни одна live-группа не включалась; каждый её клиент теперь явно задаёт maximumRateLimitRetries: 0.
Токен не выводился и не логировался; новые ошибки не включают заголовки или тела запросов.


| Класс | Файл и строка | Поведение / доказательство |
|---|---|---|
| Доказанный дефект | `FavoriteVacanciesPDFExporter.swift:123` | Бюджет NFC/NFD; новый красный тест на URL, затем зелёный. |
| Согласованное изменение контракта | `HHAPIClient.swift:174` | Ограниченные повторы 429; старое поведение подтверждено красным тестом. |
| Защитный механизм | `FavoriteVacancyStore.swift:210` | Атомарная запись JSON; формат и драйвер сохранены. |
| Защитный механизм | `FavoriteVacanciesPDFExporter.swift:1845` | Публикация с backup/rollback; новый план не разрешает замену занятого имени. |
| Предположение о причине RSS | `FavoriteVacanciesPDFExporter.swift:1670` | Итоговые Data удерживаются; доля общего RSS без Instruments не определена. |
| Открытая политика | `VacancySearchViewModel.swift:58` | Нет TTL/cap; предложение без внедрения. |
| Подтверждённая фоновая задача | `ContentView.swift:11` | Таймер 1800 с; энергетическая стоимость не измерена. |
| Защитный механизм отмены | `VacancySearchViewModel.swift:365` | Успешные статусы сохраняются после остановки цикла; тесты Task cancellation. |

## 4. Ресурсы и нагрузка на машину

| Сценарий | RSS до, B | RSS после, B | Δ | Размах до / после | CPU до / после, с | Δ CPU |
|---|---:|---:|---:|---|---|---:|
| pdf 10 | 31653888 | 33112064 | +4.61% | 13.82% / 0.89% | 0.175501 / 0.182658 | +4.08% |
| pdf 100 | 42893312 | 44384256 | +3.48% | 15.55% / 5.57% | 0.894646 / 0.937727 | +4.82% |
| pdf 500 | 115982336 | 115490816 | -0.42% | 7.67% / 7.09% | 4.156069 / 4.313920 | +3.80% |
| search 1000 | 138395648 | 138395648 | +0.00% | 1.31% / 0.90% | 0.428360 / 0.453742 | +5.93% |
| archive 1000 | 145965056 | 157433856 | +7.86% | 6.78% / 2.66% | 2.421826 / 2.624759 | +8.38% |
| archive 5000 | 730955776 | 720109568 | -1.48% | 5.09% / 7.06% | 17.090797 / 17.256380 | +0.97% |
| enrichment-repeat 1000 | 290340864 | 306135040 | +5.44% | 5.89% / 10.98% | 11.443179 / 11.489381 | +0.40% |
| gate 100 | 20398080 | 20332544 | -0.32% | 0.88% / 2.18% | 0.006745 / 0.006738 | -0.10% |

Большой PDF удерживает preparedParts с итоговыми Data до публикации (PDFExportWorker). Общий RSS не доказывает,
что именно эти буферы объясняют весь рост: в него входят fixture, модели, шрифты, layout и PDFKit.
Instruments Allocations попытался записать офлайн PDF 500, но вернул Failed to gain authorization, exit 2.
[НЕ ВЫПОЛНЕНО]: attribution аллокаций, доказательство утечек/их отсутствия и энергия. Повторять тот же отказ Leaks бессмысленно.
Streaming rewrite отклонён: нет измеренной доли буферов, а изменение staging/rollback повышает риск.

Session detailsCache остаётся без TTL/cap. Предложение для отдельного решения: cap 1000 деталей и TTL 30 минут
как начальная гипотеза из прошлых замеров; свежесть и цена дополнительных HH-запросов требуют согласования.
В этой работе новые пределы кеша не вводились, отдельная кривая cache-only на текущем дереве не снята.

Простой: ContentView содержит autoconnect Timer раз в 1800 секунд и запуск проверки при активации окна.
Сам таймер не отключается при пустом избранном. Это статически подтверждённый механизм, не измерение idle CPU.
[НЕ ВЫПОЛНЕНО]: реальные wakeups, перерисовки и энергия в простое. Отсутствие фоновой нагрузки не заявляется.

## 5. Скорость и отзывчивость

| Сценарий | До, с | После, с | Δ | Размах до / после | Граница, % |
|---|---:|---:|---:|---|---:|
| pdf 10 | 0.399689 | 0.413442 | +3.44% | 3.93% / 10.89% | 10.89% |
| pdf 100 | 1.262270 | 1.347721 | +6.77% | 1.08% / 2.96% | 5.00% |
| pdf 500 | 5.176626 | 5.427443 | +4.85% | 0.40% / 2.90% | 5.00% |
| search 1000 | 0.382771 | 0.401444 | +4.88% | 4.49% / 3.74% | 5.00% |
| archive 1000 | 2.388179 | 2.591814 | +8.53% | 1.95% / 4.58% | 5.00% |
| archive 5000 | 16.927049 | 17.098289 | +1.01% | 4.22% / 2.79% | 5.00% |
| enrichment-repeat 1000 | 11.383979 | 11.437179 | +0.47% | 0.75% / 4.47% | 5.00% |
| gate 100 | 0.536513 | 0.534767 | -0.33% | 6.09% / 4.07% | 6.09% |

Из-за ухудшения части показателей >2% выполнен дополнительный контроль: пять пар, чередование AB/BA
двух сохранённых бинарников, та же fixture и чистый каталог на процесс.

| Попарный контроль | До, с | После, с | Δ | Размах до / после |
|---|---:|---:|---:|---|
| pdf 100 | 1.286506 | 1.284812 | -0.13% | 6.03% / 4.43% |
| archive 1000 | 2.410892 | 2.385000 | -1.07% | 4.79% / 0.22% |

Ни последовательные, ни попарные показатели не используются для заявления ускорения. В этих сценариях
mock обходит HHAPIClient, а PDF harness вызывает worker напрямую с заранее заданными именами: новые retry/suffix
пути здесь не исполняются. Причинная связь наблюдаемых отклонений с правкой не доказана; runtime/порядок серий
и условия ОС остаются факторами. Это ограничение измерения, а не доказательство отсутствия замедления.
[НЕ ВЫПОЛНЕНО]: профиль долей этапов и время первого кадра. Без него новые переносы работы/оптимизации не внесены.


| Heartbeat PDF (proxy), вакансий | Медиана max gap до, мс | После, мс | Δ |
|---|---:|---:|---:|
| 10 | 12.601 | 12.604 | +0.03% |
| 100 | 12.621 | 12.604 | -0.14% |
| 500 | 31.776 | 33.159 | +4.35% |

Это задержка диагностического heartbeat, не доля CPU главного потока и не время кадра. Улучшение UI по этому proxy не заявляется.

## 6. Экспорт в PDF

Состав избранного фиксируется до первого await; worker выдаёт прогресс с фиксированным знаменателем.
Действующие тесты проверяют отмену на последней странице, повтор после отмены, 100+1 страниц, текст/порядок,
изменение избранного во время экспорта и отзывчивость с mock details. Они входят в финальный набор.
Транзакция, rollback, формат страниц, типографика, сериализация и изоляция акторов не переписывались.
Тест ручного recovery реально копирует сохранённый backup в recovered-copy.pdf, проверяет байты и PDFKit,
при этом файл другого writer остаётся нетронутым.

Автоматические имена избранного: читаемая дата/название набора/номер тома, затем суффикс при занятости.
Явный выбор личного или статистического PDF через системную save panel сохраняет прежнее подтверждение замены.
[НЕ ВЫПОЛНЕНО]: распространение автоматического суффикса на явно выбранные пользователем имена этих двух экспортов;
новый UX выбора и сообщение фактического пути в этом этапе не реализованы. Фильтры присутствуют в имени статистики,
но не в именах полного избранного, которое экспортируется целиком.

Владелец разрешил фиксированные метаданные, однако два независимых синтетических эксперимента на установленном SDK
не дали результата: CGContext проигнорировал CreationDate/ModDate; PDFKit после изменения documentAttributes
также записал текущие даты при dataRepresentation. Байты двух запусков различаются.
[НЕ ВЫПОЛНЕНО]: побайтовая детерминированность PDF при фиксированных метаданных. Production metadata не менялись.
Подмена байтов/трейлера PDF собственным непроверенным парсером отклонена; новые зависимости и инструменты не установлены.

PDFKit-сверка эталонной статистики (100 записей, фиксированные входные даты):
{"bytes_after": 40428, "bytes_before": 40428, "bytes_equal": true, "pages_after": 3, "pages_before": 3, "text_equal": true, "text_sha256": "39bedd774073ad4811fa3f24c4817cc773477e0e145d0e6ee1036a1faf8e055f"}

[НЕ ВЫПОЛНЕНО]: реальное заполнение диска/отзыв прав. Инъекция ошибок и сохранность исходных файлов проверены
существующими тестами; это не подмена реального ENOSPC. Единая структурированная UI-ошибка не вводилась.

## 7. Размер приложения

| Файл в app | До, B | После, B | Δ, B |
|---|---:|---:|---:|
| Contents/Info.plist | 1558 | 1558 | +0 |
| Contents/MacOS/СберВакансии | 2272432 | 2274736 | +2304 |
| Contents/PkgInfo | 8 | 8 | +0 |
| Contents/Resources/AppIcon.icns | 14243 | 14243 | +0 |
| Contents/Resources/Assets.car | 87752 | 87752 | +0 |
| Contents/Resources/employers.json | 17502 | 17502 | +0 |
| Contents/Resources/employers.legacy-44.json | 16503 | 16503 | +0 |
| Contents/Resources/employers.legacy-v1.json | 2931 | 2931 | +0 |
| Contents/_CodeSignature/CodeResources | 3414 | 3414 | +0 |

Итого: 2416343 → 2418647 B (+0.095%).
Чистые Release build/analyze: до median 15.02 с, min–max 14.78–30.69;
после 17.04 с, 15.15–29.04; Δ +13.45%.
Все 10 команд завершились кодом 0. Широкий разброс сборок не позволяет объявить точную цену компиляции новой логики.
Увеличение bundle — цена ограниченных повторов, планирования имён и их проверок; сокращение размера не заявляется.
Настройки stripping/WMO/dSYM, project.pbxproj, схема, CI и ресурсы не менялись.
Удалять иконки либо менять Release flags оснований не найдено; это отдельные задачи с риском совместимости.

## 8. Отклоненные оптимизации

- Streaming PDF без attribution: риск отката/публикации выше недоказанной экономии.
- TTL/cap без решения владельца: меняет свежесть и число запросов после вытеснения.
- Удаление периодической проверки: меняет обновление архивов, измеренного выигрыша нет.
- Параллельные запросы/рендер/записи: запрещены, не экспериментировались.
- Нормализация произвольных PDF regex/подмена trailer ID: риск повреждения данных, не внедрена.
- Микроправки классификаторов/форматтеров на основании общего времени fixture: нет профиля доли.
- Удаление ресурсов/смена настроек ради нескольких килобайт: вне подтверждённой задачи.

## 9. Сводка

Время/CPU/RSS до и после, проценты и размах — разделы 4–5. Размер/сборки — раздел 7.
Точные числа mock calls:

| Сценарий | До | После |
|---|---:|---:|
| pdf 10 | [20] | [20] |
| pdf 100 | [20] | [20] |
| pdf 500 | [20] | [20] |
| search 1000 | [10] | [10] |
| archive 1000 | [1000] | [1000] |
| archive 5000 | [5000] | [5000] |
| enrichment-repeat 1000 | [1000] | [1000] |

Mock counts не измеряют production RPS: fixture не проходит через общий gate.
Production-пауза между обычными операциями осталась 250 ms после завершения; concurrency 1.
Для сценария 429→429→200 попыток стало 1→3 по явному решению владельца; fallback-паузы проверены как 1/2 секунды.
Число файлов при коллизии стало 1→2 с сохранением исходного; после повторной коллизии выбирается следующий суффикс.
Idle/first frame/energy/полная детерминированность имеют явные ограничения выше.

## 10. Регрессия

Финальный Debug test/build/analyze, opt-in metrics и Python подтверждены логами раздела 13.
Ухудшения >2% в runtime оставлены видимыми; парный контроль выполнен, но оптимизационный выигрыш не принят.
Сборка медленнее по медиане при широком диапазоне, app больше примерно на 2,3 KB. Это принятая цена
согласованных защитных сценариев, а не экономия ресурсов. Код, вызываемый основными fixture, практически не затронут.
PDF страницы/текст сверены через PDFKit; в этой короткой паре совпали и байты. Это не доказывает стабильность между разными секундами: отдельные metadata-пробы с паузой 1,1 с различались. Пункт закреплённых метаданных не засчитан.

## 11. Тесты

Новые тесты (10): retry success, бюджет/60s, HTTP-date, backoff/disabled budget, реальная отмена,
очередь при retry, 403/CAPTCHA/защита потолка, сохранение файла с суффиксом,
занятые/повторные/Unicode-имена и потолок, отмена/поздняя коллизия.
Файл: HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift.
Красная фаза двух основных сценариев: red.log, exit 65, 2 теста/3 assertions, 0,279 с.
Дополнительный красный Unicode-сценарий: green-second.log, 114 тестов/1 failure; исправлен бюджет NFC/NFD.
Первый green выявил ошибку самого нового теста — сравнение URL вместо имени; она исправлена без ослабления
проверки байтов исходного файла, числа новых PDF и их читаемости.
Green-third: 114 тестов, 6 штатных skips, 0 failures; build/analyze успешны. Затем добавлены два теста очереди/terminal policy.
Оптимизационных потолков в обязательный suite не добавлялось. Opt-in metric выполняется отдельно пятью итерациями.

## 12. Отложено

- Детерминированная запись PDF: нужен подтверждённый способ в доступном SDK; разрешение владельца уже получено.
- Суффиксы для явно выбранных личного/статистического PDF и UI фактического пути; полный именующий контракт не завершён.
- Allocation/Leaks/Energy/App Launch после исправления системной авторизации Instruments; установка не выполнялась.
- Реальный disk-full/permission revocation и единый структурированный UI error.
- TTL/cap сессии, атомарность внешнего HH snapshot и общий session cooldown: отдельные продуктовые решения.
- Профиль оставшейся стоимости моделей/наблюдаемости; рефакторинг и очистка не смешивались с этим этапом.
- CI именно текущего dirty tree: commit/push запрещены заданием; CI старого PR очистки не засчитан.

## 13. Проверки

| Проверка | Исходное состояние | Финал | Время команды |
|---|---|---|---|
| Полный Debug test/build/analyze | 106 unit, 6 skips; 13 UI; SUCCEEDED | 116 unit, те же 6 skips; 13 UI; TEST/BUILD/ANALYZE SUCCEEDED, exit 0 | 205.19 → 217.15 с |
| Release build/analyze | 5/5 exit 0 | 5/5 exit 0 | медианы/размах в разделе 7 |
| Opt-in XCTMetric | был штатно пропущен | 1 test, 5 итераций, без skips/failures, exit 0 | 16.26 с; сам тест 14,181 с |
| Python | исторические результаты не засчитаны | 72 теста, OK, exit 0 | 18.65 с; сами тесты 18,305 с |
| git diff --check | успешно | успешно | — |
| bash -n build.sh/release.sh | скрипты сохранены | успешно; release.sh не запускался | — |
| Пользовательское содержимое | 63 SHA-256 | совпадение после отделения собственных правок | preservation.json |
| Живая сеть | выключена | 0 запросов | — |
| CI текущего dirty tree | не запускался | [НЕ ВЫПОЛНЕНО]: commit/push запрещены | старый CI не засчитан |

Финальные unit assertions заняли 11,442 с; исходные — 11,563 с. UI — 168,648 → 171,266 с (+1,55%).
Новые тесты повторены в финальной сборке:

| Тест | Время, с |
|---|---:|
| testFavoritePDFCollisionCreatesSuffixAndPreservesExistingFile | 0.047 |
| testPDFSuffixPlanHandlesOccupiedNamesDuplicatesAndUTF8Limit | 0.003 |
| testPDFSuffixSelectionCancellationAndLateCollisionPreserveExistingFile | 0.019 |
| testRateLimitDelaySupportsHTTPDateAndNeverRetriesBeforeServerDelay | 0.001 |
| testRateLimitRetriesTwiceThenReturnsSuccessfulResponse | 0.002 |
| testRateLimitRetryBudgetAndServerDelayCeiling | 0.005 |
| testRateLimitRetryStopsOnForbiddenCaptchaAndConfiguredCeiling | 0.004 |
| testRateLimitRetryUsesExpectedBackoffAndCanBeDisabledForLiveBudget | 0.002 |
| testRateLimitWaitCancellationStopsRetriesAndReleasesSharedGate | 0.103 |
| testRateLimitWaitPreventsQueuedRequestsFromOvertakingRetry | 0.109 |

SDK-метрики (единицы сохранены из XCTest; baseline для SDK отдельно не снимался):

| Метрика | Медиана | Min–max | Размах |
|---|---:|---|---:|
| Memory Physical, kB | -16.384000 | -311.296000–639.040000 | -5800.39% |
| CPU Cycles, kC | 6834342.321000 | 6825226.304000–6835823.784000 | 0.16% |
| Clock Monotonic Time, s | 2.083308 | 2.080833–2.091133 | 0.49% |
| CPU Time, s | 2.084048 | 2.081265–2.091821 | 0.51% |
| CPU Instructions Retired, kI | 35006400.187000 | 35003784.191000–35008790.985000 | 0.01% |
| Memory Peak Physical, kB | 32737.216000 | 32409.536000–33032.192000 | 1.90% |

Команды из HHVacancySber, project HHVacancySber.xcodeproj, scheme HHVacancySber,
destination platform=macOS,arch=arm64, derivedDataPath /private/tmp/HHVacancySber-perf-20260906/debug:
`xcodebuild ... -configuration Debug test build analyze` и отдельный
`TEST_RUNNER_HH_RUN_PERFORMANCE_TESTS=1 xcodebuild ... test -only-testing:HHVacancySberTests/HHVacancySberTests/testOptInPDFRenderingMetrics`.
Python из корня: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -q`.

Все 96 процессов основной матрицы (2 версии × 8 сценариев × 6) и 20 процессов попарного контроля завершились успешно.
Первые процессы исключены из пятиитерационных медиан; контрольные PDF — отдельная семантическая проверка.
Непринятый interpreter metadata-probe не слинковал PDFKit; повтор swiftc -framework PDFKit выполнен.
Comparator потребовал явный scratch module-cache — путь исправлен. Ошибки оснастки не засчитаны как успешные измерения.

## 14. Git

Собственные изменения: HHAPIClient.swift; точечные additions в пользовательском PDF exporter и XCTest;
README и API testing; этот новый отчёт. Предыдущий OPTIMIZATION_REPORT.md не перезаписан.
Верификация 63 исходных файлов: неизменённые совпали по SHA-256, для пяти изменённых собственные edits отделены
от исходного содержимого; реконструкция прежнего содержимого совпала с начальными hash.
Staging, commit, push, stash, reset, checkout, restore, clean, release/DMG и операции с историей не выполнялись.

Исходный status:

```text
 M HHVacancySber/HHVacancySber.xcodeproj/project.pbxproj
 M HHVacancySber/HHVacancySber/EmployerConfiguration.swift
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/HHVacancySberApp.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySber/employers.json
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
 M REFACTOR_REPORT_2026-09-04.md
 M docs/HEADHUNTER_API_TESTING.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? HHVacancySber/HHVacancySber/employers.legacy-44.json
?? HHVacancySber/HHVacancySber/employers.legacy-v1.json
?? LIVE_CANCELLATION_REPORT_2026-09-05.md
?? OPTIMIZATION_REPORT_2026-09-05.md
?? REFACTOR_REPORT_2026-09-05.md
?? docs/HH_API_CHECK_2026-09-05.md
?? docs/SBER_EMPLOYER_PERIMETER_2026-09-05.md
```

Текущий status перед записью отчёта:

```text
 M HHVacancySber/HHVacancySber.xcodeproj/project.pbxproj
 M HHVacancySber/HHVacancySber/EmployerConfiguration.swift
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHAPIClient.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/HHVacancySberApp.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySber/employers.json
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
 M REFACTOR_REPORT_2026-09-04.md
 M docs/HEADHUNTER_API_TESTING.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? HHVacancySber/HHVacancySber/employers.legacy-44.json
?? HHVacancySber/HHVacancySber/employers.legacy-v1.json
?? LIVE_CANCELLATION_REPORT_2026-09-05.md
?? OPTIMIZATION_REPORT_2026-09-05.md
?? REFACTOR_REPORT_2026-09-05.md
?? docs/HH_API_CHECK_2026-09-05.md
?? docs/SBER_EMPLOYER_PERIMETER_2026-09-05.md
```

Общий diff --stat (включает пользовательские изменения, не приписывается этому этапу):

```text
 .../HHVacancySber.xcodeproj/project.pbxproj        |   8 +
 .../HHVacancySber/EmployerConfiguration.swift      |  34 +-
 .../FavoriteVacanciesPDFExporter.swift             |  56 +-
 HHVacancySber/HHVacancySber/HHAPIClient.swift      |  64 +-
 HHVacancySber/HHVacancySber/HHModels.swift         | 151 ++++
 HHVacancySber/HHVacancySber/HHVacancySberApp.swift |  25 +-
 .../HHVacancySber/VacancySearchViewModel.swift     |  29 +-
 .../HHVacancySber/VacancySearchViews.swift         | 114 ++-
 HHVacancySber/HHVacancySber/employers.json         | 245 +++++-
 .../HHVacancySberTests/HHVacancySberTests.swift    | 920 ++++++++++++++++++++-
 .../HHVacancySberUITests.swift                     |  71 +-
 README.md                                          |  11 +-
 REFACTOR_REPORT_2026-09-04.md                      | 375 +++------
 docs/HEADHUNTER_API_TESTING.md                     |  58 +-
 scripts/benchmarks/README.md                       |   6 +-
 scripts/benchmarks/RuntimeBenchmarks.swift         |  57 +-
 16 files changed, 1862 insertions(+), 362 deletions(-)
```

Финальный status после добавления отчёта:

```text
 M HHVacancySber/HHVacancySber.xcodeproj/project.pbxproj
 M HHVacancySber/HHVacancySber/EmployerConfiguration.swift
 M HHVacancySber/HHVacancySber/FavoriteVacanciesPDFExporter.swift
 M HHVacancySber/HHVacancySber/HHAPIClient.swift
 M HHVacancySber/HHVacancySber/HHModels.swift
 M HHVacancySber/HHVacancySber/HHVacancySberApp.swift
 M HHVacancySber/HHVacancySber/VacancySearchViewModel.swift
 M HHVacancySber/HHVacancySber/VacancySearchViews.swift
 M HHVacancySber/HHVacancySber/employers.json
 M HHVacancySber/HHVacancySberTests/HHVacancySberTests.swift
 M HHVacancySber/HHVacancySberUITests/HHVacancySberUITests.swift
 M README.md
 M REFACTOR_REPORT_2026-09-04.md
 M docs/HEADHUNTER_API_TESTING.md
 M scripts/benchmarks/README.md
 M scripts/benchmarks/RuntimeBenchmarks.swift
?? HHVacancySber/HHVacancySber/employers.legacy-44.json
?? HHVacancySber/HHVacancySber/employers.legacy-v1.json
?? LIVE_CANCELLATION_REPORT_2026-09-05.md
?? OPTIMIZATION_REPORT_2026-09-05.md
?? OPTIMIZATION_REPORT_2026-09-06.md
?? REFACTOR_REPORT_2026-09-05.md
?? docs/HH_API_CHECK_2026-09-05.md
?? docs/SBER_EMPLOYER_PERIMETER_2026-09-05.md
```

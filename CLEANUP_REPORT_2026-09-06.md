# 1. Итог

Локально удалены 60 каталогов регенерируемых кешей: **28 476 файлов, 2424,43 МиБ (2,37 ГиБ)** по `du -sk` перед удалением.
Исходники, ресурсы, настройки, пользовательские данные и 63 первоначальных отслеживаемых/неотслеживаемых файла сохранены побайтово.
Результаты прежних проверок и продукты старых сборок оставлены: их историческую ценность нельзя заменить новой сборкой.

В облачную ветку `cleanup/2026-09-06` входит только этот отчет. Она создана от `origin/main`,
без трех локальных коммитов и незакоммиченных изменений основной рабочей копии.
Удалять ветки, теги, выпуски, PR или Actions artifacts оснований не найдено; необратимых облачных действий нет.

Финальная приемка еще выполняется. Это предварительный отчет; отсутствие результата не считается успешной проверкой.

## 2. Мера локально и в облаке с пояснением разницы

Удаленные кеши занимали 2,37 ГиБ. Это сумма выделенных блоков выбранных каталогов, а не обещание такого же изменения свободного места APFS: снапшоты, сжатие и параллельная работа ОС могут влиять на `df`.
Исходный `df -h`: 460 GiB всего, 282 GiB использовано, 138 GiB доступно.
Новые DerivedData для приемки и карантин частично занимают освобожденное место; итог приведен после завершения.

| Отслеживаемые файлы рабочего дерева | Файлов | Байтов | Переводов строки |
|---|---:|---:|---:|
| resources/other | 35 | 500957 | 6488 |
| .swift | 17 | 438405 | 8925 |
| .py | 4 | 145070 | 3336 |

В категории resources/other строки бинарных ресурсов не являются строками кода; это счетчик байта LF.
Отслеживаемое дерево до очистки: 56 файлов. Их содержимое не изменилось; добавляется только отчет в отдельной ветке.
Git до: 443 loose objects, 3,59 MiB, packs 0, garbage 0. Крупнейший blob — 174 033 байта, старая версия модульных тестов.
Метаданные GitHub до: size=117 (KiB по API), единственная ветка main; опубликованных и черновых выпусков, тегов, PR и artifacts нет.
Удаление локальных кешей не уменьшает Git-историю или GitHub: эти файлы туда не входили.

## 3. Реестр локальных кандидатов

Все нижеследующие кеши находились вне Git. Для Xcode принадлежность проекту доказана `WorkspacePath` в родительском info.plist.
В список удаления попали только ModuleCache.noindex, SDKStatCaches.noindex, Index.noindex, два module-cache бенчмарков и дерево, состоящее только из .pyc.
Перед удалением активные xcodebuild/swift-frontend/clang/sourcekit-lsp/XCBBuildService не обнаружены.
Поименный машинный реестр с командами восстановления — `deletion-plan.json`, подтверждение удаления — `deletion-receipt.json` в карантине.

| Абсолютный путь | МиБ до | Класс / действие |
|---|---:|---|
| `/private/tmp/HHVacancySber-build5-tests.xJot4a/DerivedData/ModuleCache.noindex` | 99.617 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-build5-tests.xJot4a/DerivedData/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-build5-tests.xJot4a/DerivedData/Index.noindex` | 24.344 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt-20260904.fGBGyH/release-1/ModuleCache.noindex` | 50.379 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt-20260904.fGBGyH/release-1/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-after/ModuleCache.noindex` | 99.605 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-after/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-after/Index.noindex` | 24.203 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-before/ModuleCache.noindex` | 99.605 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-before/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-archive-safety-before/Index.noindex` | 24.316 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-debug/ModuleCache.noindex` | 99.566 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-debug/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-debug/Index.noindex` | 24.465 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-1/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-1/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-2/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-2/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-3/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-3/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-4/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-4/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-5/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-release-5/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-unit/ModuleCache.noindex` | 99.566 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-unit/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-final-unit/Index.noindex` | 24.465 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-metrics/ModuleCache.noindex` | 99.562 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-metrics/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-metrics/Index.noindex` | 24.348 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-1.It9CIL/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-1.It9CIL/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-2.flyXLh/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-2.flyXLh/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-3.OCrHNS/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-3.OCrHNS/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-4.WN5XEW/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-4.WN5XEW/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-5.5y8R3f/ModuleCache.noindex` | 50.363 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-release-5.5y8R3f/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-refactor/ModuleCache.noindex` | 99.555 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-refactor/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-refactor/Index.noindex` | 25.852 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-refactor-release/ModuleCache.noindex` | 50.348 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-refactor-release/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-green/ModuleCache.noindex` | 99.570 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-green/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-green/Index.noindex` | 24.309 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-red/ModuleCache.noindex` | 99.566 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-red/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-red/Index.noindex` | 24.457 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-ui/ModuleCache.noindex` | 99.566 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-ui/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-status-label-ui/Index.noindex` | 24.480 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-teal/ModuleCache.noindex` | 175.320 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-teal/SDKStatCaches.noindex` | 12.141 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-teal/Index.noindex` | 25.961 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-after.izGWEv/module-cache` | 48.066 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3.8vxMU6/module-cache` | 48.066 | Регенерируемый кеш; удален |
| `/private/tmp/HHVacancySber-opt3-pycache` | 2.398 | Регенерируемый кеш; удален |

Восстановление кеша Xcode: из `HHVacancySber/` выполнить `xcodebuild -project HHVacancySber.xcodeproj -scheme HHVacancySber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath '<родитель кеша>' build`.
Измеренная холодная сборка с тестами до очистки — 32,85 с, Release build/analyze — 25,28 с; стоимость восстановления рабочего состояния меньше пяти минут.
Это восстанавливает кеш для текущих исходников, а не историю старого индекса.
Кеш бенчмарка восстанавливается `bash scripts/benchmarks/build.sh '<исходный путь>/benchmark'`; сам executable оставлен.
.pyc восстанавливается запуском `PYTHONPYCACHEPREFIX='<исходный путь>' python3 -m unittest discover -s scripts/tests -q`; исходные .py не затронуты.

Другие найденные каталоги/файлы и решение:

| Путь | МиБ до | Решение и доказательство |
|---|---:|---|
| `/private/tmp/HHVacancySber-build5-tests.xJot4a` | 767.109 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-live-cancellation-20260905` | 0.730 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-opt-20260904.fGBGyH` | 79.176 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-after.izGWEv` | 49.742 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-archive-safety-after` | 188.789 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-archive-safety-before` | 188.875 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-debug` | 191.867 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-release-1` | 78.945 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-release-2` | 78.945 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-release-3` | 78.945 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-release-4` | 78.945 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-release-5` | 78.945 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-final-unit` | 174.246 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-metrics` | 187.742 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-preview.m0T7Xd` | 0.914 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-opt3-pycache` | 2.398 | Удален целиком: все файлы .pyc |
| `/private/tmp/HHVacancySber-opt3-release-1.It9CIL` | 78.918 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-release-2.flyXLh` | 78.906 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-release-3.OCrHNS` | 78.906 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-release-4.WN5XEW` | 78.906 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-release-5.5y8R3f` | 78.906 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-opt3-trace.OgpHaW` | 0.590 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-opt3.8vxMU6` | 49.727 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-refactor` | 196.773 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-refactor-audit-20260905` | 4.703 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-refactor-release` | 79.109 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-security-build.log` | 0.277 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-security-preview` | 5.102 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-security-test.log` | 0.164 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-status-label-green` | 188.699 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-status-label-red` | 340.266 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-status-label-ui` | 371.656 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-teal` | 272.672 | Удалены только перечисленные выше кеши; Build/Products, Logs, TestResults и прочее сохранены |
| `/private/tmp/HHVacancySber-teal-build.log` | 0.246 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-teal-preview` | 4.680 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |
| `/private/tmp/HHVacancySber-teal-test.log` | 0.012 | Оставлен: результаты, снимки, логи, трассы или уникальные служебные материалы прежних задач |

В дереве не найдены .bak/.old/.orig, .pyc, .DS_Store, AppleDouble, swap, дампы .crash/.diag/.ips, случайные архивы или персональные схемы вне ignore.
Ignored output/ и OPTIMIZATION_REPORT.md оставлены как пользовательские артефакты.
Пустые `tmp/` и `project.xcworkspace/xcshareddata/swiftpm/configuration/` оставлены: первый неотслеживаемый, второй служебный каталог Xcode; экономии блоков от удаления нет.
В ~/Library/Developer/Xcode/DerivedData каталогов HHVacancySber-* не обнаружено. Другие проекты, ~/Library/Caches и Application Support не просматривались для удаления.

## 4. Реестр облачных кандидатов с признаком обратимости

| Класс | Проверка | Результат / обратимость |
|---|---|---|
| Слитые/заброшенные ветки | git branch -a, ls-remote, API branches | До очистки только main; удаление не предлагается |
| Теги и выпуски | git tag, gh release list, ls-remote | Отсутствуют; удаление не предлагается |
| PR | gh pr list --state all | Отсутствовали; новый PR только для отчета, обратимое добавление |
| Actions artifacts | API actions/artifacts | Отсутствуют; удаление не предлагается |
| Объекты истории | rev-list --objects --all + cat-file --batch-check | 20 крупнейших — исходники, тесты, отчеты и используемая иконка; переписывание не обосновано |

## 5. Удалено безвозвратно

Только 60 корней кешей, перечисленных в разделе 3, суммарно 28 476 файлов.
Использован заранее записанный список абсолютных путей, с проверкой владельца, отсутствия symlink и разрешенного имени каталога.
`rm` по маске, `find -delete`, `xargs rm`, Git cleanup/reset/restore/stash не выполнялись.
Кеши регенерируются, поэтому побайтовой резервной копии их устаревшего содержимого нет.

## 6. Карантин

Путь: `/Users/mygga/.hhvacancysber-cleanup/2026-09-05-1853`.

В `private/tmp/HHVacancySber-cleanup-records/` скопированы baseline-логи, времена, снимок SHA-256, опись и план; после приемки добавлены итоговые протоколы.
Оригинальные пути сохранены относительно `/`. RESTORE.txt объясняет восстановление без перезаписи более новых файлов.
Карантин не опустошался и автоматически опустошаться не будет; это действие владельца.
Уникальные резервные копии прежних задач не перемещались и не удалялись.

## 7. Мертвый код, ресурсы, остатки предка

Поиск Swift-деклараций private с подсчетом употреблений вне объявления внутри и вне файла не нашел имен с нулевыми употреблениями.
Просмотрены вызовы, тесты, навигация/модификаторы, схемы, build references, CI и README. Это не доказательство отсутствия любого мертвого кода; без полного доказательства удаления не выполнялись.
sourcekit-lsp установлен; отдельного семантического анализа всех ссылок через LSP не выполнялось. Удаления Swift нет, поэтому неполный текстовый анализ не использован как разрешение.
Поиск runtime-фрагментов scoring/score/скоринг/HHVacancyDesk не дал кандидатов. Защитные упоминания прежнего имени в CI нужны проверке и сохранены.
Все 10 слотов AppIcon существуют. Три пары PNG побайтово равны, но обслуживают разные размеры/scale в Contents.json; оба совпадающих Contents.json принадлежат разным используемым каталогам ассетов.
Python: render_icon связан с README/иконками; verify_release_entitlements вызывается release.sh; тестовые файлы входят в discover/CI. Доказанного мертвого Python нет.
Фикстуры бенчмарков, fatalError fail-fast, живые opt-in тесты, PDF recovery/транзакции, форматтеры с разными контрактами и снимки миграции работодателей сохранены.

## 8. Проект и конфигурации — предложения без выполнения

Три цели: HHVacancySber, HHVacancySberTests, HHVacancySberUITests; Debug/Release; одна общая схема HHVacancySber. До и после список совпадает.
Осиротевших ссылок, лишних конфигураций или фаз сборки не доказано; предложений на удаление нет.
Package.swift/Package.resolved, Podfile/Cartfile, внешних package references и lock-файлов не найдено.
project.pbxproj, схема, Info.plist, entitlements, параметры сборки, ci.yml, README/docs, release.sh и scripts/tests очисткой не изменялись.

## 9. Облако

Создан отдельный worktree от origin/main и ветка cleanup/2026-09-06. Коммиты касаются только отчета; push идет только в эту ветку.
Необратимых операций и команд на удаление для владельца нет: ни одного соответствующего кандидата не обнаружено.
Переписывание истории и резервный git bundle не требуются: крупного ненужного binary payload нет, а история и основные ветки не менялись.
Состояние после fetch --prune и ссылка на PR фиксируются ниже при завершении.

## 10. Оставлено намеренно

Все 15 предсуществующих модификаций и 7 неотслеживаемых файлов, ignored OPTIMIZATION_REPORT.md/output, снимки API,
PDF и UI, старые .xcresult и продукты сборок, уникальные резервные версии исходников, скрипты измерений и логи.
Дорогие или невоспроизводимые исторические артефакты не объявлены мусором лишь из-за их возраста.
Носитель встроенного токена не менялся; значение токена не выводилось и не включалось в отчет.

## 11. Отложено

Удаление оставшихся исторических Build/Products и результатов возможно только после определения владельцем,
какие прошлые проверки и версии больше не нужны. Без этого старую сборку нельзя считать замененной текущей.
Рефакторинг, оптимизация, исправления поведения и редактура документации не выполняются в задаче очистки.

## 12. Проверки

Baseline: Debug unit/test/build/analyze — успешно, 106 тестов, 6 пропусков; полный Debug — 13 UI без ошибок плюс тот же unit-набор;
Release build/analyze — успешно; Python — 72, OK; git diff --check, bash -n benchmarks/build.sh и release.sh — успешно.
В исходном задании числа 77/10/71 устарели; сравнение ведется с фактическим baseline 106/13/72 и 6 пропусками.
Живые HH-флаги не включались, запросов к HH в задаче нет.

| Проверка / полное время команды, с | До | После |
|---|---:|---:|
| Debug unit + build + analyze | 32.85 | [НЕ ВЫПОЛНЕНО] |
| Полный Debug test с UI | 193.24 | [НЕ ВЫПОЛНЕНО] |
| Release build + analyze | 25.28 | [НЕ ВЫПОЛНЕНО] |
| Python unittest | 18.73 | [НЕ ВЫПОЛНЕНО] |

Время — один запуск каждой команды, не статистическое доказательство ускорения. Сравниваются проверки корректности; скорость приложения не менялась.
FSEvents/диагностика отсутствующих Simulator services и XPC shutdown не выдаются за ошибку компиляции; успех подтвержден маркерами xcodebuild.
Внешний гейт — CI на macOS, его отдельный статус указан при завершении.

## 13. Пригодность почвы

После удаления кешей выполнен Debug build/analyze в новом /private/tmp/HHVacancySber-cleanup-verify — успешно.
Холодная сборка: 10.40 с.

Состав целей/схемы сохранен. CI и механизм выпуска не изменены; release.sh проверялся только bash -n, DMG/релиз не запускались.
Экспорт PDF и его тесты остаются частью неизмененного исходного дерева. Старые результаты доступны для расследований.

## 14. Git

Исходная ветка main: `6e76afdfc7086a598c029ed132eacf9b814d8bfe`.
origin/main: `389412131f2223dbb009dd3959ac15893be87b2f`.
Локальная main опережала origin/main на три коммита; эти коммиты не включены в PR очистки.
Baseline и финальные локальные проверки относятся к исходному рабочему дереву с пользовательскими изменениями;
PR меняет только отчет относительно облачной main и не переносит локальную функциональность в облако.

Начальный status (тот же для первоначальных файлов после очистки):

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

Начальный diff --stat (не является diff очистки):

```text
 .../HHVacancySber.xcodeproj/project.pbxproj        |   8 +
 .../HHVacancySber/EmployerConfiguration.swift      |  34 +-
 .../FavoriteVacanciesPDFExporter.swift             |  10 +-
 HHVacancySber/HHVacancySber/HHModels.swift         | 151 +++++
 HHVacancySber/HHVacancySber/HHVacancySberApp.swift |  25 +-
 .../HHVacancySber/VacancySearchViewModel.swift     |  29 +-
 .../HHVacancySber/VacancySearchViews.swift         | 114 +++-
 HHVacancySber/HHVacancySber/employers.json         | 245 +++++--
 .../HHVacancySberTests/HHVacancySberTests.swift    | 707 ++++++++++++++++++++-
 .../HHVacancySberUITests.swift                     |  71 ++-
 README.md                                          |   9 +-
 REFACTOR_REPORT_2026-09-04.md                      | 375 ++++-------
 docs/HEADHUNTER_API_TESTING.md                     |  54 +-
 scripts/benchmarks/README.md                       |   6 +-
 scripts/benchmarks/RuntimeBenchmarks.swift         |  57 +-
 15 files changed, 1555 insertions(+), 340 deletions(-)
```

Нет commit/push в main, принудительной отправки, операций с тегами/историей или отмены пользовательских правок.

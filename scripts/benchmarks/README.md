# Локальные runtime-проверки

Этот harness компилируется с production Swift-кодом в `-O`. HH заменён actor-fixture: ни один режим не обращается к сети. Не запускайте production load test.

```sh
benchmark_dir=$(mktemp -d /private/tmp/HHVacancySber-benchmark.XXXXXX)
bash scripts/benchmarks/build.sh "$benchmark_dir/benchmark"
"$benchmark_dir/benchmark" gate 100
"$benchmark_dir/benchmark" enrichment-cancel 100
"$benchmark_dir/benchmark" enrichment-limit 100
"$benchmark_dir/benchmark" enrichment-repeat 100
"$benchmark_dir/benchmark" enrichment-favorites 500
"$benchmark_dir/benchmark" search 1000
"$benchmark_dir/benchmark" archive 1000
"$benchmark_dir/benchmark" pdf 10
"$benchmark_dir/benchmark" pdf 100
"$benchmark_dir/benchmark" pdf 500
"$benchmark_dir/benchmark" stress 1
"$benchmark_dir/benchmark" statistics 2000
"$benchmark_dir/benchmark" soak 500
```

Используйте положительное число вакансий. `stress` создаёт 1 200 HTML-абзацев на вакансию; остальные PDF-режимы — 12. `pdf` включает подготовку, валидацию и реальную transaction-публикацию. `statistics` включает atomic write, повторное открытие и проверку присутствия последнего входного ID. `soak` шесть раз заменяет один статистический PDF. `enrichment-*` проверяет подготовку ViewModel, а не рендер: exporter-spy фиксирует вызовы и возвращает отмену выбора каталога. В `enrichment-repeat` два последовательных экспорта. `enrichment-favorites` делает два экспорта из режима избранного; оба режима проверяют число экспортов, порядок и состав последнего снимка, а также отсутствие повторной загрузки details (ровно N запросов фикстуры на два экспорта). `search` прогоняет collector на локальной постраничной фикстуре; `archive` последовательно проверяет избранное через detail-фикстуру и дожидается сохранения. Живая сеть для этих режимов запрещена.

Вывод — JSON: wall-clock, CPU user+system (`getrusage`), peak RSS в байтах (macOS), текущий RSS через `ps` в KiB, число открытых дескрипторов из первых 1 024, страницы и размер файлов. `resident_kib: -1` означает, что sandbox запретил `ps`; это не отрицательное потребление памяти. Проверка heartbeat main actor включает накладные расходы самого harness (в том числе PDFKit extraction и `ps`); это не измерение задержки отрисовки SwiftUI. В PDF-режимах параллельно выполняются 20 лёгких mock detail-операций. Более прикладной сценарий фильтры + details + PDF покрыт unit integration-тестом.

Для сравнения собирайте before/after одним toolchain и запускайте не менее пяти раз в одинаковой среде разрешений. Не смешивайте sandbox и unrestricted: на macOS 13 доступ к font registry меняет даже layout/размер PDF. Не запускайте сборки и UI-тесты параллельно с timed benchmark. Короткие wall-clock-замеры чувствительны к scheduler и фоновой нагрузке; надёжнее точные request counts, semantic checks и scaling.

Каждый запуск создаёт собственный UUID-каталог и удаляет его после штатного завершения, включая transaction recovery directories, созданные только этим synthetic workload. Сам бинарник и module-cache остаются в выбранном `benchmark_dir`: после работы удалите именно этот проверенный каталог. После аварийного завершения проверьте собственный `HHRuntimeBench-*` каталог перед удалением. Не удаляйте пользовательские PDF recovery directories.

Для визуальной проверки задайте `HH_BENCH_PREVIEW=/absolute/scratch/preview.pdf` режиму `statistics`: указанный scratch-файл будет заменён копией отчёта. Затем используйте `pdftoppm`. Не указывайте существующий пользовательский документ.

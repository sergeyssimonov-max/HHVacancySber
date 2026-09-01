# СберВакансии

Нативное macOS-приложение на SwiftUI для полной выгрузки вакансий подтверждённых работодателей группы Сбер через API hh.ru. Приложение не является официальным продуктом Сбера или HeadHunter.

## Возможности

- версионированный список работодателей в `employers.json`, копируемый в `Application Support/HHVacancySber` для последующего редактирования;
- typed-запросы к hh.ru и полная пагинация с проверкой количества записей;
- разбиение выдачи глубже ограничения API в 2000 результатов по регионам и датам;
- семидневный кэш дерева `/areas` с явно обозначенным использованием устаревших данных;
- строгая классификация региона: субъект/город, «Удалённо» или «Регион не определён»;
- фильтры работодателя и субъекта с AND-семантикой, стабильные сортировки;
- избранное в формате v2 с автоматической миграцией v1, архивные статусы и PDF;
- lazy-загрузка описания вакансии и сохранение последней полной выдачи при ошибке обновления.

Начальная конфигурация ограничена работодателями, для которых принадлежность экосистеме подтверждена явно. Она не претендует на исчерпывающий охват и может редактироваться без пересборки.

## Требования и сборка

- Apple silicon, macOS 13.0 или новее;
- Xcode 15.2 или новее;
- application token hh.ru, установленный локально по [чек-листу](HH_TOKEN_LOCAL_CHECKLIST.md).

```zsh
cd HHVacancySber
xcodebuild -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
xcodebuild -project HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Debug -destination 'platform=macOS,arch=arm64' test
```

Пользовательское имя приложения — `СберВакансии.app`, bundle ID — `local.sergey.HHVacancySber`. App Sandbox разрешает исходящие сетевые соединения и выбранные пользователем файлы.

## Конфигурация работодателей

Bundled-файл находится в `HHVacancySber/HHVacancySber/employers.json`. При первом запуске он атомарно копируется в `~/Library/Application Support/HHVacancySber/employers.json`; далее runtime-файл является источником истины. Пустой список, пустые или повторяющиеся ID и некорректная схема завершают поиск явной ошибкой — скрытого fallback нет.

## Иконка и релиз

Канонический вектор — `HHVacancySber/Design/AppIcon.svg`. Скрипт `HHVacancySber/Scripts/render_icon.py` создаёт слоты 16–1024 через CairoSVG, `rsvg-convert` или Pillow и явно завершается ошибкой, если SVG-backend недоступен.

DMG собирается из чистого commit командой `scripts/release.sh --output-dir <directory>`. Скрипт проверяет Release-настройки, sandbox entitlements и итоговый образ.

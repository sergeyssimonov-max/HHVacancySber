# Локальный checklist application token hh.ru

Репозиторий содержит только placeholder. Реальный application token никогда не добавляется в Git, test fixtures, логи, сообщения об ошибках или скриншоты.

## Получение и установка

1. Создайте приложение в [кабинете разработчика hh.ru](https://dev.hh.ru/admin) и получите application token по актуальной документации API.
2. Откройте `HHVacancySber/HHVacancySber/HHAuthConfig.swift`.
3. Локально замените `REPLACE_WITH_YOUR_HH_APPLICATION_TOKEN` реальным значением. Не передавайте это изменение в commit.

Для проверки token из shell вводите значение скрыто:

```zsh
printf 'Application token: '
read -s HH_SBER_TOKEN
printf '\n'
curl -i 'https://api.hh.ru/me' \
  -H "Authorization: Bearer ${HH_SBER_TOKEN}" \
  -H 'HH-User-Agent: HHVacancySber/1.0 (prionium@yandex.ru)' \
  -H 'User-Agent: HHVacancySber/1.0 (prionium@yandex.ru)' \
  -H 'Accept: application/json'
unset HH_SBER_TOKEN
```

## Проверка перед commit

Проверяйте только короткий уникальный фрагмент token, не печатая само значение:

```zsh
rg -l 'TOKEN_FRAGMENT' . --glob '!.git/**'
git diff -- HHVacancySber/HHVacancySber/HHAuthConfig.swift
```

Ожидаемое состояние tracked-файла:

```swift
static let appAccessToken = "REPLACE_WITH_YOUR_HH_APPLICATION_TOKEN"
```

После локальной сборки верните placeholder до создания commit. При подозрении на утечку немедленно отзовите token в кабинете hh.ru.

# Проверка встроенного application token hh.ru

Application token осознанно хранится в `HHVacancySber/HHVacancySber/HHAuthConfig.swift` и входит в конфигурацию приватного репозитория. Чистый checkout не требует ручной установки token.

Значение token не должно появляться в UI, логах, сообщениях об ошибках, test fixtures, screenshots или CI output. Не заменяйте его placeholder перед commit.

## Безопасная структурная проверка

```zsh
auth_config='HHVacancySber/HHVacancySber/HHAuthConfig.swift'
grep -Eq 'static let appAccessToken = "[^"]+"' "$auth_config"
! grep -q 'static let appAccessToken = placeholderAccessToken' "$auth_config"
! grep -q 'static let appAccessToken = "REPLACE_WITH_YOUR_HH_APPLICATION_TOKEN"' "$auth_config"
```

Эта проверка подтверждает форму конфигурации, не печатая секрет. Работоспособность проверяется read-only запросом к hh.ru с теми же Bearer и User-Agent headers, которые использует приложение.

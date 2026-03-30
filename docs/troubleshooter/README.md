# Troubleshooter — решения ошибок и инцидентов

Сюда складываем **проверенные** решения: симптом → причина → действия → ссылки.

## Как добавлять запись

1. Создайте файл `YYYY-MM-DD-kratkoe-opisanie.md` (или тематическую папку, если накопится много записей по одной области).
2. Используйте шаблон: [`TEMPLATE.md`](TEMPLATE.md).
3. В конце укажите окружение (local/staging/prod), версию приложения/commit при возможности.

## Индекс (заполнять вручную по мере появления записей)

| Дата | Тема | Файл |
|------|------|------|
| 2026-03-28 | Minitest + SQLite: отключить `parallelize` | [2026-03-28-minitest-sqlite-no-parallel.md](2026-03-28-minitest-sqlite-no-parallel.md) |
| 2026-03-29 | WSL / PowerShell и Ollama на `127.0.0.1` | [2026-03-29-wsl-powershell-ollama-localhost.md](2026-03-29-wsl-powershell-ollama-localhost.md) |
| 2026-03-30 | Playwright worker в WSL: нет `headless_shell` | [2026-03-30-playwright-worker-wsl-headless-shell.md](2026-03-30-playwright-worker-wsl-headless-shell.md) |

## Связь с остальной документацией

- Операции и типовые сценарии: [`../RUNBOOK.md`](../RUNBOOK.md)
- Безопасность и утечки: [`../SECURITY-PRIVACY.md`](../SECURITY-PRIVACY.md)
- Интеграции и лимиты: [`../INTEGRATIONS.md`](../INTEGRATIONS.md)

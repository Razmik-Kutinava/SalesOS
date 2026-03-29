# WSL / PowerShell и Ollama на `127.0.0.1`

## Метаданные

- **Дата:** 2026-03-29  
- **Окружение:** local  
- **Теги:** ollama, wsl, windows, powershell  

## Симптом

- В **WSL** (`bash`): `curl http://127.0.0.1:11434/api/tags` → `Failed to connect`, хотя Ollama установлена на **Windows**.
- В **PowerShell**: вставка строки вывода тестов (`30 runs, 57 assertions…`) или строки с приглашением bash (`darks@…$ curl …`) → ошибки парсера / `CommandNotFoundException`.
- В PowerShell команда `curl` открывает предупреждение про **Invoke-WebRequest** и разбор HTML.

## Контекст

Ollama по умолчанию слушает **localhost хоста**, где запущен её процесс. **WSL2** имеет **свой** сетевой loopback: `127.0.0.1` внутри Linux — это не тот же интерфейс, что **localhost Windows**, где обычно слушает Ollama для Windows.

## Диагностика

- Из **PowerShell на Windows**: `Invoke-WebRequest -Uri http://127.0.0.1:11434/api/tags -UseBasicParsing` или `curl.exe http://127.0.0.1:11434/api/tags` → часто **200**.
- Из **WSL**: тот же запрос на `127.0.0.1` может **не** достучаться до демона на Windows.

## Причина (root cause)

Разные сетевые стеки: **loopback WSL ≠ loopback Windows**; плюс путаница **alias `curl` = `Invoke-WebRequest`** в PowerShell и вставка **не-команд** из логов в оболочку.

## Решение

1. **Rails и проверки Ollama с той же ОС, где крутится Ollama** (типично **PowerShell + Windows Ruby**): `OLLAMA_HOST=http://127.0.0.1:11434`, `bin/rails ollama:ping`.
2. **Rails в WSL, Ollama на Windows:** в `.env` или `export` задать `OLLAMA_HOST=http://<IP_хоста_Windows>:11434` (часто IP из `nameserver` в `/etc/resolv.conf` в WSL2); при необходимости разрешить порт **11434** в брандмауэре Windows для подсети WSL.
3. **PowerShell:** для HTTP без предупреждений — `curl.exe …` или `Invoke-WebRequest … -UseBasicParsing`.
4. В проекте: скопировать **`.env.example` → `.env`** и править `OLLAMA_HOST` под своё окружение (`dotenv-rails` подхватит в development/test).

## Профилактика

- Не вставлять в терминал строки из логов (результаты minitest, приглашения `user@host$`).
- Держать в репозитории актуальные подсказки: `docs/integrations/OLLAMA-RAILS-INTEGRATION.md`, этот файл.

## Ссылки

- `docs/integrations/OLLAMA-RAILS-INTEGRATION.md`

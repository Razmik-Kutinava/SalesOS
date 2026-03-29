# Интеграция Ollama в SalesOS (Rails)

Документ описывает **что сделано в коде** и **что нужно сделать тебе локально**, чтобы Ollama работала с приложением.

---

## Порты (важно различать)

| Сервис | Порт по умолчанию | Назначение |
|--------|-------------------|------------|
| **Ollama** | **11434** | HTTP API (`/api/chat`, `/api/tags`, …). Слушает на `127.0.0.1`, если не менял конфиг. |
| **Rails (Puma)** | **3000** | Веб-приложение. Health Ollama в приложении: `GET http://localhost:3000/health/ollama` — это **прокси-проверка** из Rails к Ollama, не замена порта Ollama. |

Итого: Ollama — **11434**, Rails — **3000**. В `OLLAMA_HOST` указывается именно адрес **Ollama** (обычно `http://127.0.0.1:11434`).

---

## Что сделано в репозитории

1. **`app/services/llm/ollama_client.rb`** — `Llm::OllamaClient`:
   - `chat(messages:, model: nil, format: nil)` → `POST /api/chat`, `stream: false`;
   - `tags` → `GET /api/tags` (список моделей);
   - `reachable?` → быстрая проверка без исключения наружу;
   - `Llm::OllamaClient.message_content(hash)` — достать текст ответа ассистента;
   - ошибки: `ConfigurationError`, `HttpError`, `TimeoutError` (наследники `Llm::OllamaClient::Error`).

2. **`config/initializers/ollama.rb`** — после старта приложения читает конфиг и кладёт в `Rails.application.config.ollama` (`base_url`, `default_model`) для обзора в консоли/отладке.

3. **`GET /health/ollama`** — `OllamaHealthController` (JSON, без `allow_browser` из HTML-контроллера):
   - успех: `{ ok: true, base_url, default_model, models: [...] }`;
   - ошибка: `503` + `{ ok: false, error, message }`.

4. **Rake:** `bin/rails ollama:ping` — дергает `/api/tags` и короткий `chat` (нужен запущенный Ollama и скачанная модель).

5. **Тесты:** `test/services/llm/ollama_client_test.rb`, `test/integration/ollama_health_test.rb` (WebMock, без реальной сети).

6. **Переменные окружения** — см. **`.env.example`** в корне репозитория.

---

## Переменные окружения

| Переменная | По умолчанию | Смысл |
|------------|--------------|--------|
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Базовый URL Ollama (без `/` в конце). |
| `OLLAMA_MODEL` | `llama3.2` | Модель для `chat`, если не передать `model:` явно. |
| `OLLAMA_OPEN_TIMEOUT` | `5` | Таймаут установки соединения (сек). |
| `OLLAMA_READ_TIMEOUT` | `120` | Таймаут чтения ответа (сек); для LLM лучше не делать слишком маленьким. |

В **development** и **test** переменные можно задавать через файл **`.env`** в корне репозитория (шаблон — `.env.example`): подключён gem **`dotenv-rails`**. В **production** используй реальные env на хосте / в оркестраторе (файл `.env` в git не коммитится).

---

## Что сделать тебе локально (пошагово)

### 1. Установить Ollama

- **Windows / macOS / Linux:** скачай установщик с официального сайта: [https://ollama.com/download](https://ollama.com/download).
- После установки в трее/службах должен быть запущен процесс **Ollama** (он поднимает сервер на **11434**).

### 2. Проверить, что API доступен

**Linux / macOS / Git Bash:**

```bash
curl http://127.0.0.1:11434/api/tags
```

**PowerShell (Windows):** `curl` — это часто **alias** на `Invoke-WebRequest` (предупреждение про разбор HTML). Надёжнее:

```powershell
curl.exe http://127.0.0.1:11434/api/tags
# или
Invoke-WebRequest -Uri http://127.0.0.1:11434/api/tags -UseBasicParsing
```

**WSL:** если Ollama запущена **только на Windows**, запрос к `http://127.0.0.1:11434` из WSL может **не дойти** до демона (разный loopback). См. **troubleshooter:** `docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`.

Ожидается JSON со списком `models` (может быть пустым, пока не скачал модели).

**Не вставляй в терминал** строки из логов (например `30 runs, 57 assertions…`) или целиком строку с приглашением bash (`user@host$ …`) — оболочка попытается выполнить их как команду и выдаст ошибку.

### 3. Скачать модель

Имя должно совпадать с тем, что задашь в `OLLAMA_MODEL` (пример — `llama3.2`):

```bash
ollama pull llama3.2
```

Список локальных моделей:

```bash
ollama list
```

Если хочешь другую модель — измени `OLLAMA_MODEL` и сделай `ollama pull <имя>`.

### 4. Задать переменные для Rails

**Рекомендуется:** скопировать `.env.example` → `.env` и при необходимости поправить значения — в development/test их подхватит **dotenv-rails**.

Пример в PowerShell (одна сессия, без `.env`):

```powershell
$env:OLLAMA_HOST = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL = "llama3.2"
```

Пример в bash/WSL (синтаксис **не** как в PowerShell — не используй `$env:…`):

```bash
export OLLAMA_HOST=http://127.0.0.1:11434
export OLLAMA_MODEL=llama3.2
```

### 5. Запустить Rails и проверить интеграцию

```bash
bin/rails server
```

В другом терминале:

```bash
curl http://localhost:3000/health/ollama
```

Или из каталога приложения:

```bash
bin/rails ollama:ping
```

`ollama:ping` выполнит запрос к **Ollama на 11434**; если всё ок, увидишь список моделей и короткий ответ ассистента.

### 5a. Замеры latency и простые пробы качества (benchmark)

- **Rake:** `bin/rails ollama:benchmark` — для модели из `OLLAMA_MODEL` или списка `OLLAMA_BENCHMARK_MODELS=model1,model2` выводит время `GET /api/tags`, короткий чат и результаты проб (математика / факт / JSON).
- **Код:** `Llm::OllamaProbe` в `app/services/llm/ollama_probe.rb`; тесты и команды — в **`test/README.md`** (раздел про Ollama benchmark).

### 6. Если Rails в Docker/WSL, а Ollama на Windows (или наоборот)

- `127.0.0.1` внутри контейнера или **внутри WSL** — это **не** Windows-localhost, где слушает Ollama для Windows. Нужен адрес хоста: например `http://host.docker.internal:11434` (Docker Desktop Windows/Mac), **IP хоста Windows** с точки зрения WSL (часто из `grep nameserver /etc/resolv.conf`), или IP машины в LAN.
- Убедись, что **11434** не блокирует файрвол при доступе с WSL к Windows.
- Подробнее: **`docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`**.

---

## Безопасность

- **`/health/ollama`** отдаёт список моделей и URL из конфига — для **продакшена** имеет смысл ограничить доступ (Basic Auth, VPN, только внутренняя сеть) или отключить маршрут.
- Не выставляй Ollama без аутентификации в интернет без reverse proxy и политики доступа.

---

## Связанные документы

- Голосовой конвейер (Whisper + интенты): **`docs/integrations/VOICE-PIPELINE.md`**
- `docs/stack/ollama.md`
- `docs/INTEGRATIONS.md`
- `docs/ARCHITECTURE.md`, ADR `docs/ADRs/003-voice-asr-ollama-intent-router.md`

---

## Журнал изменений (кратко)

| Дата | Изменение |
|------|-----------|
| 2026-03-28 | Первый вариант: `Llm::OllamaClient`, `/health/ollama`, `ollama:ping`, WebMock-тесты, `.env.example`. |
| 2026-03-29 | `Llm::OllamaProbe`, `ollama:benchmark`, юнит-тесты пробы, опциональные live-тесты (`OLLAMA_LIVE_BENCHMARK=1`). |
| 2026-03-29 | `dotenv-rails` + `.env` для Ollama в dev/test; доп. разделы про PowerShell/`curl` и WSL; troubleshooter WSL↔Windows. |

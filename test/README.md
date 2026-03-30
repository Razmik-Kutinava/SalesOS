# Тесты SalesOS

## Где живут тесты

**Все автотесты проекта — только в папке `test/`.**  
Не размещать тесты в `spec/`, в корне, в `app/` и т.д.

- Модели: `test/models/`
- Контроллеры (когда появятся): `test/controllers/`
- Интеграция / система: `test/integration/`, `test/system/`
- Общая настройка: `test/test_helper.rb`

## Журнал прогонов и итогов

Файл **[TEST_LOG.md](TEST_LOG.md)** — что планировали, что сделали, результаты прогонов (`bin/rails test`), заметки.  
Обновлять после значимых сессий тестирования.

## Проблемы и фиксы

Если тесты падают из‑за окружения, конфига БД, SQLite, параллельного запуска и т.п. — **решение фиксируем** в `docs/troubleshooter/` (шаблон `docs/troubleshooter/TEMPLATE.md`), а в `TEST_LOG.md` даём ссылку на файл.

## Команды

```bash
bin/rails test
bin/rails test test/models/user_test.rb
```

## Ollama: замеры модели и скорости

Интеграция с Ollama уже в приложении (`Llm::OllamaClient`, см. `docs/integrations/OLLAMA-RAILS-INTEGRATION.md`). Чтобы **понять, какая модель задана**, **как быстро отвечает** и **пройти простые пробы качества** (арифметика, факт, JSON):

1. **Юнит-тесты (без сети, WebMock)** — всегда в общем прогоне:
   - `test/services/llm/ollama_probe_test.rb` — `Llm::OllamaProbe` (latency, сравнение моделей на моках).

2. **Живые вызовы к локальному Ollama** (по умолчанию **пропускаются**):
   ```bash
   export OLLAMA_LIVE_BENCHMARK=1
   bin/rails test test/integration/ollama_live_benchmark_test.rb
   ```
   Нужен запущенный Ollama и переменные `OLLAMA_HOST` / `OLLAMA_MODEL` (bash: `export …`, не синтаксис PowerShell).

3. **Rake без тестов** — таблица по одной или нескольким моделям:
   ```bash
   bin/rails ollama:benchmark
   OLLAMA_BENCHMARK_MODELS=llama3.2,qwen2.5:0.5b bin/rails ollama:benchmark
   ```

Переменные `OLLAMA_*` в development/test можно держать в **`.env`** (из `.env.example`); см. `docs/integrations/OLLAMA-RAILS-INTEGRATION.md`. WSL + Ollama на Windows: **`docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`**.

Как выбирать модель: смотрите **latency** (`GET /api/tags`, tiny chat) и **ratio** пройденных проб; быстрые маленькие кванты удобны для интерактива, тяжёлые — для качества — сравнивайте на своём железе через `ollama:benchmark`.

**Голос (Whisper + Ollama + интенты):** см. [`docs/integrations/VOICE-PIPELINE.md`](../docs/integrations/VOICE-PIPELINE.md), облако ASR — [`docs/integrations/OPENAI-WHISPER-API.md`](../docs/integrations/OPENAI-WHISPER-API.md). Тесты: `test/services/voice/intent_router_test.rb` (20+ сценариев), `test/services/asr/*`, `test/services/voice/ollama_intent_parser_test.rb`, `test/integration/voice_commands_test.rb`.

## База данных в test

Используется `storage/test.sqlite3` (см. `config/database.yml`). Перед прогоном: `bin/rails db:test:prepare`.

## Импорт лидов (CSV / Excel, Roo)

На **Ruby 3.4+** библиотека `csv` не входит в default gems — в `Gemfile` указаны `gem "csv"` и `gem "roo"`. Если при старте приложения видите `LoadError: cannot load such file -- csv`, выполните `bundle install`.

## Playwright fetch worker

Отдельный процесс **Node.js** в каталоге `playwright-worker/`; Rails обращается через `Fetch::PlaywrightClient` и `FetchUrlJob` (переменные `PLAYWRIGHT_*` в `.env.example`).  
Тесты **без реального браузера**: WebMock. См. `playwright-worker/README.md`, `LEAD_RESEARCH_SOURCES.md` (список источников для лидов — на апрув).

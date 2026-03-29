# Журнал тестирования

## 2026-03-28 — стартовый набор модельных тестов (БД)

**План:** 30 тестов в `test/models/` — валидации, ассоциации, уникальность, scope, ограничения `restrict_with_exception`.

**Сделано:**

- Политика в `test/README.md`; правило Cursor `omni-testing.mdc`.
- Файлы: `account_test`, `user_test`, `lead_test`, `lead_event_test`, `task_test`, `lead_document_test`, `voice_session_test`, `pending_action_test`.
- `test_helper.rb`: отключён параллельный прогон (SQLite + один файл БД).

**Прогон:** `bin/rails test` (после `bin/rails db:test:prepare`).

**Итог:** **30 runs, 57 assertions, 0 failures, 0 errors, 0 skips** (~0.99s локально, Windows).

**Troubleshooter:** превентивно — [`docs/troubleshooter/2026-03-28-minitest-sqlite-no-parallel.md`](../docs/troubleshooter/2026-03-28-minitest-sqlite-no-parallel.md) (почему отключён `parallelize` в `test_helper.rb`).

---

## 2026-03-28 — Ollama

**План:** HTTP-клиент, health, rake ping, тесты с WebMock, дока для локального запуска.

**Сделано:** см. [`docs/integrations/OLLAMA-RAILS-INTEGRATION.md`](../docs/integrations/OLLAMA-RAILS-INTEGRATION.md).

**Прогон:** `bin/rails test` — **37 runs** (30 доменных + 5 Ollama client + 2 integration health).

---

## 2026-03-29 — Ollama: замеры модели, скорость, пробы качества

**План:** зафиксировать характеристики текущей нейросети (модель по `OLLAMA_MODEL`, latency, простые проверки ответов); тесты в `test/`, журнал здесь.

**Что уже было (подключение Ollama):** HTTP-клиент `Llm::OllamaClient`, initializer, `GET /health/ollama`, rake `ollama:ping`, переменные `OLLAMA_HOST` / `OLLAMA_MODEL` — см. `docs/integrations/OLLAMA-RAILS-INTEGRATION.md`. Связь проверяется `bin/rails ollama:ping` или `curl http://localhost:3000/health/ollama`.

**Сделано в этой сессии:**

- Сервис **`Llm::OllamaProbe`** (`app/services/llm/ollama_probe.rb`): замер `GET /api/tags`, короткий чат («pong»), набор проб `DEFAULT_PROBES` (математика, столица, JSON), сводка `suite`, сравнение нескольких имён моделей `compare_models`.
- **Юнит-тесты:** `test/services/llm/ollama_probe_test.rb` (WebMock, без реальной сети).
- **Интеграционные live-тесты:** `test/integration/ollama_live_benchmark_test.rb` — только при `OLLAMA_LIVE_BENCHMARK=1` (разрешается сеть через WebMock); иначе **skip**.
- **Rake:** `bin/rails ollama:benchmark` — вывод таблицы по `OLLAMA_MODEL` или списку `OLLAMA_BENCHMARK_MODELS=m1,m2`.
- Инструкции в **`test/README.md`** (раздел «Ollama: замеры модели и скорости»).

**Прогон:** `bin/rails test` (после `bin/rails db:test:prepare` при необходимости).

**Итог:** **56 runs, 116 assertions, 0 failures, 0 errors, 4 skips** (пропуски — live Ollama без `OLLAMA_LIVE_BENCHMARK=1`).

**Live-прогон (опционально):** `OLLAMA_LIVE_BENCHMARK=1 bin/rails test test/integration/ollama_live_benchmark_test.rb` при запущенном Ollama.

---

## 2026-03-29 — Ollama: dotenv, документация WSL/PowerShell

**Сделано:** gem `dotenv-rails` (development, test); обновлены `.env.example`, `README.md` (копирование `.env`), `docs/integrations/OLLAMA-RAILS-INTEGRATION.md` (PowerShell `curl.exe`, WSL, не вставлять вывод тестов в shell); запись **troubleshooter** [`docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`](../docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md); индекс в `docs/troubleshooter/README.md`; ссылка в `test/README.md`.

**Прогон:** `bundle install` затем `ruby bin/rails test` (Windows PowerShell).

**Итог:** **56 runs, 116 assertions, 0 failures, 0 errors, 4 skips** (live Ollama без `OLLAMA_LIVE_BENCHMARK=1`).

**Troubleshooter:** [`docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`](../docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md).

---

## 2026-03-29 — Голос → Whisper → Ollama → IntentRouter (каркас)

**Сделано:** сессии (`SessionsController`), `LeadsController`, `POST /leads/:id/voice` (`VoiceCommandsController`), сервисы `Asr::WhisperRunner`, `Voice::Pipeline`, `Voice::OllamaIntentParser`, `Voice::IntentRouter`; Stimulus `voice_controller`; стили `app/assets/stylesheets/app.css`; дока [`docs/integrations/VOICE-PIPELINE.md`](../docs/integrations/VOICE-PIPELINE.md); `.env.example` (WHISPER / `VOICE_ASR_STUB`); seed «Demo Lead».

**Тесты:** `test/services/voice/intent_router_test.rb`, `test/integration/voice_commands_test.rb`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **61 runs, 136 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — OpenAI Whisper API + расширение голосовых тестов

**Сделано:** миграция `leads.next_call_at`; `Asr::OpenaiWhisperClient`; выбор бэкенда в `Asr::WhisperRunner` (`ASR_BACKEND=openai` + `OPENAI_API_KEY`); интент `update_lead` с полем **следующий звонок**; дока [`docs/integrations/OPENAI-WHISPER-API.md`](../docs/integrations/OPENAI-WHISPER-API.md); обновлены `VOICE-PIPELINE.md`, `.env.example`.

**Тесты:** расширен `intent_router_test` (20 кейсов поведения), добавлены `openai_whisper_client_test`, `whisper_runner_test`, `ollama_intent_parser_test`.

**Прогон:** `ruby bin/rails db:migrate` и `ruby bin/rails db:test:prepare`, затем `ruby bin/rails test`.

**Итог:** **93 runs, 204 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — ASR: автозаглушка в development + 422 при ошибке конфигурации

**Сделано:** в `development` без Whisper/OpenAI `Asr::WhisperRunner` использует текст заглушки; `VOICE_ASR_STUB=0` отключает автозаглушку; при отсутствии ASR ответ голоса **422** вместо 503; тесты `stub_mode?`; обновлены `.env.example`, `docs/integrations/VOICE-PIPELINE.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **97 runs, 208 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — консоль: история событий, реальный ASR по OPENAI_API_KEY

**Сделано:** лента `LeadEvent` на консоли; баннер режима ASR (stub / OpenAI / local); при успешном применении интента — перезагрузка страницы и блок `[CRM] Сделано`; `OPENAI_API_KEY` без `ASR_BACKEND=openai` включает Whisper API; `ASR_BACKEND=local_whisper` — только локальный whisper; `OllamaIntentParser` уточнённый промпт; `Voice::Pipeline` ловит `Asr::OpenaiWhisperClient::Error`; `.env.example` (`OLLAMA_READ_TIMEOUT=300`).

**Прогон:** `ruby bin/rails test`.

**Итог:** **100 runs, 216 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — локальный Whisper: дока, voice:check_asr, 429 OpenAI, stub + local_whisper

**Сделано:** `docs/integrations/LOCAL-WHISPER-SETUP.md`; `bin/rails voice:check_asr`; понятные сообщения OpenAI (429/401); `Voice::Pipeline` отдаёт текст ошибки OpenAI; `stub_mode?` не подменяет заглушкой при `ASR_BACKEND=local_whisper`; `.env` / `.env.example` обновлены (ключи не хранить в чате).

**Прогон:** `ruby bin/rails test`.

**Итог:** **101 runs, 217 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — консоль лидов (одна страница: таблица + голос)

**План:** `root` — страница с таблицей полей лидов и панелью голоса для выбранного лида (`?lead_id=`); редиректы со старых `leads#index` / `leads#show`.

**Сделано:** `LeadConsoleController#show`, `app/views/lead_console/show.html.erb`, стили в `app/assets/stylesheets/app.css`; `config/routes.rb` — `root "lead_console#show"`; `LeadsController#index` → `root_path`, `#show` → `root_path(lead_id: ...)`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **93 runs, 204 assertions, 0 failures, 0 errors, 4 skips**.

---

## 2026-03-29 — ASR: WHISPER_USE_WSL (Windows Ruby + whisper из WSL)

**Сделано:** `Asr::WhisperRunner` — вызов `wsl.exe` при `WHISPER_USE_WSL=1`, конвертация путей к WAV/модели в `/mnt/c/...`; `resource_path_exists?` для проверки модели; `voice:check_asr` проверяет `wsl … -h`; `.gitignore` — `whisper.cpp/build/`, `models/*.bin`; обновлены `.env.example`, `LOCAL-WHISPER-SETUP.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **104 runs, 220 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — .env: FFMPEG_BIN (WinGet) + WHISPER_USE_WSL, игнор ffmpeg-8.1 исходников

**Сделано:** в `.env` заданы `FFMPEG_BIN` на шим WinGet, `WHISPER_*` + `WHISPER_USE_WSL=1`; `.gitignore` — `/ffmpeg-8.1/`; дока `LOCAL-WHISPER-SETUP.md` (исходники ≠ exe).

**Прогон:** `ruby bin/rails test`; `ruby bin/rails voice:check_asr` — все OK.

**Итог:** **104 runs, 220 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — голос: приоритет update_lead, stage/score, LeadIntentEnricher

**Сделано:** расширен промпт `OllamaIntentParser`; `IntentRouter` — `stage`, `score`; `Voice::LeadIntentEnricher`; тесты; `VOICE-PIPELINE.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **110 runs, 230 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — голос: delete_lead сразу (discarded_at), без PendingAction

**Сделано:** `IntentRouter#apply_delete_lead`, интент `delete_lead` / алиас `request_delete_lead` → мягкое удаление; событие `lead_discarded`; промпт и `LeadIntentEnricher` под фразы «удали лид»; `voice_controller` — редирект на `/` после `lead:discarded`; вью, тесты, `VOICE-PIPELINE.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **112 runs, 234 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — POST /leads/:id/voice: 410 для архивного лида (без RecordNotFound)

**Сделано:** `VoiceCommandsController#set_lead` — JSON `lead_gone` + **410 Gone** вместо 404 exception; `voice_controller.js` — редирект на `/`; интеграционный тест.

**Прогон:** `ruby bin/rails test`.

**Итог:** **113 runs, 236 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — голос без выбранного лида: `create_lead`, панель всегда, `POST /console/voice`

**План:** кнопка записи доступна при нуле активных лидов; интент `create_lead` (Whisper + Ollama + эвристики); эндпоинт `voice_console_path` без `lead_id`; после создания — редирект на `/?lead_id=`; сид не ломается после discard демо-лида.

**Сделано:** `Voice::IntentRouter` — `create_lead`, `Result#created_lead_id`; `VoiceCommandsController#create_console` + маршрут; `LeadConsoleController` — `@voice_post_path`, исправление «битого» `lead_id`; вью консоли — панель голоса всегда; `voice_controller` — редирект по `created_lead_id`; `OllamaIntentParser` / `LeadIntentEnricher`; `db/seeds.rb` — условие по `kept`; интеграционный тест: `Lead.update_all(discarded_at: …)` вместо `destroy_all` (FK).

**Прогон:** `ruby bin/rails test`.

**Итог:** **116 runs, 250 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — голос: температура Ollama для интента, enricher «перезвон завтра»

**Сделано:** `Llm::OllamaClient#chat` — параметр `options` (temperature и др.); `OllamaIntentParser` — `OLLAMA_INTENT_TEMPERATURE`, нормализация транскрипта; `LeadIntentEnricher` — эвристика `next_call_at` из речи + триггер для `add_note`→`update_lead`; тесты; `.env.example`, `VOICE-PIPELINE.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **118 runs, 255 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — голос: retry Ollama, few-shot, дни недели, ASR ru, аудит сессий

**План:** один retry JSON; few-shot вынесен; enricher — дни недели + `users.timezone`; whisper.cpp по умолчанию `ru`; пустой/длинный транскрипт до LLM; rake `voice:session_insights` и `voice:golden_check`; исправление regex `\w` vs кириллица.

**Сделано:** `OllamaIntentParser` — `SCHEMA_RULES` + `FEW_SHOT_EXAMPLES`, retry при битом JSON или неверном intent (`OLLAMA_INTENT_RETRY_TEMPERATURE`); `LeadIntentEnricher` — `CALL_RELATED_RE` с `\p{L}` (кириллица), `extract_next_call_at` — дни недели + `users.timezone`; `WhisperRunner.effective_whisper_language` (по умолчанию `ru` для whisper.cpp); `OpenaiWhisperClient` — `OPENAI_WHISPER_LANGUAGE`; `Pipeline` — пустой/длинный транскрипт; `Voice::SessionInsights`, `Voice::GoldenPhrases`, `voice:session_insights` / `voice:golden_check`; `voice:check_asr` — строка про эффективный язык; тесты; `.env.example`, `VOICE-PIPELINE.md`.

**Прогон:** `ruby bin/rails test`.

**Итог:** **129 runs, 280 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — RAG: загрузка PDF на консоли (`knowledge_documents`)

**План:** блок на главной странице без отдельной админки; PDF → чанки → Ollama embeddings → SQLite (`embedding_json`); `Llm::OllamaClient#embed`.

**Сделано:** миграции `knowledge_documents` / `knowledge_chunks`; модели; Active Storage; `IndexKnowledgeDocumentJob`; `Knowledge::PdfExtractor`, `TextChunker`, `Retriever`; `gem pdf-reader`; UI в `lead_console/show`; flash в layout; `docs/integrations/RAG-KNOWLEDGE-UPLOAD.md`; `.env.example` (`OLLAMA_EMBED_MODEL`, chunk env).

**Прогон:** `ruby bin/rails db:migrate` / `db:test:prepare`, затем `ruby bin/rails test`.

**Итог:** **134 runs, 292 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — RAG: чат по базе + текст on-the-fly + голос `add_knowledge`

**План:** подключить `Retriever` к ответам Ollama (`Knowledge::RagAnswer`); verification — нет чанков / низкий score → сообщение без галлюцинаций; форма текста и интент голоса для дописывания базы.

**Сделано:** колонка `body_text`; `KnowledgeDocument` — PDF или текст; `KnowledgeQueriesController` + `POST /knowledge/query`; `Knowledge::RagAnswer`; `Retriever` только `status: ready`; UI (Stimulus `rag-chat`), форма `text_knowledge_documents_path`; `VoiceIntentRouter` + `OllamaIntentParser` — `add_knowledge`; `LeadEvent` `knowledge_snippet_voice`; `config.active_job.queue_adapter = :test`; тесты; `RAG-KNOWLEDGE-UPLOAD.md`, `.env.example`.

**Прогон:** `ruby bin/rails db:migrate` / `db:test:prepare`, затем `ruby bin/rails test`.

**Итог:** **143 runs, 328 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — UI: вкладки «Лиды и голос» / «База знаний»

**Сделано:** `?tab=leads|rag`, навигация под шапкой, RAG вынесен на отдельную вкладку; редиректы `knowledge_documents` с `tab=rag`.

**Прогон:** `ruby bin/rails test` — **143 runs, 328 assertions, 0 failures, 0 errors, 5 skips**.

---

## 2026-03-29 — публичный репо: без `.claude/` и `docs/`

**Сделано:** `.gitignore` — `/.claude/`, `/docs/`; сняты с трека; README/CONTRIBUTING/CHANGELOG; удалены ветки Dependabot на origin.

**Прогон:** `ruby bin/rails test` — **143 runs, 328 assertions, 0 failures, 0 errors, 5 skips**.

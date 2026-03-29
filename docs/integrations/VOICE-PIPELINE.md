# Голос → Whisper → Ollama → IntentRouter (SalesOS)

Реализованный каркас **Phase 1** по `docs/ARCHITECTURE.md` и ADR `003-voice-asr-ollama-intent-router.md`.

## Поток

1. Браузер: **Stimulus** `voice_controller` записывает аудио (**MediaRecorder**), `POST /leads/:id/voice` с полем `audio`.
2. **Asr::WhisperRunner** — при наличии **`OPENAI_API_KEY`** запрос уходит в **OpenAI Whisper API** (можно явно `ASR_BACKEND=openai`); **`ASR_BACKEND=local_whisper`** — только локальный whisper.cpp, даже если ключ есть; иначе локальный whisper.cpp по `WHISPER_BIN`/`WHISPER_MODEL`; в **`development`** без всего этого — заглушка или `VOICE_ASR_STUB=1`. См. `OPENAI-WHISPER-API.md`, пошаговая локальная установка: **`LOCAL-WHISPER-SETUP.md`**. Проверка: `bin/rails voice:check_asr`.
3. **Voice::OllamaIntentParser** — `Llm::OllamaClient` с `format: "json"` и **`options.temperature`** (**`OLLAMA_INTENT_TEMPERATURE`**, по умолчанию **0.2**; при повторном запросе — **`OLLAMA_INTENT_RETRY_TEMPERATURE`**, по умолчанию **0.05**). Если JSON не распарсился или **intent/slots не согласованы** с allow-list — **один повтор** с коротким системным промптом «только JSON». В системном промпте разделены **правила** и **few-shot** примеры. Транскрипт **нормализуется** (пробелы). Ответ с полями `intent`, `slots`, `assistant_message`, `need_approval`. **Voice::LeadIntentEnricher** (с **`users.timezone`**) поднимает `add_note` → `update_lead` при email/телефоне, **перезвон + дата** (завтра/сегодня/послезавтра) или **день недели** («в пятницу в 11»).
4. **Voice::IntentRouter** — allow-list интентов: `noop`, `add_note`, `update_lead` (поля: `company_name`, `contact_name`, `email`, `phone`, **`stage`**, **`score`**, **`next_call_at`**), `create_task`, **`delete_lead`** (сразу `discarded_at` у текущего лида; событие `lead_discarded`). Устаревшее имя `request_delete_lead` обрабатывается так же, без очереди `PendingAction`.
5. **VoiceSession** сохраняет транскрипт и сырой ответ модели.

## Переменные окружения

| Переменная | Назначение |
|------------|------------|
| `OLLAMA_HOST`, `OLLAMA_MODEL` | Как в `OLLAMA-RAILS-INTEGRATION.md` |
| `OLLAMA_INTENT_TEMPERATURE` | Температура для шага интента (0.0–2.0), по умолчанию `0.2` |
| `OLLAMA_INTENT_RETRY_TEMPERATURE` | Температура для повторного запроса при битом JSON / неверном intent |
| `VOICE_TRANSCRIPT_MAX_CHARS` | Макс. длина транскрипта до LLM (по умолчанию `8000`) |
| `OPENAI_WHISPER_LANGUAGE` | Опционально, язык для OpenAI Whisper API (например `ru`) |
| `VOICE_ASR_STUB=1` | Не вызывать Whisper; текст из `VOICE_ASR_STUB_TEXT` |
| `VOICE_ASR_STUB=0` | В `development` отключить автозаглушку (нужен Whisper или OpenAI) |
| `WHISPER_BIN` | Путь к исполняемому файлу whisper.cpp (`main`, `whisper-cli`, …) |
| `WHISPER_MODEL` | Путь к файлу весов `.bin` / `.gguf` |
| `WHISPER_LANGUAGE` | Опционально, например `ru` (флаг `-l` у whisper.cpp) |
| `FFMPEG_BIN` | По умолчанию `ffmpeg` в PATH — конвертация webm/mp3 → WAV 16 kHz mono |

## UI и вход

- Корень `/` — консоль: таблица лидов + голос для выбранного (нужна сессия).
- `GET /login` — демо `admin@example.com` / `password` после `bin/rails db:seed`.
- Кнопки «Записать» / «Стоп и отправить» на той же странице для выбранного лида.

## Типовые проблемы

- **WSL и Ollama на Windows:** см. `docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md`.
- **Whisper не настроен (не `development`):** в ответе API `422` и подсказка. В **`development`** заглушка ASR подставляется сама, если не заданы Whisper/OpenAI; явно в `.env` можно `VOICE_ASR_STUB=1` или отключить автозаглушку: `VOICE_ASR_STUB=0`.

## Наблюдаемость и регрессия

- **`bin/rails voice:session_insights`** — сводка по `VoiceSession` за последние **7** дней (или `DAYS=14`): статусы, гистограмма intent из `raw_llm_response`, частые `error_message`.
- **`bin/rails voice:golden_check`** — прогон эталонных фраз из `Voice::GoldenPhrases::LIST` через Ollama (нужен доступный Ollama). Опционально `LEAD_ID=`, `TIMEZONE=Europe/Moscow`. Код выхода **2**, если не все intent совпали с ожидаемыми.

## Тесты

- `test/services/voice/intent_router_test.rb` — сценарии «что делает голос» (заметки, поля лида, **stage/score**, **перенос звонка**, задачи, заявка на удаление).
- `test/services/voice/lead_intent_enricher_test.rb` — подъём `add_note` → `update_lead` по email/телефону в тексте.
- `test/services/asr/openai_whisper_client_test.rb`, `test/services/asr/whisper_runner_test.rb`
- `test/services/voice/ollama_intent_parser_test.rb`
- `test/integration/voice_commands_test.rb` (WebMock на Ollama, stub ASR)
- `test/services/voice/pipeline_test.rb`, `session_insights_test.rb`, `golden_phrases_test.rb`

Полный прогон: **120+** тестов с WebMock (без реальных вызовов OpenAI/Ollama в CI).

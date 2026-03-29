# Архитектура SalesOS / Omni-Agent

**Версия:** 0.1  
**Статус:** Каркас (согласуется с `docs/product/PRD.md`)

---

## 1. Цели архитектуры

- **Один бэкенд** обслуживает **веб-клиент** (браузер) и **Telegram-бота** с общей доменной моделью и БД.
- **Phase 1:** надёжная связка **голос → ASR → Ollama → intent → действие** с аудитом.
- **Масштабирование по этапам:** без преждевременного Kubernetes; контейнер + Kamal при необходимости.
- **Локальный ИИ:** Ollama на машине пользователя/сервера; сетевой вызов по HTTP.

---

## 2. Высокоуровневая схема

```
[Браузер: Hotwire + Stimulus + Web Audio / MediaRecorder]
        │ HTTPS
        ▼
[Rails 8 — Puma] ──► [PostgreSQL]
        │                    ▲
        │                    │ Active Record
        ├──► [Solid Queue / фоновые джобы]
        │           │
        │           ├──► [Whisper / ASR адаптер]
        │           └──► [Ollama HTTP client]
        │
        └──► [Telegram Webhook / long poll]

[Опционально Phase 2+] ──► [Внешняя CRM: DB replica / API / ETL]
```

---

## 3. Слои приложения (Rails)

### 3.1. Presentation

- **Controllers** — HTML для Hotwire, JSON для API (минимальный или расширяемый).
- **Views** — Turbo Frames/Streams, минимальный JS для голоса.
- **Stimulus controllers** — запись микрофона, отправка аудио/chunks, отображение транскрипта, approve bar.

### 3.2. Application / Domain

- **Models** — `User`, `Lead`, `Task`, `LeadEvent`, `VoiceSession`, и др. (см. DATA-MODEL.md).
- **Services** — `VoicePipeline`, `IntentRouter`, `Llm::OllamaClient`, `Enrichment::*` (позже).
- **Policies** — авторизация (Pundit или самописная) для ролей.

### 3.3. Infrastructure

- **Jobs** — фоновая обработка ASR (если вынесено из запроса), тяжёлый RAG, синк CRM.
- **Cache** — Solid Cache или Redis (решение в ADR).
- **Storage** — Active Storage для импорта файлов.

---

## 4. Клиенты

### 4.1. Веб (основной)

- **Вход:** сессия + CSRF для HTML форм.
- **Голос:** `MediaRecorder` API → отправка на сервер (WebM/Opus/WAV в зависимости от браузера) → сервер вызывает Whisper (или браузерный Web Speech API как **не** основной путь из-за качества/офлайна).
- **UX:** минимум кнопок; обязательный текстовый fallback (скрытый/вторичный).

### 4.2. Telegram

- **Webhook** `POST /telegram/webhook` с верификацией секретного пути или токена.
- **Голос:** `getFile` → скачивание → тот же ASR pipeline.
- **Команды:** `/start`, привязка `telegram_id` к `User`.

---

## 5. Поток голос → действие (Phase 1)

1. **Клиент** завершает запись, отправляет аудио (или потоково — v2).
2. **Сервер** сохраняет файл (временно), ставит job или синхронно вызывает **Whisper** (нагрузка → job).
3. **Транскрипт** сохраняется в `VoiceSession` / `LeadEvent`.
4. **Ollama** получает: system prompt (роль оператора CRM), user message = транскрипт + контекст (текущий лид, последние события).
5. **Structured output** (JSON schema или tool-calling паттерн) — `intent`, `slots`, `assistant_message`.
6. **IntentRouter** валидирует intent против allow-list, проверяет права, решает need_approval.
7. **Transaction** изменяет БД или создаёт `PendingAction` до approve.
8. **Ответ клиенту** — Turbo Stream обновления UI + сообщение ассистента.

---

## 6. Ollama

- **Конфигурация:** `OLLAMA_HOST`, имя модели в админке или credentials.
- **Таймауты:** короткие для UX; retry с backoff на уровне job.
- **Контекст:** усечённый набор полей лида, чтобы не переполнить окно.

---

## 7. RAG (Phase 2 в полном виде)

- **Ingest:** PDF → текст → чанки → эмбеддинги (локальная модель эмбеддингов или Ollama) → **pgvector**.
- **Retrieval:** top-k чанков по запросу пользователя/автогенерации письма.
- **Injection:** в промпт с пометками источника.

---

## 8. Очереди и фон

- **Solid Queue** (по умолчанию в Rails 8 шаблоне) или **Sidekiq+Redis** — см. ADR.
- Джобы: `TranscribeAudioJob`, `SyncCrmJob`, `RecomputeLeadScoreJob`, `SendEmailJob` (Phase 3).

---

## 9. База данных

- **PostgreSQL** — основной источник истины приложения.
- **Расширение pgvector** — при включении RAG.
- Реплика для тяжёлых отчётов — опционально.

---

## 10. Аутентификация и авторизация

- **Devise** или `has_secure_password` + сессии — решение при реализации.
- Роли: `owner`, `admin`, `user`.
- API-токены для интеграций (Phase 2+) — отдельная таблица `api_tokens` с хешем.

---

## 11. Наблюдаемость

- **Rails log** — JSON в проде (рекомендуется).
- **Request id** — прокидывать в job arguments.
- **Health:** `/up` Rails 8 + кастомный `/health/ollama` (проверка TCP/HTTP).

---

## 12. Развёртывание

- **Dockerfile** — multi-stage, production gems.
- **Kamal** — см. docs/stack/kamal.md.
- Переменные окружения — через `.env` на сервере / секреты CI.

---

## 13. Мультиязычность

- **I18n** для UI.
- Промпты: отдельные шаблоны RU/EN или bilingual system prompt с явным указанием языка ответа.

---

## 14. Безопасность на уровне архитектуры

- Не выполнять произвольный код из ответа LLM.
- Все действия — через **явные** команды и валидацию параметров.
- Rate limit на голосовые endpoint и Ollama proxy.

---

## 15. Состояние realtime

- **Turbo Streams** для обновления UI после job.
- **Action Cable** опционально; можно polling для MVP.

---

## 16. Хранение аудио

- Политика: **не хранить** после транскрипции или TTL 24h — см. SECURITY-PRIVACY.md.

---

## 17. Синхронизация с внешней CRM (Phase 2)

Варианты:

1. **Read-only** доступ к реплике БД CRM → периодический ETL в SalesOS.
2. **API CRM** → двусторонний sync с id mapping таблицей.
3. **Импорт файлов** из CRM export.

ADR фиксирует выбранный путь.

---

## 18. Масштабирование горизонтальное

- Stateless веб-воркеры за load balancer.
- Сессии в cookie или DB/Redis.
- Очередь и БД — узкие места; connection pooling.

---

## 19. Зависимости от внешних сервисов по фазам

См. INTEGRATIONS.md; архитектурно все адаптеры за **интерфейсами** (`MailerProvider`, `SearchProvider`).

---

## 20. Структура каталогов (целевая)

```
app/
  models/
  controllers/
    web/
    api/
    telegram/
  services/
    voice/
    llm/
    intents/
    crm/
  jobs/
  views/
config/
  routes.rb
  initializers/ollama.rb
db/
  migrate/
```

---

## 21. Маршрутизация

- `namespace :admin` — админка.
- `namespace :api` — JSON для фронта/бота при необходимости.
- `post /voice/transcriptions` — загрузка аудио.
- `post /telegram/webhook` — бот.

---

## 22. Обработка ошибок

- **Ollama down:** пользователю дружелюбное сообщение + лог `ollama_error`.
- **ASR fail:** предложить повторить запись или ввести текст.

---

## 23. Версионирование API

- `/api/v1/...` при появлении публичного API.

---

## 24. Тестирование на уровне архитектуры

- Contract-тесты на `IntentRouter`.
- Интеграционные с заглушками Ollama (VCR/WebMock).

---

## 25. Производительность веба

- **Thruster** перед Puma при деплое.
- **Eager load** в production.

---

## 26. Локальная разработка

- `docker compose` с PostgreSQL (и опционально Ollama sidecar).
- Либо нативный PostgreSQL + Ollama на хосте.

---

## 27. Границы модулей

- `Voice` не знает о Telegram напрямую — только о `AudioBlob` + `user_id`.
- `Telegram` адаптер переводит update в внутренние команды.

---

## 28. Feature flags

- `Flipper` или простая таблица `settings` для включения RAG/почты без redeploy (опционально).

---

## 29. Backup архитектурный

- БД — ежедневные снимки; секреты — вне git.

---

## 30. Расширяемость

- Новый intent = новый handler + тест + запись в каталог PRD.

---

## 31. Anti-patterns

- Прямой вызов Ollama из view.
- Хранение секретов в репозитории.
- Отсутствие idempotency в джобах с side-effects.

---

## 32. Ссылки

- PRD: `docs/product/PRD.md`
- DATA-MODEL: `docs/DATA-MODEL.md`
- ADR: `docs/ADRs/`

---

## 33. Дополнение — поток данных при импорте Excel

Файл → Active Storage → `ImportBatch` record → job парсит строки → валидация → `Lead` upsert → события аудита → опционально `EnrichLeadJob`.

---

## 34. Дополнение — поток скоринга

Триггеры: изменение стадии, новый документ, время с последнего касания → `RecomputeLeadScoreJob` → обновление `leads.score` и `lead_scores` истории.

---

## 35. Дополнение — аудит

Каждая мутация лида создаёт `LeadEvent` с `actor` (user/system), `payload` JSON diff.

---

## 36. Дополнение — безопасность Telegram

Проверка `secret_token` в заголовке или path secret; ограничение IP при возможности.

---

## 37. Дополнение — CORS

Если отдельный SPA когда-либо — CORS только на API; сейчас same-origin Hotwire.

---

## 38. Дополнение — Content Security Policy

Строгая CSP для снижения XSS; `nonce` для inline скриптов голоса при необходимости.

---

## 39. Дополнение — WebSocket голос

Потоковый ASR в будущем через WebSocket к отдельному сервису — не MVP.

---

## 40. Дополнение — мультитенантность

`account_id` на всех сущностях — заложить nullable или default account для будущего SaaS.

---

## 41. Дополнение — поиск

Полнотекст PostgreSQL или pg_trgm для автокомплита компаний.

---

## 42. Дополнение — файлы больших размеров

Direct upload к S3-совместимому хранилищу при росте — Active Storage поддерживает.

---

## 43. Дополнение — локализация времени

Все timestamp в UTC; отображение в timezone пользователя.

---

## 44. Дополнение — лимиты загрузки

Rack middleware лимит тела запроса для голосовых upload.

---

## 45. Дополнение — идемпотентность Telegram updates

`update_id` уникальный индекс для защиты от повторной обработки.

---

## 46. Дополнение — секреты Ollama

Если Ollama удалённо — TLS + базовая auth на reverse proxy.

---

## 47. Дополнение — мониторинг job queue

Дашборд Solid Queue или Sidekiq Web UI защищённый админкой.

---

## 48. Дополнение — миграции без даунтайма

Расширенные стратегии для крупных таблиц — совместно с DBA.

---

## 49. Дополнение — логирование PII

Маскировать email/телефон в логах по умолчанию.

---

## 50. Дополнение — завершение

Архитектура итеративна: Phase 1 минимизирует moving parts; каждая фаза добавляет адаптеры, не ломая ядро.

---

*Документ будет обновляться по мере реализации.*

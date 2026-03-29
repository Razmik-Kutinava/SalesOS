# API и контракты SalesOS

**Версия:** 0.1  
**Статус:** Черновик контрактов (реализация по мере появления маршрутов)

---

## 1. Обзор

- **Основной клиент Phase 1:** server-rendered HTML + Turbo; JSON API минимален.
- **Публичный REST** версионируется как `/api/v1`.
- **Вебхуки входящие:** Telegram, опционально Stripe (позже).
- **Формат:** JSON, UTF-8, даты в ISO 8601.

---

## 2. Аутентификация

### 2.1. Сессия (браузер)

Cookie session; CSRF для не-GET.

### 2.2. Bearer token (интеграции)

`Authorization: Bearer <token>`

Токены выдаются в админке; хранится только digest.

---

## 3. Общие ответы

### 3.1. Успех

`200 OK` с телом объекта или `201 Created` + `Location`.

### 3.2. Ошибки

```json
{
  "error": {
    "code": "validation_error",
    "message": "Human readable",
    "details": { "email": ["invalid"] }
  }
}
```

Коды HTTP: 400, 401, 403, 404, 422, 429, 500.

### 3.3. Пагинация

`?page=1&per_page=50` или cursor `?after=cursor`.

Ответ:

```json
{
  "data": [],
  "meta": { "next_cursor": null, "total_count": 0 }
}
```

---

## 4. Leads

### 4.1. Список

`GET /api/v1/leads`

Query: `stage`, `q` (поиск), `owner_id`, `sort`.

### 4.2. Получить

`GET /api/v1/leads/:id`

### 4.3. Создать

`POST /api/v1/leads`

Тело:

```json
{
  "lead": {
    "company_name": "ACME",
    "contact_name": "Ivan",
    "email": "i@acme.ru",
    "phone": "+79001234567",
    "stage": "new",
    "metadata": {}
  }
}
```

### 4.4. Обновить

`PATCH /api/v1/leads/:id`

### 4.5. Удалить

`DELETE /api/v1/leads/:id` — может создавать `pending_action` если политика.

---

## 5. Lead events (аудит)

`GET /api/v1/leads/:id/events?limit=50`

Элемент:

```json
{
  "id": "...",
  "event_type": "stage_changed",
  "payload": {},
  "actor": { "type": "User", "id": 1 },
  "created_at": "2026-03-28T12:00:00Z"
}
```

---

## 6. Tasks

`GET /api/v1/leads/:id/tasks`  
`POST /api/v1/leads/:id/tasks`  
`PATCH /api/v1/tasks/:id`  
`DELETE /api/v1/tasks/:id`

---

## 7. Voice

### 7.1. Загрузка аудио

`POST /api/v1/voice/transcriptions`

`Content-Type: multipart/form-data`  
Поле `audio` — файл.

Ответ 202:

```json
{
  "voice_session_id": "uuid",
  "status": "processing"
}
```

### 7.2. Статус

`GET /api/v1/voice_sessions/:id`

```json
{
  "id": "uuid",
  "status": "done",
  "transcript": "текст",
  "assistant_message": "Я обновил стадию на qualified",
  "pending_action_id": null
}
```

---

## 8. Pending actions (approve)

`GET /api/v1/pending_actions?status=pending`

`POST /api/v1/pending_actions/:id/approve`  
`POST /api/v1/pending_actions/:id/reject`

---

## 9. Import

`POST /api/v1/imports`

multipart `file` (xlsx/csv).

Ответ:

```json
{ "import_batch_id": "uuid", "status": "pending" }
```

`GET /api/v1/imports/:id`

---

## 10. Telegram webhook

`POST /telegram/webhook/:secret`

Тело — Telegram Update JSON. Ответ `200 OK` быстро; тяжёлое в job.

---

## 11. Health

`GET /up` — Rails  
`GET /health` — кастом: БД + опционально Ollama

---

## 12. Webhooks исходящие (Phase 2)

Подписки на события: `lead.created`, `lead.updated`, `task.due`.

Заголовок подписи: `X-SalesOS-Signature: sha256=...`

---

## 13. Rate limits

Заголовки:

`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`

---

## 14. Idempotency

`Idempotency-Key` на POST для импорта и создания лидов из интеграций.

---

## 15. Версионирование

Breaking changes → новая версия `/api/v2`.

---

## 16. OpenAPI

Файл `openapi/salesos.yaml` (создать при стабилизации) — единый источник для клиентов.

---

## 17. CORS

Если SPA: whitelist origin; credentials осторожно.

---

## 18. Фильтрация полей

`?fields=id,company_name` опционально.

---

## 19. Bulk (осторожно)

`POST /api/v1/leads/bulk_update` — только с strict policy и job за кадром.

---

## 20. Схемы JSON (intents от LLM)

Внутренний контракт (не публичный):

```json
{
  "intent": "change_lead_stage",
  "slots": { "lead_id": "uuid", "stage": "qualified" },
  "assistant_message": "…",
  "need_approval": false
}
```

Валидация dry-schema или JSON Schema.

---

## 21. Ошибки Ollama

Код `llm_unavailable` 503 с retry hint.

---

## 22. Ошибки ASR

Код `transcription_failed` 422.

---

## 23. Админ API

`namespace :admin` под отдельным middleware и ролью.

---

## 24. Экспорт

`GET /api/v1/leads/export.csv` — async link через job при больших объёмах.

---

## 25. Соглашения имён

Plural ресурсы, snake_case в JSON.

---

## 26. Время

Все timestamp UTC с `Z`.

---

## 27. Локаль ответов

`Accept-Language` или параметр `locale` для сообщений об ошибках.

---

## 28. Размер тела

Лимит 10MB для голоса (настраивается).

---

## 29. Безопасность

Не отдавать `raw_llm_*` в публичный API без роли admin.

---

## 30. Примеры curl

```bash
curl -H "Authorization: Bearer $TOKEN" \
  https://app.example.com/api/v1/leads
```

---

## 31. Telegram Bot API (исходящие)

Используется сервером; не документируется как публичный API продукта.

---

## 32. Stripe (будущее)

Webhooks `POST /webhooks/stripe` с проверкой подписи.

---

## 33. Календарь Cal.com (будущее)

OAuth + booking webhooks — см. INTEGRATIONS.md.

---

## 34. Статусы import_batch

`pending`, `processing`, `completed`, `failed` в ответах API.

---

## 35. Коды intent allow-list

Документировать enum в коде и здесь дублировать кратко.

---

## 36. Нотификации

`POST /api/v1/notifications/mark_read` — при появлении inbox UI.

---

## 37. Поиск

`GET /api/v1/search?q=acme&type=leads`

---

## 38. RAG query (Phase 2)

`POST /api/v1/knowledge/query` с rate limit.

---

## 39. Версия API в заголовке

`X-API-Version: 1` дублирование для логов.

---

## 40. Deprecation

`Sunset` header за 90 дней до удаления.

---

## 41. Тестирование контракта

Contract tests против OpenAPI + примеры в `spec/fixtures/api/`.

---

## 42. Ошибка 401 vs 403

401 — не аутентифицирован; 403 — нет прав.

---

## 43. Мультитенантность

Все запросы фильтруются по `current_account_id` из сессии или токена.

---

## 44. Ссылки на модель

См. `docs/DATA-MODEL.md` для полей сущностей.

---

## 45. Чек-лист нового endpoint

Маршрут, policy, тест request, запись здесь, OpenAPI snippet.

---

## 46. Pagination max per_page

100 по умолчанию.

---

## 47. Sort whitelist

Только `created_at`, `updated_at`, `score` — защита от SQLi через column allow-list.

---

## 48. Embeds

`?include=owner,tasks` опционально для уменьшения чаттинга.

---

## 49. Optimistic locking

`lock_version` на lead при конфликтах редактирования.

---

## 50. Файлы

`POST /api/v1/leads/:id/documents` multipart.

---

## 51. Voice SSE (будущее)

`GET /api/v1/voice_sessions/:id/stream` для прогресса — не MVP.

---

## 52. Метрики

Prometheus endpoint опционально `/metrics` за auth.

---

## 53. Логирование запросов

request_id в ответе `X-Request-Id`.

---

## 54. Набор кодов ошибок

Централизованный YAML errors.yml для i18n.

---

## 55. SDK

Официального SDK нет; OpenAPI → codegen при необходимости.

---

## 56. Postman коллекция

Экспорт из OpenAPI для партнёров.

---

## 57. Стабильность Phase 1

HTML формы могут обходить часть JSON API — допустимо для скорости.

---

## 58. Безопасность вебхуков

Constant-time compare для подписей.

---

## 59. Retry policy клиентов

Экспоненциальный backoff на 503/429.

---

## 60. Заключение

Документ — живой контракт; изменения через PR + версия в шапке.

---

*Добавить `openapi/salesos.yaml` при первом стабильном релизе API.*

---

## 61. Совместимость с Hotwire

Формы Turbo могут возвращать `422 Unprocessable Entity` с HTML фрагментом ошибок; тот же контракт полей, что и в JSON, чтобы не дублировать валидацию.

---

## 62. Коды событий вебхука (исходящие)

Рекомендуемый enum: `lead.created`, `lead.updated`, `lead.deleted`, `task.created`, `task.completed`, `import.completed`, `voice_session.failed`.

---

## 63. Повторная доставка вебхука

Клиент отвечает `2xx` в течение 10s; иначе повтор с backoff (1m, 5m, 30m, 2h, 24h), max 10 попыток, затем запись в `webhook_dead_letters`.

---

## 64. Подпись вебхука (пример)

`X-SalesOS-Timestamp` + `X-SalesOS-Signature` = HMAC-SHA256 от `timestamp + "." + body` с секретом подписки.

---

## 65. Ограничение размера JSON тела API

По умолчанию 1MB для JSON; исключения документировать (bulk — только async).

---

## 66. Кэширование GET

`ETag`/`Last-Modified` для редко меняющихся справочников (стадии, настройки account) — Phase 2+.

---

## 67. GraphQL

Не планируется в обозримом будущем; REST + OpenAPI проще для B2B интеграций.

---

## 68. Мобильный клиент

Если появится нативный клиент — тот же `/api/v1` + refresh token стратегия (отдельный ADR).

---

## 69. Версия схемы intent (внутренняя)

Поле `schema_version` в ответе LLM-парсера для миграций форматов без простоя.

---

## 70. Лимит вложенности metadata

Рекомендация: глубина JSON не более 4 уровней для предсказуемости индексов GIN.

---

## 71. Часовые пояса в API

Поля `due_at` передаются в ISO 8601 с offset или Z; сервер нормализует в UTC.

---

## 72. Нулевые значения

`null` vs отсутствие ключа: для PATCH отсутствие — «не менять», явный `null` — очистить поле (если разрешено политикой).

---

## 73. Сортировка списка событий

По умолчанию `created_at desc`; параметр `order=asc` для чат-подобного UI.

---

## 74. Фильтр по диапазону дат

`?updated_after=...&updated_before=...` в ISO формате.

---

## 75. Квоты на создание лидов

Заголовок `X-RateLimit-Limit` per account; при превышении 429 с `code: "quota_exceeded"`.

---

## 76. Заключение дополнения

Секции 61–75 расширяют контракт без изменения базовых путей Phase 1; при конфликте с реализацией правит код или этот документ в одном PR.

# Модель данных SalesOS

**Версия:** 0.1  
**Статус:** Целевая схема (миграции могут отставать)

---

## 1. Назначение

Описывает сущности, связи, индексы и правила для **ядра CRM-lite**, **голосовых сессий**, **скоринга** и **стыка с внешней CRM** (Phase 2).

---

## 2. ER-диаграмма (текстовая)

```
accounts (будущий multi-tenant)
    │
    ├── users (belongs_to account)
    │       └── has_many lead_events (as actor)
    │
    ├── leads
    │       ├── belongs_to account
    │       ├── belongs_to owner (user, optional)
    │       ├── has_many lead_events
    │       ├── has_many tasks
    │       ├── has_many lead_documents
    │       ├── has_many voice_sessions
    │       └── has_many lead_scores (history)
    │
    ├── tasks (belongs_to lead, assignee user)
    ├── lead_documents (belongs_to lead, Active Storage)
    ├── voice_sessions (belongs_to user, optional lead)
    ├── lead_events (polymorphic target, actor)
    ├── import_batches
    ├── pending_actions (approval queue)
    ├── crm_id_mappings (external_id ↔ lead_id)
    └── knowledge_chunks (pgvector, Phase 2)
```

---

## 3. Соглашения

- **UUID** первичные ключи для публичных сущностей (рекомендуется) или bigint — ADR.
- **Timestamps:** `created_at`, `updated_at` везде.
- **Soft delete:** `discarded_at` (discard gem) опционально для leads.
- **JSONB** для гибких полей (`metadata`, `raw_llm`).

---

## 4. Таблица `accounts`

| Колонка      | Тип        | Описание                    |
|-------------|------------|-----------------------------|
| id          | uuid/pk    |                             |
| name        | string     | Название организации        |
| settings    | jsonb      | feature flags, лимиты       |
| created_at  | timestamptz|                             |

---

## 5. Таблица `users`

| Колонка         | Тип         | Описание                          |
|----------------|-------------|-----------------------------------|
| id             | pk          |                                   |
| account_id     | fk          |                                   |
| email          | string      | unique per account                |
| encrypted_password | string  | если Devise                       |
| role           | string      | owner / admin / user              |
| telegram_id    | bigint      | nullable, unique                  |
| locale         | string      | ru / en                           |
| timezone       | string      | IANA                              |

Индексы: `(account_id, email)` unique, `telegram_id` unique where not null.

---

## 6. Таблица `leads`

| Колонка        | Тип         | Описание                              |
|---------------|-------------|---------------------------------------|
| id            | pk          |                                       |
| account_id    | fk          |                                       |
| owner_id      | fk users    | nullable                              |
| company_name  | string      |                                       |
| contact_name  | string      |                                       |
| email         | string      | nullable                              |
| phone         | string      | nullable                              |
| stage         | string      | enum-подобное значение                |
| source        | string      | import / voice / manual / telegram    |
| score         | integer     | 0–100, кэш последнего расчёта         |
| score_version | string      | версия формулы                        |
| metadata      | jsonb       | произвольные поля импорта             |
| last_contacted_at | timestamptz | nullable                        |

Индексы: `account_id`, `stage`, `score`, GIN на `metadata` при поиске.

---

## 7. Таблица `lead_events` (аудит)

| Колонка     | Тип         | Описание                         |
|------------|-------------|----------------------------------|
| id         | pk          |                                  |
| lead_id    | fk          |                                  |
| actor_type | string      | User / System / Bot              |
| actor_id   | bigint      | nullable для System              |
| event_type | string      | stage_changed / note_added / …   |
| payload    | jsonb       | diff, текст заметки, raw intent  |
| created_at | timestamptz |                                  |

---

## 8. Таблица `tasks`

| Колонка      | Тип         | Описание                    |
|-------------|-------------|-----------------------------|
| id          | pk          |                             |
| lead_id     | fk          |                             |
| assignee_id | fk users    | nullable                    |
| title       | string      |                             |
| due_at      | timestamptz | nullable                    |
| status      | string      | open / done / cancelled     |
| created_at  | timestamptz |                             |

---

## 9. Таблица `lead_documents`

| Колонка   | Тип  | Описание              |
|----------|------|-----------------------|
| id       | pk   |                       |
| lead_id  | fk   |                       |
| kind     | string | contract / other    |
| name     | string |                     |

Файл через `ActiveStorage::Attachment`.

---

## 10. Таблица `voice_sessions`

| Колонка          | Тип         | Описание                          |
|-----------------|-------------|-----------------------------------|
| id              | pk          |                                   |
| user_id         | fk          |                                   |
| lead_id         | fk nullable | контекст                          |
| status          | string      | recording / processing / done / error |
| transcript      | text        |                                   |
| raw_llm_request | jsonb       | опционально, без секретов         |
| raw_llm_response| jsonb       |                                   |
| error_message   | text        |                                   |
| created_at      | timestamptz |                                   |

Политика хранения аудио — отдельное хранилище с TTL; ссылка `audio_blob_key` опционально.

---

## 11. Таблица `pending_actions`

Очередь на подтверждение человеком.

| Колонка      | Тип         | Описание                    |
|-------------|-------------|-----------------------------|
| id          | pk          |                             |
| user_id     | fk          | кто должен approve          |
| lead_id     | fk          |                             |
| action_type | string      | delete_lead / mass_email / … |
| payload     | jsonb       | параметры                   |
| status      | string      | pending / approved / rejected |
| created_at  | timestamptz |                             |
| resolved_at | timestamptz | nullable                    |

---

## 12. Таблица `import_batches`

| Колонка       | Тип         | Описание                 |
|--------------|-------------|--------------------------|
| id           | pk          |                          |
| account_id   | fk          |                          |
| user_id      | fk          | кто загрузил             |
| filename     | string      |                          |
| status       | string      | pending / processed / failed |
| row_count    | integer     |                          |
| error_report | jsonb       | строки с ошибками        |
| created_at   | timestamptz |                          |

---

## 13. Таблица `crm_id_mappings`

Для стыка с внешней CRM.

| Колонка        | Тип    | Описание              |
|---------------|--------|-----------------------|
| id            | pk     |                       |
| account_id    | fk     |                       |
| external_system | string | bitrix / custom     |
| external_id   | string |                       |
| lead_id       | fk     |                       |
| last_synced_at | timestamptz |                  |

Unique `(account_id, external_system, external_id)`.

---

## 14. Таблица `lead_scores` (история скоринга)

| Колонка      | Тип         | Описание              |
|-------------|-------------|-----------------------|
| id          | pk          |                       |
| lead_id     | fk          |                       |
| score       | integer     |                       |
| breakdown   | jsonb       | веса факторов         |
| computed_at | timestamptz |                       |

---

## 15. Таблица `knowledge_chunks` (Phase 2, RAG)

| Колонка     | Тип     | Описание           |
|------------|---------|--------------------|
| id         | pk      |                    |
| account_id | fk      |                    |
| document_id| fk      | ссылка на источник |
| content    | text    |                    |
| embedding  | vector  | pgvector           |
| metadata   | jsonb   | page, offset       |

Индекс ivfflat/hnsw по `embedding`.

---

## 16. Скоринг v0 (логика в коде)

Факторы (пример):

- Близость к **ICP** (отрасль, размер — из metadata).
- **Стадия** воронки (веса по таблице).
- **Свежесть** последнего касания.
- **Полнота** данных (email, телефон, документы).
- **Негативные** сигналы (стоп-слова в заметках — осторожно, bias).

Формула хранится в коде + `score_version` на лиде для пересчёта истории.

---

## 17. Импорт Excel/CSV

Маппинг колонок → поля `leads` + `metadata` для неизвестных колонок.

Валидации:

- email формат (если есть).
- телефон нормализация (libphonenumber).

Дубликаты: правило `account_id + email` или `account_id + phone` — настраиваемо.

---

## 18. Enums (стадии)

Рекомендуемый набор v0:

`new`, `qualified`, `proposal`, `negotiation`, `won`, `lost`

Хранение string + check constraint или Rails enum.

---

## 19. Связь с Telegram

`users.telegram_id` + при входящем сообщении резолв лида по последнему контексту или команде `/lead UUID`.

---

## 20. Миграции и версии

Каждое изменение схемы — миграция + обновление этого документа.

---

## 21. Резервное копирование

pg_dump стратегия — см. RUNBOOK.md.

---

## 22. Права на уровне строк (будущее)

`account_id` обязателен в scope всех запросов.

---

## 23. Шифрование at-rest

На уровне диска провайдера + опционально encrypted columns для PII.

---

## 24. Поля GDPR

`consent_marketing_at`, `data_processing_basis` на лиде при необходимости.

---

## 25. Расширение метаданных

`metadata` не должен подменять нормализованные поля без миграции.

---

## 26. Счётчики агрегатов

Кэш `leads_count` на account — опционально materialized view.

---

## 27. Временные ряды

Для аналитики событий — возможен экспорт в warehouse позже.

---

## 28. Удаление данных

Job `PurgeOldVoiceArtifactsJob` по политике retention.

---

## 29. Тестовые данные

Seeds создают account demo + пользователей без реальных PII.

---

## 30. Индексы производительности

Частые запросы: список лидов по `account_id` + `stage` + order `updated_at desc`.

---

## 31. Ограничения целостности

FK с `on_delete` осмысленно: tasks cascade при удалении лида или restrict — политика продукта.

---

## 32. Версионирование документов

v1: один файл на тип; v2: версии через отдельную таблицу.

---

## 33. Теги лидов

Таблица `tags`, `lead_tags` join — Phase 2.

---

## 34. Кастомные поля

`metadata` + админка маппинга ключей для импорта.

---

## 35. Синхронизация score

Триггер в коде после `LeadEvent` определённых типов.

---

## 36. Idempotency imports

`import_batches` + хеш файла предотвращает дубль загрузки (опционально).

---

## 37. Audit retention

`lead_events` хранить N лет или архивировать в cold storage.

---

## 38. API tokens

Таблица `api_tokens`: `user_id`, `digest`, `last_used_at`.

---

## 39. Webhooks исходящие

Таблица `webhook_subscriptions` — URL, secret, events[].

---

## 40. Связь User ↔ Lead owner

Смена owner логируется в `lead_events`.

---

## 41. Нормализация телефона

Колонка `phone_e164` для уникальности.

---

## 42. Локализация имён компаний

Одна основная локаль; transliteration в metadata при необходимости.

---

## 43. Ограничения размера JSONB

Мониторинг больших payload; лимит на `raw_llm_*`.

---

## 44. Миграция с внешней CRM

ETL таблица `staging_leads` опционально для сложных маппингов.

---

## 45. Векторный поиск и фильтр

Запрос: embedding + `where account_id = ?`.

---

## 46. Чек-лист новой сущности

Модель, миграция, индексы, policy, factory, документ здесь.

---

## 47. Пример запроса «мои лиды»

`Lead.where(account_id: current_account).order(updated_at: :desc).limit(50)`.

---

## 48. Пример аудита

После `lead.update(stage: ...)`: `LeadEvent.create!(event_type: 'stage_changed', payload: { from:, to: })`.

---

## 49. Будущее: сделки и продукты

Таблицы `deals`, `deal_line_items` — Phase 3+, связь many-to-many с лидами.

---

## 50. Будущее: 3D-абстракция

Сущности `graph_nodes`, `graph_edges` или JSON graph на лиде — отдельный ADR.

---

## 51. Соответствие PRD

Все сущности отражают требования Phase 1–2 из `docs/product/PRD.md`.

---

## 52. ERD визуально

Рекомендуется экспорт из dbdiagram.io или pgAdmin при стабилизации схемы.

---

## 53. Миграции backwards-compatible

Добавлять колонки nullable → backfill → NOT NULL.

---

## 54. Сиды ролей

owner: полный доступ; user: только свои лиды если включено.

---

## 55. Конфликты merge импорта

Стратегия last-write-wins или manual review queue.

---

## 56. Хранение вложений

S3-compatible + checksum для дедупликации.

---

## 57. Связь VoiceSession ↔ LeadEvent

После успешного intent создаётся event `voice_command_applied`.

---

## 58. Таблица настроек скоринга

`scoring_configs` jsonb per account — опционально для no-code tuning.

---

## 59. Заключение

Модель расширяема через `metadata` и отдельные таблицы; критичные пути индексированы.

---

*Обновлять при каждой значимой миграции.*

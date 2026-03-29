# Документация SalesOS

Оглавление основных артефактов. Детали стека и ролей — в подпапках.

## Продукт

| Документ | Описание |
|----------|----------|
| [product/PRD.md](product/PRD.md) | Цели, scope, фазы, NFR, риски, MVP |

## Архитектура и данные

| Документ | Описание |
|----------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Слои, сервисы, потоки данных, Ollama/голос |
| [DATA-MODEL.md](DATA-MODEL.md) | Таблицы, связи, скоринг, стык с CRM |

## API и внешний мир

| Документ | Описание |
|----------|----------|
| [API.md](API.md) | REST, вебхуки, контракты |
| [INTEGRATIONS.md](INTEGRATIONS.md) | Внешние API, ключи, фазы |
| [integrations/OLLAMA-RAILS-INTEGRATION.md](integrations/OLLAMA-RAILS-INTEGRATION.md) | Ollama в Rails: код, порты, локальный запуск |
| [integrations/LOCAL-WHISPER-SETUP.md](integrations/LOCAL-WHISPER-SETUP.md) | Локальный whisper.cpp + ffmpeg, переменные `.env` |

## Эксплуатация и безопасность

| Документ | Описание |
|----------|----------|
| [RUNBOOK.md](RUNBOOK.md) | Деплой, откат, дежурство, инциденты |
| [SECURITY-PRIVACY.md](SECURITY-PRIVACY.md) | Секреты, ПДн, логи, угрозы |

## Решения (ADR)

| Файл | Тема |
|------|------|
| [ADRs/001-rails-monolith-hotwire.md](ADRs/001-rails-monolith-hotwire.md) | Монолит Rails + Hotwire |
| [ADRs/002-postgresql-core-pgvector-optional.md](ADRs/002-postgresql-core-pgvector-optional.md) | PostgreSQL, pgvector |
| [ADRs/003-voice-asr-ollama-intent-router.md](ADRs/003-voice-asr-ollama-intent-router.md) | Голос → ASR → Ollama → intent |
| [ADRs/004-background-jobs-solid-queue-sidekiq.md](ADRs/004-background-jobs-solid-queue-sidekiq.md) | Очереди задач |

## Операционные заметки по ошибкам

| Путь | Назначение |
|------|------------|
| [troubleshooter/README.md](troubleshooter/README.md) | Как вести базу решений |
| [troubleshooter/TEMPLATE.md](troubleshooter/TEMPLATE.md) | Шаблон записи |

## Роли и стек (справочно)

| Папка | Содержание |
|-------|------------|
| [devdep/](devdep/) | Роли, стыковка команды |
| [stack/](stack/) | Технологии: Rails, PostgreSQL, Ollama, Kamal и др. |

## Тесты

| Путь | Назначение |
|------|------------|
| [../test/README.md](../test/README.md) | Все автотесты только в `test/` |
| [../test/TEST_LOG.md](../test/TEST_LOG.md) | Журнал прогонов и итогов |

## Корень репозитория

- [../README.md](../README.md) — быстрый старт
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — правила коммитов и линтера
- [../CHANGELOG.md](../CHANGELOG.md) — история изменений

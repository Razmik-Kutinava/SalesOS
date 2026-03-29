# SalesOS (Omni-Agent)

B2B-ориентированное приложение для работы с лидами и задачами: упор на **выручку**, **голосовой** сценарий (браузер и Telegram), локальный **Ollama** и поэтапный стык с **продакшен CRM**. Регионы и языки: **АМ/РФ**, **RU/EN**.

Подробный продукт и фазы — в [**документации**](docs/README.md).

---

## За 5 минут (локально)

Требования: **Ruby** (см. `.ruby-version`), **PostgreSQL**, опционально **Ollama** и **Whisper** для полного голосового контура.

```bash
git clone <repo-url>
cd SalesOS
bundle install
cp .env.example .env   # опционально: OLLAMA_HOST, OLLAMA_MODEL и др. (dotenv-rails в dev/test)
# Настройте PostgreSQL в config/database.yml при необходимости
bin/rails db:prepare
bin/rails server
```

Откройте `http://localhost:3000`. Вход: `admin@example.com` / `password` (после seed) → откройте лид **Demo Lead** → блок **Голос** (нужны микрофон, Ollama и для реального ASR — Whisper; без Whisper в `.env` можно `VOICE_ASR_STUB=1`).

**Ollama (опционально):** установите [Ollama](https://ollama.com), подтяните модель (`ollama pull …`), задайте `OLLAMA_HOST` / `OLLAMA_MODEL` (см. `docs/INTEGRATIONS.md`).

**Переменные и прод:** см. `docs/RUNBOOK.md` и `docs/INTEGRATIONS.md`.

---

## Документация

| Раздел | Файл |
|--------|------|
| Оглавление docs | [docs/README.md](docs/README.md) |
| PRD (продукт, MVP, риски) | [docs/product/PRD.md](docs/product/PRD.md) |
| Архитектура | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Модель данных | [docs/DATA-MODEL.md](docs/DATA-MODEL.md) |
| API и контракты | [docs/API.md](docs/API.md) |
| Интеграции | [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) |
| Безопасность и ПДн | [docs/SECURITY-PRIVACY.md](docs/SECURITY-PRIVACY.md) |
| Деплой и инциденты | [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| Архитектурные решения (ADR) | [docs/ADRs/](docs/ADRs/) |
| Решения по ошибкам | [docs/troubleshooter/](docs/troubleshooter/) |
| Роли команды | [docs/devdep/](docs/devdep/) |
| Стек технологий | [docs/stack/](docs/stack/) |

---

## Участие и история изменений

- [CONTRIBUTING.md](CONTRIBUTING.md) — ветки, коммиты, RuboCop  
- [CHANGELOG.md](CHANGELOG.md) — список изменений  

---

## Лицензия

Уточните в репозитории при публикации (файл `LICENSE`).

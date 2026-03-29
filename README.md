# SalesOS (Omni-Agent)

B2B-ориентированное приложение для работы с лидами и задачами: упор на **выручку**, **голосовой** сценарий (браузер и Telegram), локальный **Ollama** и поэтапный стык с **продакшен CRM**. Регионы и языки: **АМ/РФ**, **RU/EN**.

Подробности продукта, архитектуры и интеграций ведутся **внутри команды** (локально); в публичном репозитории — только код и шаблоны.

---

## За 5 минут (локально)

Требования: **Ruby** (см. `.ruby-version`), **PostgreSQL**, опционально **Ollama** и **Whisper** для полного голосового контура.

```bash
git clone https://github.com/Razmik-Kutinava/SalesOS.git
cd SalesOS
bundle install
cp .env.example .env   # опционально: OLLAMA_HOST, OLLAMA_MODEL и др. (dotenv-rails в dev/test)
# Настройте PostgreSQL в config/database.yml при необходимости
bin/rails db:prepare
bin/rails server
```

Откройте `http://localhost:3000`. Вход: `admin@example.com` / `password` (после seed) → откройте лид **Demo Lead** → блок **Голос** (нужны микрофон, Ollama и для реального ASR — Whisper; без Whisper в `.env` можно `VOICE_ASR_STUB=1`).

**Ollama (опционально):** установите [Ollama](https://ollama.com), подтяните модель (`ollama pull …`), задайте `OLLAMA_HOST` / `OLLAMA_MODEL` (см. `.env.example` и комментарии в нём).

**Переменные и прод:** см. `.env.example`, `config/deploy.yml`, `Dockerfile`.

---

## Участие и история изменений

- [CONTRIBUTING.md](CONTRIBUTING.md) — ветки, коммиты, RuboCop  
- [CHANGELOG.md](CHANGELOG.md) — список изменений  

---

## Лицензия

См. [LICENSE](LICENSE) (MIT).

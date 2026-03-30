# Playwright fetch worker (SalesOS)

Отдельный процесс **Node.js + Playwright (Chromium)**. Rails вызывает его по HTTP (`Fetch::PlaywrightClient`), не нагружая Puma.

## Запуск локально

```bash
cd playwright-worker
npm install
export ALLOWED_HOSTS=example.com,www.wikipedia.org
export FETCH_TOKEN=dev-secret
node server.mjs
```

Проверка:

```bash
curl -s http://127.0.0.1:3001/health
curl -s -X POST http://127.0.0.1:3001/v1/fetch \
  -H "Authorization: Bearer dev-secret" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
```

## Docker

Из корня репозитория:

```bash
docker compose -f docker-compose.playwright.yml build
docker compose -f docker-compose.playwright.yml up
```

## Переменные

| Переменная | Описание |
|------------|----------|
| `PORT` | Порт HTTP (по умолчанию 3001) |
| `ALLOWED_HOSTS` | Список разрешённых hostname через запятую (**обязателен** для реального использования) |
| `FETCH_TOKEN` | Если задан — заголовок `Authorization: Bearer …` обязателен |

## Безопасность

- Не открывайте воркер в публичный интернет без TLS и сильного токена.
- Список доменов согласуйте с ToS целевых сайтов.

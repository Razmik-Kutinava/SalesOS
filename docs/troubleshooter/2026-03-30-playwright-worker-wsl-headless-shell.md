# Шаблон записи troubleshooter
#
# Troubleshooter: Playwright worker в WSL — нет `headless_shell`
#

---

## Метаданные

- **Дата:** 2026-03-30
- **Окружение:** local (Rails на Windows, worker в WSL)
- **Версия / commit:** (опционально)
- **Теги:** playwright, wsl, rails, fetch

---

## Симптом

- При нажатии в UI вкладки `tab=parse` кнопки «Запросить» запрос к worker не приводит к появлению события `LeadEvent` (типа «Playwright: страница») в истории лида.
- В логах worker падал запуск браузера с ошибкой Playwright вида:
  - `browserType.launch: Executable doesn't exist at /home/<user>/.cache/ms-playwright/chromium_headless_shell-1148/chrome-linux/headless_shell`
- Health проверка worker могла не отвечать (например `curl http://127.0.0.1:3001/health` не проходил), пока worker не взлетел.

---

## Контекст

- Playwright worker (`playwright-worker/server.mjs`) запускали в WSL.
- Ситуация появлялась после установки/обновления Playwright без загрузки browser-бинарей в кеш.
- Rails ходил в worker через `Fetch::PlaywrightClient`, т.е. worker должен быть запущен и иметь скачанные Chromium headless-бинарники.

---

## Диагностика

1. На стороне worker (в WSL) запуск `node server.mjs`:
   - виделась ошибка `Executable doesn't exist ... headless_shell`.
2. Проверка доступности worker:
   - `curl -s http://127.0.0.1:3001/health`
3. Проверка что Rails реально видит env (важно при `.env` правках):
   - `bin/rails runner 'puts ENV["PLAYWRIGHT_FETCH_URL"]; puts ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"].inspect'`
4. Дополнительно на Rails:
   - при `PLAYWRIGHT_FETCH_ALLOWED_HOSTS` без нужного hostname worker отклоняет запрос (см. `Fetch::PlaywrightClient` allowlist).

---

## Причина (root cause)

- В кеш/директории Playwright отсутствовал исполняемый файл `headless_shell`, поэтому Playwright не мог запустить Chromium.
- Worker падал, Rails не получал ответ и/или ловил эффекты разрыва соединения (на практике проявлялось как “ничего не происходит” на UI и/или ошибка в Rails логах).

---

## Решение

Сделали в таком порядке:

1. В WSL перейти в папку worker:
   - `cd /mnt/c/Tools/workarea/SalesOS/playwright-worker`
2. Установить системные зависимости Playwright:
   - `sudo npx playwright install-deps`
3. Скачать Chromium browser-бинарники Playwright (включая `headless_shell`):
   - `npx playwright install chromium`
4. Перезапустить worker с корректными env:
   - пример:
     - `ALLOWED_HOSTS=checko.ru PORT=3001 node server.mjs`
5. Проверить health:
   - `curl -s http://127.0.0.1:3001/health`
6. В Windows/Rails убедиться в env:
   - `PLAYWRIGHT_FETCH_URL` (например `http://127.0.0.1:3001`)
   - `PLAYWRIGHT_FETCH_ALLOWED_HOSTS` (должен включать hostname целевого сайта)
7. Перезапустить Rails после правок `.env`, чтобы dotenv подтянул изменения.
8. Повторно протестировать из UI:
   - вкладка `tab=parse`
   - ввод `https://checko.ru/...`
   - после успешного fetch должен появляться `LeadEvent` `page_fetched` (label «Playwright: страница»).

---

## Профилактика

- Если обновлялся Playwright (или менялась среда worker), перед запуском всегда прогонять:
  - `npx playwright install-deps`
  - `npx playwright install chromium`
- Поддерживать health-чекинг перед тестированием UI.
- Следить за allowlist:
  - `PLAYWRIGHT_FETCH_ALLOWED_HOSTS` должен содержать hostname целевого домена.
- Любые изменения `.env` в Windows — перезапуск `bin/rails s`.

---

## Ссылки

- Документация worker: `playwright-worker/README.md`
- Разделы тестов и UI: `test/TEST_LOG.md` (Playwright worker + UI fetch)


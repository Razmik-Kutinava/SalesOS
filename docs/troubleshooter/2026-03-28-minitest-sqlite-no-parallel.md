# Minitest + SQLite: не использовать parallelize по умолчанию

## Метаданные

- **Дата:** 2026-03-28  
- **Окружение:** test (SQLite `storage/test.sqlite3`)  
- **Теги:** minitest, sqlite, rails, parallelize  

## Симптом

При включённом `parallelize(workers: :number_of_processors, with: :threads)` тесты периодически падают с **`SQLite3::BusyException` / database is locked** (несколько потоков бьют в один файл БД).

## Контекст

Rails по умолчанию генерирует `parallelize` в `test/test_helper.rb`. Для **PostgreSQL** это обычно нормально; для **SQLite** — частый источник флаков.

## Решение

В `test/test_helper.rb` **отключить** параллельный прогон (закомментировать `parallelize` или явно `parallelize(workers: 1)` при проверенной поддержке).

Для ускорения на SQLite альтернативы: перейти на PostgreSQL в test, или in-memory SQLite с осторожностью к воркерам.

## Профилактика

Держать политику в `test/README.md`; при смене БД в CI — пересмотреть настройку.

## Ссылки

- `test/test_helper.rb`  
- `test/README.md`  

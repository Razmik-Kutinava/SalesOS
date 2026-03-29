# RAG: загрузка PDF и текст с консоли (SalesOS)

На главной странице (`/`) в блоке **«База знаний (RAG)»** можно:

1. Задать **вопрос по базе** — `POST /knowledge/query` (JSON), сервис `Knowledge::RagAnswer`: эмбеддинг запроса → `Knowledge::Retriever` (только чанки документов со статусом `ready`) → ответ `OLLAMA_MODEL` **только по переданному контексту**; если релевантных фрагментов нет (или score ниже `RAG_MIN_SCORE`) — текст «нет релевантных фрагментов», без выдумки.
2. **Добавить текст в индекс** (on-the-fly) — форма «Текст в базу» → `POST /knowledge_documents/text`, поле `body_text` в `knowledge_documents`, та же джоба индексации.
3. Загрузить **PDF** с диска: Active Storage, `IndexKnowledgeDocumentJob` извлекает текст (`pdf-reader`), режет на чанки, эмбеддинги **Ollama** (`POST /api/embeddings`) → `knowledge_chunks` (вектор как JSON в SQLite).

**Голос:** интент `add_knowledge` — «добавь в базу знаний», «запомни: …» → создаётся документ с `body_text`, `IndexKnowledgeDocumentJob.perform_later`, опционально `LeadEvent` с типом `knowledge_snippet_voice`.

## Требования

1. **Ollama** запущен, доступен по `OLLAMA_HOST`.
2. Модель эмбеддингов скачана, например:  
   `ollama pull nomic-embed-text`  
   В `.env`: `OLLAMA_EMBED_MODEL=nomic-embed-text` (размерность вектора должна совпадать с моделью).
3. В **production** фоновые воркеры Solid Queue обрабатывают очередь (иначе статус зависнет на `pending` / `processing`).

## Переменные

| Переменная | Назначение |
|------------|------------|
| `OLLAMA_EMBED_MODEL` | Имя модели эмбеддингов в Ollama |
| `RAG_CHUNK_SIZE` | Размер чанка текста (по умолчанию 900) |
| `RAG_CHUNK_OVERLAP` | Перекрытие соседних чанков (по умолчанию 120) |
| `RAG_TOP_K` | Сколько чанков подмешивать в промпт (по умолчанию 5) |
| `RAG_MIN_SCORE` | Порог косинусной близости; ниже — считаем, что контекста нет (по умолчанию 0.12) |
| `OLLAMA_RAG_TEMPERATURE` | Температура ответа в RAG-чате (по умолчанию 0.3) |

## Поиск по базе (программно)

Сервис `Knowledge::Retriever.search(account:, query:, k:)` — косинусная близость по JSON-векторам; учитываются только документы со статусом `ready`. Для ответа пользователю — `Knowledge::RagAnswer.call(account:, question:, ...)`. Для больших объёмов данных планируйте PostgreSQL + pgvector (см. `docs/stack/pgvector.md`).

## Ограничения текущей версии

- PDF **или** текстовая заметка (`body_text`); Word/Excel — позже.
- Скан без текстового слоя даст пустой текст → статус `failed`.

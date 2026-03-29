# OpenAI Whisper API (облачная транскрипция)

Кратко по модели **whisper-1** через HTTP API (обзор для разработчиков: [OpenAI Speech to text](https://platform.openai.com/docs/guides/speech-to-text)). Внешние статьи (например, handbook с `openai.Audio.transcribe`) описывают тот же сервис: ключ API, файл до **~25 МБ**, форматы **webm, wav, mp3, m4a, …**, при необходимости **разбиение длинных записей** на сегменты.

## В SalesOS

При **`ASR_BACKEND=openai`** и заданном **`OPENAI_API_KEY`** сервис **`Asr::WhisperRunner`** отправляет загруженный файл в **`POST https://api.openai.com/v1/audio/transcriptions`** (реализация: `Asr::OpenaiWhisperClient`). Дальше цепочка та же: текст → **Ollama** → **IntentRouter** → БД.

| Переменная | Назначение |
|------------|------------|
| `ASR_BACKEND` | `openai` — облако; иначе локальный whisper.cpp (см. `VOICE-PIPELINE.md`) |
| `OPENAI_API_KEY` | Секретный ключ (не коммитить) |
| `OPENAI_WHISPER_MODEL` | По умолчанию `whisper-1` |
| `OPENAI_WHISPER_READ_TIMEOUT` / `OPENAI_WHISPER_OPEN_TIMEOUT` | Таймауты HTTP (сек) |

## Сравнение с локальным whisper.cpp

| | OpenAI API | Локально (whisper.cpp) |
|---|------------|-------------------------|
| ПДн / сеть | Аудио уходит в OpenAI | На своей машине |
| Стоимость | По тарифу API | Железо + электричество |
| Настройка | Ключ + `ASR_BACKEND` | `WHISPER_BIN`, `WHISPER_MODEL`, часто `ffmpeg` |

## Ограничения API

- Лимит размера файла (ориентир **25 МБ**).
- Качество зависит от шума, акцента, жаргона; нет разделения спикеров в базовом ответе.
- Опционально в API есть **prompt** для подсказки словаря — в текущем клиенте не прокидывается; можно расширить при необходимости.

## Связанные файлы

- `app/services/asr/openai_whisper_client.rb`
- `app/services/asr/whisper_runner.rb`
- `docs/integrations/VOICE-PIPELINE.md`

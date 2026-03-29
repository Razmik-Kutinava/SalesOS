# Локальный whisper.cpp + SalesOS (без OpenAI ASR)

**Ollama** не распознаёт речь — только текст → JSON/интенты. Речь → текст даёт **whisper.cpp** (или OpenAI Whisper API).

Официальный репозиторий: [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp).

## 1. FFmpeg

Браузер шлёт **webm**; Rails конвертирует в **WAV 16 kHz mono** через ffmpeg.

- **Windows:** установи [ffmpeg](https://ffmpeg.org/download.html) или `winget install Gyan.FFmpeg`.
- Архив **исходников** (папка с `configure`, `fftools/ffmpeg.c`) — это **не** готовый `ffmpeg.exe`; нужна **сборка под Windows** или установка через winget.
- Ruby/Puma иногда не видит `ffmpeg` из PATH: задай в `.env` **`FFMPEG_BIN=C:/Users/…/AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe`** (или полный путь к `bin\ffmpeg.exe` из Gyan) и перезапусти сервер.
- В том же окружении, где запускаешь `bin/rails server`, должна работать команда `ffmpeg -version` **или** корректный `FFMPEG_BIN`.

## 2. Сборка whisper.cpp (Windows)

```powershell
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build --config Release -j
```

Исполняемый файл обычно:

- `build\bin\Release\whisper-cli.exe`, или
- `build\bin\whisper-cli.exe`

Проверка: `.\build\bin\Release\whisper-cli.exe -h`

## 3. Модель ggml

В каталоге `whisper.cpp` используй скрипты из `models/` (см. README репозитория), например:

```powershell
# пример — см. models/README.md в whisper.cpp
.\models\download-ggml-model.cmd base
```

Или скачай `.bin` с [Hugging Face ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp).

Для русского языка бери модели **без** суффикса `.en` (например `base`, `small`).

## 4. Переменные в `.env`

```env
ASR_BACKEND=local_whisper
WHISPER_BIN=C:/Tools/whisper.cpp/build/bin/Release/whisper-cli.exe
WHISPER_MODEL=C:/Tools/whisper.cpp/models/ggml-base.bin
WHISPER_LANGUAGE=ru
# FFMPEG_BIN=C:/path/to/ffmpeg.exe

# Чтобы не вызывать OpenAI для ASR — убери или закомментируй:
# OPENAI_API_KEY=
```

Пути с пробелами лучше без кавычек в `.env` (dotenv) или используй короткие пути.

Перезапусти `bin/rails server` после изменений.

## 5. Проверка

```bash
bin/rails voice:check_asr
```

## 6. WSL и Windows

- **Rails на Windows** — пути `WHISPER_*` в формате Windows (`C:/...`) к **whisper-cli.exe**, если собирал под Windows.
- **Rails в WSL** — собери whisper внутри WSL и укажи Linux-пути (`/mnt/c/...` или `/home/.../whisper-cli`).
- **Rails на Windows, whisper собран только в WSL (Linux ELF)** — такой `whisper-cli` нельзя запустить как `.exe`. Варианты:
  1. Собрать `whisper-cli` под Windows (Clang) **или**
  2. Включить мост **`WHISPER_USE_WSL=1`**: Rails вызывает `wsl.exe` с путями `/mnt/c/...`. Пример `.env`:

```env
ASR_BACKEND=local_whisper
VOICE_ASR_STUB=0
OPENAI_API_KEY=
WHISPER_USE_WSL=1
WHISPER_BIN=/mnt/c/Tools/workarea/SalesOS/whisper.cpp/build/bin/whisper-cli
WHISPER_MODEL=C:/Tools/workarea/SalesOS/whisper.cpp/models/ggml-base.bin
WHISPER_LANGUAGE=ru
```

После правок: `bin/rails voice:check_asr` (должны быть OK ffmpeg, `whisper -h` через wsl, файл модели).

Скрипт `models/download-ggml-model.sh` под Windows может иметь CRLF — тогда модель скачай в WSL:  
`curl -L -o models/ggml-base.bin 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'`

Сборка в WSL (чистый каталог `build`, без кэша от MSVC): `rm -rf build && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8`

- Если **Ollama на Windows**, а Rails в WSL — см. `docs/troubleshooter/2026-03-29-wsl-powershell-ollama-localhost.md` для `OLLAMA_HOST`.

## Связанные файлы

- `app/services/asr/whisper_runner.rb`
- `docs/integrations/VOICE-PIPELINE.md`

# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "shellwords"

module Asr
  # Локальный whisper.cpp (или совместимый CLI) либо заглушка VOICE_ASR_STUB для dev.
  # См. docs/integrations/VOICE-PIPELINE.md
  class WhisperRunner
    class Error < StandardError; end
    class ConfigurationError < Error; end

    class << self
      def transcribe(uploaded_path)
        if stub?
          return ENV.fetch("VOICE_ASR_STUB_TEXT", "Добавь заметку: тестовая расшифровка голоса.")
        end

        if openai_asr?
          raise ConfigurationError, "Нужен OPENAI_API_KEY для распознавания через OpenAI Whisper." if ENV["OPENAI_API_KEY"].to_s.strip.blank?

          return Asr::OpenaiWhisperClient.transcribe(uploaded_path)
        end

        raise ConfigurationError, "Задайте WHISPER_BIN и WHISPER_MODEL, или OPENAI_API_KEY (облачный Whisper), или VOICE_ASR_STUB=1." if whisper_bin.blank? || whisper_model.blank?

        Dir.mktmpdir("asr_") do |dir|
          wav = File.join(dir, "input.wav")
          convert_to_wav(uploaded_path, wav)
          txt = run_whisper(wav)
          txt.to_s.strip
        end
      end

      # Явно: VOICE_ASR_STUB=1|true — всегда заглушка; =0|false — не подставлять заглушку в development.
      # В development без whisper/openai автоматически включается заглушка, чтобы UI работал без .env.
      def stub?
        stub_mode?(rails_env: (Rails.env if defined?(Rails)), env: ENV)
      end

      # Для тестов: передать свой env / StringInquirer окружения Rails.
      def stub_mode?(rails_env:, env: ENV)
        v = env["VOICE_ASR_STUB"].to_s.strip
        return true if v == "1" || v.casecmp("true").zero?
        return false if v == "0" || v.casecmp("false").zero?
        return false if openai_asr?(env)
        # Явный выбор локального whisper — не подменять заглушкой в dev (нужны реальные пути или ошибка конфига).
        return false if env["ASR_BACKEND"].to_s.downcase == "local_whisper"
        return false unless rails_env&.development?
        return false if env["WHISPER_BIN"].to_s.strip.present? && env["WHISPER_MODEL"].to_s.strip.present?

        true
      end

      # OpenAI Whisper API: явно ASR_BACKEND=openai или есть OPENAI_API_KEY (кроме принудительно локального whisper).
      def openai_asr?(env = ENV)
        return false if env["ASR_BACKEND"].to_s.downcase == "local_whisper"
        return true if env["ASR_BACKEND"].to_s.downcase == "openai"

        env["OPENAI_API_KEY"].to_s.strip.present?
      end

      def whisper_bin
        ENV["WHISPER_BIN"].to_s.strip
      end

      def whisper_model
        ENV["WHISPER_MODEL"].to_s.strip
      end

      # Для whisper.cpp без WHISPER_LANGUAGE по умолчанию ru — явная русская модель лучше для CRM.
      # OpenAI Whisper API не использует этот флаг (см. OPENAI_WHISPER_LANGUAGE).
      def effective_whisper_language(env = ENV)
        lang = env["WHISPER_LANGUAGE"].to_s.strip
        return lang if lang.present?
        return nil if openai_asr?(env)

        "ru"
      end

      def ffmpeg_bin
        ENV["FFMPEG_BIN"].presence || "ffmpeg"
      end

      # Только на Windows: вызывать бинарник из WSL (собранный в Linux), см. WHISPER_USE_WSL.
      def whisper_use_wsl?
        return false unless Gem.win_platform?

        v = ENV["WHISPER_USE_WSL"].to_s.strip
        v == "1" || v.casecmp("true").zero?
      end

      # Путь к WAV для whisper: на Windows + WHISPER_USE_WSL — в виде /mnt/c/... для argv внутри WSL.
      def wsl_path_for_local_whisper(path)
        return path unless Gem.win_platform?

        p = File.expand_path(path)
        return p.tr("\\", "/") if p.start_with?("/mnt/")

        m = p.match(/\A([A-Za-z]):[\\\/]?(.*)\z/m)
        return p.tr("\\", "/") unless m

        rest = m[2].tr("\\", "/").squeeze("/")
        "/mnt/#{m[1].downcase}/#{rest}"
      end

      # Файл по пути из .env: Windows Ruby не всегда видит /mnt/c/... — проверяем и C:/... .
      def resource_path_exists?(path)
        return true if File.file?(path.to_s)
        return false unless Gem.win_platform?

        m = path.to_s.match(%r{\A/mnt/([a-z])/(.*)\z}i)
        return false unless m

        win = "#{m[1].upcase}:/#{m[2].tr('/', '/')}"
        File.file?(win)
      end

      private

      def convert_to_wav(source, wav_out)
        cmd = [ ffmpeg_bin, "-y", "-i", source, "-ar", "16000", "-ac", "1", wav_out ]
        _run!(cmd, "ffmpeg")
      rescue Error
        # Уже wav или ffmpeg нет — пробуем скопировать
        if File.extname(source).downcase == ".wav"
          FileUtils.cp(source, wav_out)
        else
          raise Error, "Нужен ffmpeg для конвертации #{File.extname(source)} в WAV. Установите ffmpeg или задайте FFMPEG_BIN."
        end
      end

      def run_whisper(wav_path)
        wav_arg = whisper_use_wsl? ? wsl_path_for_local_whisper(wav_path) : wav_path
        model_arg = whisper_use_wsl? ? wsl_path_for_local_whisper(whisper_model) : whisper_model
        cmd =
          if whisper_use_wsl?
            [ "wsl", whisper_bin, "-m", model_arg, "-f", wav_arg, "-otxt" ]
          else
            [ whisper_bin, "-m", whisper_model, "-f", wav_path, "-otxt" ]
          end
        lang = effective_whisper_language
        cmd += [ "-l", lang ] if lang.present?
        _run!(cmd, whisper_use_wsl? ? "wsl whisper" : "whisper")
        txt_file = "#{wav_path}.txt"
        raise Error, "Whisper не создал #{txt_file}" unless File.file?(txt_file)

        File.read(txt_file, encoding: "UTF-8")
      end

      def _run!(argv, label)
        stdout_and_err, status = Open3.capture2e({ "LANG" => "C.UTF-8" }, *argv)
        return if status.success?

        raise Error, "#{label} exit #{status.exitstatus}: #{stdout_and_err[0, 2000]}"
      end
    end
  end
end

# frozen_string_literal: true

require "open3"

module VoiceAsrCheck
  module_function

  def run_cmd_capture(cmd, *args)
    full = [ cmd, *args ]
    out, status = Open3.capture2e({ "LANG" => "C.UTF-8" }, *full)
    [ status.success?, out.to_s ]
  rescue Errno::ENOENT => e
    [ false, e.message ]
  end
end

namespace :voice do
  desc "Проверить ASR: ffmpeg, whisper.cpp (если задан), переменные .env"
  task check_asr: :environment do
    puts "=== SalesOS: проверка голосового ASR ==="
    puts "Rails.env: #{Rails.env}"
    puts ""

    ffmpeg = ENV["FFMPEG_BIN"].presence || "ffmpeg"
    puts "FFmpeg (#{ffmpeg}):"
    ok_ff, out_ff = VoiceAsrCheck.run_cmd_capture(ffmpeg, "-version")
    puts ok_ff ? "  OK — #{out_ff.lines.first&.strip}" : "  ОШИБКА — #{out_ff[0, 500]}"

    bin = ENV["WHISPER_BIN"].to_s.strip
    model = ENV["WHISPER_MODEL"].to_s.strip
    asr_local = ENV["ASR_BACKEND"].to_s.downcase == "local_whisper"
    openai = ENV["OPENAI_API_KEY"].to_s.strip.present? && !asr_local

    puts ""
    puts "OPENAI_API_KEY: #{openai ? 'задан (облачный Whisper, если не local_whisper)' : 'пусто'}"
    puts "ASR_BACKEND: #{ENV['ASR_BACKEND'].presence || '(не задан)'}"
    puts "WHISPER_USE_WSL: #{ENV['WHISPER_USE_WSL'].presence || '(не задан; локальный whisper без wsl.exe)'}"
    puts ""

    if bin.present?
      puts "WHISPER_BIN: #{bin}"
      wsl_asr = Gem.win_platform? && %w[1 true].include?(ENV["WHISPER_USE_WSL"].to_s.strip.downcase)
      ok_w, out_w =
        if wsl_asr
          VoiceAsrCheck.run_cmd_capture("wsl", bin, "-h")
        else
          VoiceAsrCheck.run_cmd_capture(bin, "-h")
        end
      puts ok_w ? "  OK — whisper отвечает на -h#{wsl_asr ? ' (через wsl)' : ''}" : "  ОШИБКА — #{out_w[0, 800]}"
    else
      puts "WHISPER_BIN: не задан (локальный whisper.cpp не используется)"
    end

    if model.present?
      exists = Asr::WhisperRunner.resource_path_exists?(model)
      puts "WHISPER_MODEL: #{model}"
      puts exists ? "  OK — файл есть" : "  ОШИБКА — файл не найден"
    else
      puts "WHISPER_MODEL: не задан"
    end

    puts ""
    stub = Asr::WhisperRunner.stub_mode?(rails_env: Rails.env, env: ENV)
    puts "Режим заглушки ASR (stub): #{stub ? 'да' : 'нет'}"
    eff = Asr::WhisperRunner.effective_whisper_language(ENV)
    puts "WHISPER_LANGUAGE (эффективный для whisper.cpp): #{eff.presence || '(не задан — для openai ASR не используется)'}"

    puts ""
    puts "Подробно: docs/integrations/LOCAL-WHISPER-SETUP.md"
  end
end

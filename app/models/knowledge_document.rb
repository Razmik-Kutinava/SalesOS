# frozen_string_literal: true

class KnowledgeDocument < ApplicationRecord
  STATUSES = %w[pending processing ready failed].freeze
  MIN_BODY_TEXT = 10
  MAX_BODY_TEXT = 500_000
  MAX_PDF_BYTES = 25.megabytes

  belongs_to :account
  has_many :knowledge_chunks, dependent: :delete_all

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validates :body_text, length: { maximum: MAX_BODY_TEXT }, allow_blank: true

  validate :source_payload, on: :create

  def display_title
    return title.presence if title.present?
    return "#{body_text.to_s.strip[0, 48]}…" if body_text.present? && body_text.length > 50
    return body_text.to_s.strip.presence if body_text.present?

    file&.filename&.to_s.presence || "Документ ##{id}"
  end

  def text_source?
    body_text.present?
  end

  private

  def source_payload
    text_len = body_text.to_s.strip.length
    text_ok = text_len >= MIN_BODY_TEXT
    file_present = file.attached?

    if text_ok && file_present
      errors.add(:base, "Укажите либо PDF, либо текст — не оба варианта одновременно.")
      return
    end

    if file_present
      unless file.content_type == "application/pdf"
        errors.add(:file, "пока поддерживается только PDF")
        return
      end

      if file.byte_size > MAX_PDF_BYTES
        errors.add(:file, "слишком большой (макс. 25 МБ)")
      end
      return
    end

    return if text_ok

    errors.add(:base, "Нужен PDF-файл или текстовая заметка (от #{MIN_BODY_TEXT} символов).")
  end
end

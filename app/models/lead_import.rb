# frozen_string_literal: true

# Загрузка Excel/CSV → разбор строк → создание лидов с source: import.
# Файл в Active Storage; обработка — ProcessLeadImportJob (Solid Queue в production).
class LeadImport < ApplicationRecord
  STATUSES = %w[pending queued processing completed failed].freeze

  belongs_to :account
  belongs_to :user

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validate :file_must_be_attached, on: :create

  scope :recent_first, -> { order(created_at: :desc) }

  def file_must_be_attached
    errors.add(:file, "нужно прикрепить файл") unless file.attached?
  end
end

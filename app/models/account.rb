class Account < ApplicationRecord
  has_many :users, dependent: :restrict_with_exception
  has_many :leads, dependent: :restrict_with_exception
  has_many :knowledge_documents, dependent: :destroy
  has_many :lead_imports, dependent: :destroy

  validates :name, presence: true
end

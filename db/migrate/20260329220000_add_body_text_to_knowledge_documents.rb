# frozen_string_literal: true

class AddBodyTextToKnowledgeDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_documents, :body_text, :text
  end
end

# frozen_string_literal: true

class CreateKnowledgeDocumentsAndChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.timestamps
    end

    create_table :knowledge_chunks do |t|
      t.references :knowledge_document, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :chunk_index, null: false
      t.text :content, null: false
      t.text :embedding_json, null: false
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :knowledge_chunks, [ :account_id, :knowledge_document_id ], name: "index_knowledge_chunks_on_account_and_doc"
  end
end

# frozen_string_literal: true

class CreateLeadImports < ActiveRecord::Migration[8.1]
  def change
    create_table :lead_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.json :column_mapping, null: false, default: {}
      t.json :preview_headers, null: false, default: []
      t.json :result_summary, null: false, default: {}
      t.text :error_message
      t.boolean :llm_mapping_used, null: false, default: false
      t.timestamps
    end

    add_index :lead_imports, [ :account_id, :created_at ]
  end
end

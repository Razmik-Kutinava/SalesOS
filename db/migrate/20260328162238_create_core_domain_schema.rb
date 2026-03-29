class CreateCoreDomainSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.json :settings, null: false, default: {}
      t.timestamps
    end

    create_table :users do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "user"
      t.bigint :telegram_id
      t.string :locale, null: false, default: "ru"
      t.string :timezone, null: false, default: "UTC"
      t.timestamps
    end
    add_index :users, [ :account_id, :email ], unique: true
    add_index :users, :telegram_id, unique: true, where: "telegram_id IS NOT NULL"

    create_table :leads do |t|
      t.references :account, null: false, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.string :company_name
      t.string :contact_name
      t.string :email
      t.string :phone
      t.string :stage, null: false, default: "new"
      t.string :source, null: false, default: "manual"
      t.integer :score, null: false, default: 0
      t.string :score_version
      t.json :metadata, null: false, default: {}
      t.datetime :last_contacted_at
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :leads, [ :account_id, :stage ]
    add_index :leads, [ :account_id, :updated_at ]
    add_index :leads, :score

    create_table :lead_events do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :actor_type
      t.bigint :actor_id
      t.string :event_type, null: false
      t.json :payload, null: false, default: {}
      t.timestamps
    end
    add_index :lead_events, [ :lead_id, :created_at ]

    create_table :tasks do |t|
      t.references :lead, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.datetime :due_at
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :tasks, [ :lead_id, :status ]

    create_table :lead_documents do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :kind, null: false, default: "other"
      t.string :name, null: false
      t.timestamps
    end

    create_table :voice_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lead, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :transcript
      t.json :raw_llm_request
      t.json :raw_llm_response
      t.text :error_message
      t.timestamps
    end
    add_index :voice_sessions, [ :user_id, :created_at ]

    create_table :pending_actions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.string :action_type, null: false
      t.json :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :pending_actions, [ :user_id, :status ]
  end
end

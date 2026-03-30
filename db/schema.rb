# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_29_233000) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "settings", default: {}, null: false
    t.datetime "updated_at", null: false
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "knowledge_chunks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "embedding_json", null: false
    t.integer "knowledge_document_id", null: false
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["account_id", "knowledge_document_id"], name: "index_knowledge_chunks_on_account_and_doc"
    t.index ["account_id"], name: "index_knowledge_chunks_on_account_id"
    t.index ["knowledge_document_id"], name: "index_knowledge_chunks_on_knowledge_document_id"
  end

  create_table "knowledge_documents", force: :cascade do |t|
    t.integer "account_id", null: false
    t.text "body_text"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "status", default: "pending", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_knowledge_documents_on_account_id"
  end

  create_table "lead_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "other", null: false
    t.integer "lead_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_lead_documents_on_lead_id"
  end

  create_table "lead_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "lead_id", null: false
    t.json "payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id", "created_at"], name: "index_lead_events_on_lead_id_and_created_at"
    t.index ["lead_id"], name: "index_lead_events_on_lead_id"
  end

  create_table "lead_imports", force: :cascade do |t|
    t.integer "account_id", null: false
    t.json "column_mapping", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.boolean "llm_mapping_used", default: false, null: false
    t.json "preview_headers", default: [], null: false
    t.json "result_summary", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["account_id", "created_at"], name: "index_lead_imports_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_lead_imports_on_account_id"
    t.index ["user_id"], name: "index_lead_imports_on_user_id"
  end

  create_table "leads", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "company_name"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "email"
    t.datetime "last_contacted_at"
    t.json "metadata", default: {}, null: false
    t.datetime "next_call_at"
    t.integer "owner_id"
    t.string "phone"
    t.integer "score", default: 0, null: false
    t.string "score_version"
    t.string "source", default: "manual", null: false
    t.string "stage", default: "new", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "stage"], name: "index_leads_on_account_id_and_stage"
    t.index ["account_id", "updated_at"], name: "index_leads_on_account_id_and_updated_at"
    t.index ["account_id"], name: "index_leads_on_account_id"
    t.index ["owner_id"], name: "index_leads_on_owner_id"
    t.index ["score"], name: "index_leads_on_score"
  end

  create_table "pending_actions", force: :cascade do |t|
    t.string "action_type", null: false
    t.datetime "created_at", null: false
    t.integer "lead_id", null: false
    t.json "payload", default: {}, null: false
    t.datetime "resolved_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["lead_id"], name: "index_pending_actions_on_lead_id"
    t.index ["user_id", "status"], name: "index_pending_actions_on_user_id_and_status"
    t.index ["user_id"], name: "index_pending_actions_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "assignee_id"
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.integer "lead_id", null: false
    t.string "status", default: "open", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_tasks_on_assignee_id"
    t.index ["lead_id", "status"], name: "index_tasks_on_lead_id_and_status"
    t.index ["lead_id"], name: "index_tasks_on_lead_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "locale", default: "ru", null: false
    t.string "password_digest", null: false
    t.string "role", default: "user", null: false
    t.bigint "telegram_id"
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_users_on_account_id_and_email", unique: true
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["telegram_id"], name: "index_users_on_telegram_id", unique: true, where: "telegram_id IS NOT NULL"
  end

  create_table "voice_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "lead_id"
    t.json "raw_llm_request"
    t.json "raw_llm_response"
    t.string "status", default: "pending", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["lead_id"], name: "index_voice_sessions_on_lead_id"
    t.index ["user_id", "created_at"], name: "index_voice_sessions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_voice_sessions_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "knowledge_chunks", "accounts"
  add_foreign_key "knowledge_chunks", "knowledge_documents"
  add_foreign_key "knowledge_documents", "accounts"
  add_foreign_key "lead_documents", "leads"
  add_foreign_key "lead_events", "leads"
  add_foreign_key "lead_imports", "accounts"
  add_foreign_key "lead_imports", "users"
  add_foreign_key "leads", "accounts"
  add_foreign_key "leads", "users", column: "owner_id"
  add_foreign_key "pending_actions", "leads"
  add_foreign_key "pending_actions", "users"
  add_foreign_key "tasks", "leads"
  add_foreign_key "tasks", "users", column: "assignee_id"
  add_foreign_key "users", "accounts"
  add_foreign_key "voice_sessions", "leads"
  add_foreign_key "voice_sessions", "users"
end

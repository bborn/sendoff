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

ActiveRecord::Schema[8.1].define(version: 2026_06_01_000012) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "sendoff_audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.text "detail"
    t.uuid "email_account_id"
    t.string "recipient"
    t.uuid "subject_id"
    t.string "subject_type"
    t.index ["action"], name: "index_sendoff_audit_logs_on_action"
    t.index ["actor"], name: "index_sendoff_audit_logs_on_actor"
    t.index ["created_at"], name: "index_sendoff_audit_logs_on_created_at"
    t.index ["email_account_id"], name: "index_sendoff_audit_logs_on_email_account_id"
    t.index ["subject_type", "subject_id"], name: "index_sendoff_audit_logs_on_subject_type_and_subject_id"
  end

  create_table "sendoff_companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "categories", default: [], array: true
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.string "name", null: false
    t.text "notes_md"
    t.string "segment"
    t.string "segment_source"
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_sendoff_companies_on_domain", unique: true
    t.index ["segment"], name: "index_sendoff_companies_on_segment"
  end

  create_table "sendoff_competitor_domains", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "added_by"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_sendoff_competitor_domains_on_domain", unique: true
  end

  create_table "sendoff_drafts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "bcc_addr"
    t.text "body_html", null: false
    t.string "cc_addr"
    t.text "context_summary_json"
    t.datetime "created_at", null: false
    t.uuid "email_account_id"
    t.jsonb "flagged_claims"
    t.string "gmail_draft_id"
    t.string "gmail_thread_id"
    t.boolean "human_edited", default: false, null: false
    t.string "intent"
    t.uuid "lead_id", null: false
    t.string "name_confidence"
    t.text "original_body_html"
    t.text "original_subject"
    t.uuid "pipeline_entry_id"
    t.text "prompt_used"
    t.text "raw_response"
    t.datetime "scheduled_at"
    t.string "send_job_id"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.string "subject", null: false
    t.string "to_addr", null: false
    t.datetime "updated_at", null: false
    t.index ["email_account_id"], name: "index_sendoff_drafts_on_email_account_id"
    t.index ["lead_id"], name: "index_sendoff_drafts_on_lead_id"
    t.index ["pipeline_entry_id"], name: "index_sendoff_drafts_on_pipeline_entry_id"
    t.index ["scheduled_at"], name: "index_sendoff_drafts_on_scheduled_at"
    t.index ["status"], name: "index_sendoff_drafts_on_status"
  end

  create_table "sendoff_email_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "oauth_client_id"
    t.string "oauth_client_secret"
    t.string "oauth_refresh_token"
    t.string "role", default: "outreach"
    t.text "signature_html"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_sendoff_email_accounts_on_email", unique: true
  end

  create_table "sendoff_email_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "bcc_addrs", default: [], array: true
    t.text "body_html"
    t.text "body_text"
    t.string "cc_addrs", default: [], array: true
    t.uuid "company_id"
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.uuid "email_account_id"
    t.string "from_addr", null: false
    t.string "gmail_message_id"
    t.string "gmail_thread_id"
    t.uuid "lead_id"
    t.datetime "sent_at", null: false
    t.string "subject"
    t.string "to_addrs", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_sendoff_email_events_on_company_id"
    t.index ["email_account_id"], name: "index_sendoff_email_events_on_email_account_id"
    t.index ["gmail_message_id"], name: "index_sendoff_email_events_on_gmail_message_id", unique: true
    t.index ["gmail_thread_id"], name: "index_sendoff_email_events_on_gmail_thread_id"
    t.index ["lead_id"], name: "index_sendoff_email_events_on_lead_id"
    t.index ["sent_at"], name: "index_sendoff_email_events_on_sent_at"
  end

  create_table "sendoff_hidden_leads", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hidden_by"
    t.uuid "lead_id", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_sendoff_hidden_leads_on_lead_id"
    t.index ["lead_id"], name: "index_sendoff_hidden_leads_on_lead_id_unique", unique: true
  end

  create_table "sendoff_leads", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "full_name"
    t.string "last_name"
    t.string "name_source"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_sendoff_leads_on_company_id"
    t.index ["email"], name: "index_sendoff_leads_on_email", unique: true
  end

  create_table "sendoff_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "author"
    t.text "body_md", null: false
    t.datetime "created_at", null: false
    t.uuid "notable_id", null: false
    t.string "notable_type", null: false
    t.string "source"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["notable_type", "notable_id"], name: "index_sendoff_notes_on_notable_type_and_notable_id"
  end

  create_table "sendoff_pipeline_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "claimed_until"
    t.uuid "company_id", null: false
    t.datetime "created_at", null: false
    t.date "last_report_view"
    t.uuid "lead_id", null: false
    t.datetime "queued_at"
    t.integer "reports_viewed", default: 0, null: false
    t.jsonb "signals", default: {}, null: false
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.integer "warm_score", default: 0, null: false
    t.index ["claimed_until"], name: "index_sendoff_pipeline_entries_on_claimed_until"
    t.index ["company_id", "lead_id"], name: "index_sendoff_pipeline_entries_on_company_id_and_lead_id"
    t.index ["company_id"], name: "index_sendoff_pipeline_entries_on_company_id"
    t.index ["lead_id"], name: "index_sendoff_pipeline_entries_on_lead_id"
    t.index ["lead_id"], name: "index_sendoff_pipeline_entries_on_lead_id_unique", unique: true
    t.index ["stage"], name: "index_sendoff_pipeline_entries_on_stage"
  end

  create_table "sendoff_voice_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "created_by"
    t.text "raw_feedback"
    t.text "rule", null: false
    t.string "scope", null: false
    t.string "source_draft_subject"
    t.string "source_recipient"
    t.datetime "updated_at", null: false
    t.index ["scope", "active"], name: "index_sendoff_voice_rules_on_scope_and_active"
  end

  add_foreign_key "sendoff_audit_logs", "sendoff_email_accounts", column: "email_account_id"
  add_foreign_key "sendoff_drafts", "sendoff_email_accounts", column: "email_account_id"
  add_foreign_key "sendoff_drafts", "sendoff_leads", column: "lead_id"
  add_foreign_key "sendoff_drafts", "sendoff_pipeline_entries", column: "pipeline_entry_id"
  add_foreign_key "sendoff_email_events", "sendoff_companies", column: "company_id"
  add_foreign_key "sendoff_email_events", "sendoff_email_accounts", column: "email_account_id"
  add_foreign_key "sendoff_email_events", "sendoff_leads", column: "lead_id"
  add_foreign_key "sendoff_hidden_leads", "sendoff_leads", column: "lead_id"
  add_foreign_key "sendoff_leads", "sendoff_companies", column: "company_id"
  add_foreign_key "sendoff_pipeline_entries", "sendoff_companies", column: "company_id"
  add_foreign_key "sendoff_pipeline_entries", "sendoff_leads", column: "lead_id"
end

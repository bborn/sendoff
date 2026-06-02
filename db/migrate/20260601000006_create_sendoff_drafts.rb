class CreateSendoffDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_drafts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :lead, null: false, type: :uuid,
                          foreign_key: { to_table: :sendoff_leads }
      t.references :pipeline_entry, type: :uuid,
                                    foreign_key: { to_table: :sendoff_pipeline_entries }
      t.references :email_account, type: :uuid,
                                   foreign_key: { to_table: :sendoff_email_accounts }
      t.string :to_addr, null: false
      t.string :cc_addr
      t.string :bcc_addr
      t.string :subject, null: false
      t.text :body_html, null: false
      t.string :gmail_draft_id
      t.string :gmail_thread_id
      t.string :status, default: "pending", null: false
      t.string :intent
      t.string :name_confidence
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.string :send_job_id
      t.text :context_summary_json
      t.text :prompt_used
      t.text :raw_response
      t.text :original_subject
      t.text :original_body_html
      t.boolean :human_edited, default: false, null: false
      t.jsonb :flagged_claims

      t.timestamps
    end

    add_index :sendoff_drafts, :status
    add_index :sendoff_drafts, :scheduled_at
  end
end

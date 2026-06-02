class CreateSendoffPipelineEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_pipeline_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :lead, null: false, type: :uuid,
                          foreign_key: { to_table: :sendoff_leads }
      t.references :company, null: false, type: :uuid,
                             foreign_key: { to_table: :sendoff_companies }
      t.string :stage, null: false
      # Generic warmth indicators (replaces IK-specific has_flex_account/flex_url).
      t.jsonb :signals, default: {}, null: false
      t.integer :reports_viewed, default: 0, null: false
      t.date :last_report_view
      t.integer :warm_score, default: 0, null: false
      t.datetime :queued_at
      t.datetime :claimed_until

      t.timestamps
    end

    add_index :sendoff_pipeline_entries, :lead_id, unique: true,
              name: "index_sendoff_pipeline_entries_on_lead_id_unique"
    add_index :sendoff_pipeline_entries, [ :company_id, :lead_id ]
    add_index :sendoff_pipeline_entries, :stage
    add_index :sendoff_pipeline_entries, :claimed_until
  end
end

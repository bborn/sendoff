class CreateSendoffVoiceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_voice_rules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :scope, null: false
      t.text :rule, null: false
      t.text :raw_feedback
      t.string :source_draft_subject
      t.string :source_recipient
      t.string :created_by
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :sendoff_voice_rules, [ :scope, :active ]
  end
end

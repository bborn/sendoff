class CreateSendoffAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_audit_logs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :actor, null: false
      t.string :action, null: false
      t.string :subject_type
      t.uuid :subject_id
      t.string :recipient
      t.text :detail
      t.references :email_account, type: :uuid,
                                   foreign_key: { to_table: :sendoff_email_accounts }

      t.datetime :created_at, default: -> { "now()" }, null: false
    end

    add_index :sendoff_audit_logs, :action
    add_index :sendoff_audit_logs, :actor
    add_index :sendoff_audit_logs, :created_at
    add_index :sendoff_audit_logs, [ :subject_type, :subject_id ]
  end
end

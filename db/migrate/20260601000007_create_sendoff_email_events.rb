class CreateSendoffEmailEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_email_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :lead, type: :uuid,
                          foreign_key: { to_table: :sendoff_leads }
      t.references :company, type: :uuid,
                             foreign_key: { to_table: :sendoff_companies }
      t.references :email_account, type: :uuid,
                                   foreign_key: { to_table: :sendoff_email_accounts }
      t.string :direction, null: false
      t.string :gmail_message_id
      t.string :gmail_thread_id
      t.string :from_addr, null: false
      t.string :to_addrs, default: [], array: true
      t.string :cc_addrs, default: [], array: true
      t.string :bcc_addrs, default: [], array: true
      t.string :subject
      t.text :body_text
      t.text :body_html
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :sendoff_email_events, :gmail_message_id, unique: true
    add_index :sendoff_email_events, :gmail_thread_id
    add_index :sendoff_email_events, :sent_at
  end
end

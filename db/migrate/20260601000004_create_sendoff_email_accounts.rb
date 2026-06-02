class CreateSendoffEmailAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_email_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :email, null: false
      t.string :display_name, null: false
      t.string :first_name
      t.text :signature_html
      t.string :oauth_refresh_token
      t.string :oauth_client_id
      t.string :oauth_client_secret
      t.boolean :active, default: true, null: false
      t.string :role, default: "outreach"

      t.timestamps
    end

    add_index :sendoff_email_accounts, :email, unique: true
  end
end

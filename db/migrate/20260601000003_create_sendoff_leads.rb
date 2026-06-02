class CreateSendoffLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_leads, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, type: :uuid,
                             foreign_key: { to_table: :sendoff_companies }
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :full_name
      t.string :name_source
      t.string :role

      t.timestamps
    end

    add_index :sendoff_leads, :email, unique: true
  end
end

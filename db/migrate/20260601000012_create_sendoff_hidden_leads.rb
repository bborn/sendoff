class CreateSendoffHiddenLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_hidden_leads, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :lead, null: false, type: :uuid,
                          foreign_key: { to_table: :sendoff_leads }
      t.string :hidden_by
      t.text :reason

      t.timestamps
    end

    add_index :sendoff_hidden_leads, :lead_id, unique: true,
              name: "index_sendoff_hidden_leads_on_lead_id_unique"
  end
end

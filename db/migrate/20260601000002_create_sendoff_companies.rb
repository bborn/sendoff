class CreateSendoffCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_companies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :domain, null: false
      t.string :subdomain
      t.string :segment
      t.string :segment_source
      t.text :categories, default: [], array: true
      t.text :notes_md

      t.timestamps
    end

    add_index :sendoff_companies, :domain, unique: true
    add_index :sendoff_companies, :segment
  end
end

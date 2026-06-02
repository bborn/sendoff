class CreateSendoffCompetitorDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_competitor_domains, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :domain, null: false
      t.string :category, null: false
      t.text :reason
      t.string :added_by

      t.timestamps
    end

    add_index :sendoff_competitor_domains, :domain, unique: true
  end
end

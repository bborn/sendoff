class CreateSendoffNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :sendoff_notes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :notable_type, null: false
      t.uuid :notable_id, null: false
      t.string :title
      t.text :body_md, null: false
      t.string :author
      t.string :source

      t.timestamps
    end

    add_index :sendoff_notes, [ :notable_type, :notable_id ]
  end
end

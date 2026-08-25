class CreateMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :memories do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :source_conversation, null: true, foreign_key: { to_table: :conversations }

      t.text :content, null: false
      t.string :category
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :memories, [ :organization_id, :active ], where: "active"
  end
end

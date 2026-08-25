class CreateInitiatives < ActiveRecord::Migration[8.1]
  def change
    create_table :initiatives do |t|
      t.references :goal, null: false, foreign_key: true
      t.references :owner, null: true, foreign_key: { to_table: :users }

      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "proposed"

      t.timestamps
    end
  end
end

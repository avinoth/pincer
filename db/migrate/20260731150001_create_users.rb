class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.references :organization, null: false, foreign_key: true
      t.string :provider_uid, null: false
      t.string :full_name, null: false
      t.string :time_zone, null: false
      t.string :role, null: false
      t.jsonb :images

      t.timestamps
    end

    add_index :users, :created_at
    add_index :users, [ :organization_id, :provider_uid ], unique: true
  end
end

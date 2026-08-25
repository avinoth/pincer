class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.string :status, null: false
      t.string :time_zone, null: false
      t.bigint :owner_id # points at users.id; no FK (circular with users.organization_id)
      t.string :email
      t.string :domain
      t.string :users_import_status, null: false, default: "pending"

      t.timestamps
    end
  end
end

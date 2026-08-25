class CreateGoalOwners < ActiveRecord::Migration[8.1]
  def change
    create_table :goal_owners do |t|
      t.references :goal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :goal_owners, [ :goal_id, :user_id ], unique: true
  end
end

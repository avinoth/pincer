class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals do |t|
      t.references :organization, null: false, foreign_key: true
      # Who created the goal — distinct from its owners (goal_owners join table).
      t.references :creator, null: false, foreign_key: { to_table: :users }
      # Self-referential goal hierarchy.
      t.references :parent_goal, null: true, foreign_key: { to_table: :goals }

      t.string :title, null: false
      t.text :description
      t.date :start_date
      t.date :end_date

      # Slack conversation id the goal broadcasts to.
      t.string :update_channel

      # Weekly summary schedule. Nudge timing is derived from these at scheduling
      # time (a day before + 4h before the summary) rather than stored.
      t.integer :summary_day    # 0=Sunday … 6=Saturday
      t.string :summary_time    # "HH:MM" in the workspace timezone

      t.string :status, null: false, default: "active"
      t.string :health

      t.timestamps
    end

    add_index :goals, :status
  end
end

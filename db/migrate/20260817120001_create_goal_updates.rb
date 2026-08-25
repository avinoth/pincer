class CreateGoalUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :goal_updates do |t|
      # Usually set (the nudge that prompted this entry); nullable to allow
      # ad-hoc updates with no originating check-in later.
      t.references :checkin, null: true, foreign_key: true

      t.references :goal, null: false, foreign_key: true
      t.references :initiative, null: true, foreign_key: true
      # Attributed to the reporter, who may differ from the goal owner.
      t.references :reported_by, null: false, foreign_key: { to_table: :users }

      t.string :kind, null: false
      t.text :body

      # Set on kind: metric — the MetricUpdate row this log entry narrates.
      t.references :metric_update, null: true, foreign_key: true

      t.timestamps
    end
  end
end

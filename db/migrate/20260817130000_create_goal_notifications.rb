class CreateGoalNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :goal_notifications do |t|
      t.references :goal, null: false, foreign_key: true

      t.string :kind, null: false

      # Recurrence idempotency token, weekly only — start/end are one-time so
      # they don't need one (mirrors Checkin#period_key, but nullable here
      # since only one of the three kinds uses it).
      t.string :period_key

      # Snapshot of Goal#health at generation time (weekly/end only).
      t.string :health

      # The LLM narrative (weekly/end only) — start has none.
      t.text :body

      t.string :slack_channel_id
      t.string :slack_thread_ts
      t.datetime :posted_at

      t.timestamps
    end

    # Dedup, mirroring checkins' partial-index pattern: weekly recurs (keyed
    # by period_key), start/end are one-time per goal (no period_key needed).
    add_index :goal_notifications, [ :goal_id, :kind, :period_key ],
      unique: true, where: "kind = 'weekly'", name: "index_goal_notifications_on_weekly_period"
    add_index :goal_notifications, [ :goal_id, :kind ],
      unique: true, where: "kind IN ('start', 'end')", name: "index_goal_notifications_on_start_end"
  end
end

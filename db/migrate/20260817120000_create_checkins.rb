class CreateCheckins < ActiveRecord::Migration[8.1]
  def change
    create_table :checkins do |t|
      t.references :organization, null: false, foreign_key: true
      # The owner being nudged — not necessarily the goal's creator.
      t.references :user, null: false, foreign_key: true

      t.references :goal, null: false, foreign_key: true
      # Set when the subject is an initiative rather than the goal's metric.
      t.references :initiative, null: true, foreign_key: true

      # Shared across a clubbed batch — several checkins for one owner point at
      # the same outbound DM thread.
      t.string :slack_channel_id
      t.string :slack_thread_ts

      t.datetime :notified_at
      t.datetime :completed_at

      t.string :status, null: false, default: "pending"

      # The localized nudge date (e.g. "2026-08-20") — the idempotency token
      # a scheduler tick upserts against.
      t.string :period_key, null: false

      t.timestamps
    end

    # Dedup: initiative_id is nullable, so one partial unique index per subject
    # shape rather than a single composite index that would ignore NULLs.
    add_index :checkins, [ :goal_id, :user_id, :period_key ],
      unique: true, where: "initiative_id IS NULL", name: "index_checkins_on_metric_subject_period"
    add_index :checkins, [ :goal_id, :user_id, :initiative_id, :period_key ],
      unique: true, where: "initiative_id IS NOT NULL", name: "index_checkins_on_initiative_subject_period"
  end
end

# One row per posted goal-lifecycle notification: the weekly summary, the
# goal-start notice, or the goal-end notice — all posted to
# `goal.update_channel` by GoalSummarySchedulerJob / GoalLifecycleSchedulerJob.
# `period_key` is the recurrence idempotency token, weekly only (start/end are
# one-time per goal, mirroring Checkin's shape). `health`/`body` are the LLM
# narrative snapshot for weekly/end; start has neither (no LLM call). See
# docs/data_model.md.
class GoalNotification < ApplicationRecord
  enum :kind, {
    start: "start",
    weekly: "weekly",
    end: "end"
  }, prefix: "kind"

  # Same enum values as Goal#health — a snapshot at generation time.
  enum :health, {
    on_track: "on_track",
    at_risk: "at_risk",
    off_track: "off_track"
  }, prefix: "health"

  belongs_to :goal
end

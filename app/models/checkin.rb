# One row per (owner x subject x occurrence) — the envelope for a weekly
# check-in nudge. Several checkins for the same owner share one clubbed DM
# thread (slack_channel_id/slack_thread_ts). The subject is either the goal's
# metric (initiative_id nil) or one of the goal's initiatives (initiative_id
# set); period_key is the localized nudge date and doubles as the idempotency
# token a scheduler tick upserts against. See docs/data_model.md.
class Checkin < ApplicationRecord
  enum :status, {
    pending: "pending",
    notified: "notified",
    in_progress: "in_progress",
    completed: "completed",
    skipped: "skipped",
    expired: "expired"
  }, prefix: "status"

  belongs_to :organization
  belongs_to :user
  belongs_to :goal
  belongs_to :initiative, optional: true

  has_many :goal_updates, dependent: :nullify

  validates :period_key, presence: true
end

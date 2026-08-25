# Append-only running log of check-in information: a metric value report, an
# initiative status change, or a free-text note. checkin_id is usually set (the
# nudge that prompted this entry) but nullable to allow ad-hoc updates later
# with no originating check-in. metric_update_id is set on kind: metric,
# pointing at the MetricUpdate row this entry narrates. See docs/data_model.md.
class GoalUpdate < ApplicationRecord
  enum :kind, {
    metric: "metric",
    initiative_status: "initiative_status",
    note: "note"
  }, prefix: "kind"

  belongs_to :checkin, optional: true
  belongs_to :goal
  belongs_to :initiative, optional: true
  belongs_to :reported_by, class_name: "User", optional: true
  belongs_to :metric_update, optional: true

  validates :kind, presence: true
end

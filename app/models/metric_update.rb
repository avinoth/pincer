# An append-only reported value for a Metric. Never mutated or deleted: this is
# the metric time series the timeline, weekly summaries, and trend analysis read.
# Metric#current_value is a denormalized pointer to the latest one. Attributed to
# the reporter, who may differ from the goal owner. See docs/data_model.md.
class MetricUpdate < ApplicationRecord
  belongs_to :metric
  belongs_to :reported_by, class_name: "User", optional: true

  has_one :goal_update, dependent: :nullify

  validates :value, presence: true
end

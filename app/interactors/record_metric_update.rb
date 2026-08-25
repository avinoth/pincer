# Records a new reported value for a Goal's metric: an append-only MetricUpdate,
# Metric#current_value advanced to match, and a GoalUpdate(kind: metric) log
# entry narrating it. All in one transaction so a partial write is never left
# behind. Note: once this runs, the metric's definition (name/direction/target)
# is frozen — the existing "no editing a metric once any MetricUpdate exists"
# rule (see UpdateMetric) — intentional.
#
# Context in:  metric (Metric), value (Decimal-ish), reported_by (User),
#              note (String, optional), checkin (Checkin, optional — the nudge
#              this report answers).
# Context out: metric_update, goal_update, metric
class RecordMetricUpdate
  include Interactor

  def call
    metric = context.metric
    reported_by = context.reported_by

    unless metric&.goal&.modifiable_by?(reported_by&.provider_uid)
      return context.fail!(error: "Only the goal's owners or creator can report a metric value.")
    end

    ActiveRecord::Base.transaction do
      metric_update = metric.metric_updates.create!(
        value: context.value,
        note: context.note.presence,
        reported_by: reported_by,
      )
      metric.update!(current_value: context.value)

      goal_update = GoalUpdate.create!(
        checkin: context.checkin,
        goal: metric.goal,
        reported_by: reported_by,
        kind: :metric,
        metric_update_id: metric_update.id,
        body: "#{metric.name}: #{Metric.format_value(context.value, metric.unit)}#{note_suffix}",
      )

      context.metric_update = metric_update
      context.goal_update = goal_update
      context.metric = metric.reload
    end
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end

  private

  def note_suffix
    context.note.present? ? " — #{context.note}" : ""
  end
end

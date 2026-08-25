# Updates a Goal's primary metric — reached only from the Edit Goal modal, and
# only while the metric is still editable (no MetricUpdate exists yet; see
# Slack::Interactions::EditGoalSubmission). current_value is re-seeded from
# start_value, mirroring CreateMetric — safe here because nothing has been
# reported against the old value yet.
#
# Context in:  metric, name, direction, target_value, start_value (optional),
#              unit (optional)
# Context out: metric
class UpdateMetric
  include Interactor

  def call
    start_value = context.start_value.presence || 0

    context.metric.update!(
      name: context.name,
      direction: context.direction,
      start_value: start_value,
      current_value: start_value,
      target_value: context.target_value,
      unit: context.unit.presence,
    )
  rescue ActiveRecord::RecordInvalid => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end

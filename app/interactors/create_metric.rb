# Persists a Goal's primary metric. current_value seeds to the baseline
# (start_value, or 0 when blank) — no MetricUpdate exists yet; the append-only log
# starts empty and current_value is its denormalized pointer. The unique index on
# metrics.goal_id guards the one-metric-per-goal rule.
#
# Context in:  goal, name, direction, target_value, start_value (optional),
#              unit (optional)
# Context out: metric
class CreateMetric
  include Interactor

  def call
    # Refuse up front rather than relying solely on the unique index: with the
    # has_one association loaded, `build_metric` would silently destroy-and-replace
    # the existing metric (dependent: :destroy) instead of failing.
    return context.fail!(error: "goal already has a metric") if context.goal.metric.present?

    start_value = context.start_value.presence || 0

    metric = context.goal.build_metric(
      name: context.name,
      direction: context.direction,
      start_value: start_value,
      current_value: start_value,
      target_value: context.target_value,
      unit: context.unit.presence,
    )
    metric.save!

    context.metric = metric
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Bugsnag.notify(e)
    context.fail!(error: e.message)
  end
end

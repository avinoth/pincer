# Shared lifecycle-status derivation, used by both CreateGoal (initial status)
# and UpdateGoal (recomputed on edit, since start_date may change). A goal is
# in progress once it has started; before then it's not yet started.
#
# `completed`/`ended` is a separate decision (#outcome_for), evaluated only
# when a goal's end_date actually arrives — GoalLifecycleSchedulerJob is what
# drives that, not every save (a goal sits at whatever status it last had
# until the scheduler reaches its end_date).
module GoalLifecycle
  module_function

  def status_for(start_date)
    return :not_started if start_date.blank?

    start_date.to_date <= Date.current ? :in_progress : :not_started
  end

  # completed if the primary metric's target was reached (direction-aware,
  # reusing the same "reached" check as Metric#remaining_to_target), ended
  # otherwise. A goal with no metric (shouldn't happen for a published goal,
  # but defensively) can't have hit a target, so it's ended.
  def outcome_for(goal)
    metric = goal.metric
    return :ended if metric.nil? || metric.current_value.blank? || metric.target_value.blank?

    reached = metric.direction_decrease? ? metric.current_value <= metric.target_value : metric.current_value >= metric.target_value
    reached ? :completed : :ended
  end
end

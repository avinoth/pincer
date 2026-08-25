# frozen_string_literal: true

# Modal-state field readers shared by CreateGoalSubmission and
# EditGoalSubmission — both handlers parse the same field layout (see
# Slack::Views::MetricFields#metric_input_blocks). Mirrors
# Slack::Interactions::GoalForm. Include into a Slack::Interactions::Base
# subclass that exposes `payload`.
module Slack::Interactions::MetricForm
  private

  def metric_name
    value_at("name_block", "name")
  end

  def metric_direction
    state.dig("direction_block", "direction", "selected_option", "value")
  end

  def metric_start_value
    value_at("start_value_block", "start_value").presence
  end

  def metric_target_value
    value_at("target_value_block", "target_value")
  end

  def metric_unit
    value_at("unit_block", "unit").presence
  end

  # The first blocking validation failure, as a response_action errors hash, or
  # nil when the metric fields are all valid.
  def metric_errors
    return error("name_block", "Please name what to track") if metric_name.blank?
    return error("direction_block", "Pick increase or decrease") if metric_direction.blank?
    return error("target_value_block", "Please set a target value") if metric_target_value.blank?

    nil
  end

  def state
    payload.dig(:view, :state, :values) || {}
  end

  def value_at(block_id, action_id)
    state.dig(block_id, action_id, "value").to_s.strip
  end

  def error(block_id, message)
    { response_action: "errors", errors: { block_id => message } }
  end
end

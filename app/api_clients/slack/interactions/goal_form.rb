# frozen_string_literal: true

# Modal-state field readers shared by CreateGoalSubmission and
# EditGoalSubmission — both handlers parse the same field layout (see
# Slack::Views::CreateGoalModal / EditGoalModal), just apply the parsed values
# differently (CreateGoal vs. UpdateGoal). Include into a
# Slack::Interactions::Base subclass that exposes `payload` and `organization`.
module Slack::Interactions::GoalForm
  private

  def title
    value_at("title_block", "title")
  end

  def description
    value_at("description_block", "description").presence
  end

  def owner_slack_ids
    Array(state.dig("owners_block", "owners", "selected_users"))
  end

  def start_date
    date_value("start_date_block", "start_date")
  end

  def end_date
    date_value("end_date_block", "end_date")
  end

  # True when both dates are present and end is before start — callers should
  # surface this as an inline error rather than let it fall through to the
  # model validation's generic failure message.
  def end_before_start?
    start_date.present? && end_date.present? && Date.parse(end_date) < Date.parse(start_date)
  end

  # Bare selected conversation, if any — callers apply their own fallback.
  def channel
    state.dig("channel_block", "channel", "selected_conversation").presence
  end

  def summary_day
    state.dig("summary_day_block", "summary_day", "selected_option", "value")&.to_i
  end

  def summary_time
    time_value("summary_time_block", "summary_time")
  end

  def parent_goal
    id = state.dig("parent_block", "parent", "selected_option", "value")
    id && organization.goals.find_by(id: id)
  end

  # "Draft" checkbox: checked means the single option's selected.
  def draft_checked?
    state.dig("draft_block", "draft", "selected_options").present?
  end

  def state
    payload.dig(:view, :state, :values) || {}
  end

  def value_at(block_id, action_id)
    state.dig(block_id, action_id, "value").to_s.strip
  end

  def date_value(block_id, action_id)
    state.dig(block_id, action_id, "selected_date").presence
  end

  def time_value(block_id, action_id)
    state.dig(block_id, action_id, "selected_time").presence
  end

  def error(block_id, message)
    { response_action: "errors", errors: { block_id => message } }
  end
end

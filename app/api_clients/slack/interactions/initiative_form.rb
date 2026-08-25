# frozen_string_literal: true

# Modal-state field readers shared by CreateInitiativeSubmission and
# EditInitiativeSubmission — both handlers parse the same field layout (see
# Slack::Views::CreateInitiativeModal / EditInitiativeModal), just apply the
# parsed values differently (CreateInitiative vs. UpdateInitiative). Include
# into a Slack::Interactions::Base subclass that exposes `payload` and
# `organization`.
module Slack::Interactions::InitiativeForm
  private

  def title
    value_at("title_block", "title")
  end

  def description
    value_at("description_block", "description").presence
  end

  def owner_slack_id
    state.dig("owner_block", "owner", "selected_user").presence
  end

  def status
    state.dig("status_block", "status", "selected_option", "value")
  end

  # Create modal's goal picker — the parent goal isn't editable, so
  # EditInitiativeSubmission never reads this.
  def goal_id
    state.dig("goal_block", "goal", "selected_option", "value")
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

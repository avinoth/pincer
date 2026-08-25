# frozen_string_literal: true

# Base for interaction handlers (block_actions / view_submission). Subclasses
# implement #call; block_actions handlers return nil, view_submission handlers may
# return a `response_action` hash (errors / update / push) that the controller renders.
class Slack::Interactions::Base
  def initialize(payload)
    @payload = payload.is_a?(Hash) ? payload.with_indifferent_access : payload
  end

  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  attr_reader :payload

  def organization
    @organization ||= SlackWorkspace.find_by(identifier: team_id)&.organization
  end

  def team_id
    payload.dig(:team, :id)
  end

  def user_id
    payload.dig(:user, :id)
  end

  def trigger_id
    payload[:trigger_id]
  end

  # Posts a Slack ephemeral message (visible only to the acting user) in the
  # channel the block_actions payload fired in. Returns nil so callers can use
  # it directly as the value of an early `return` from #call.
  def ephemeral(text)
    Slack::Request::SendMessage.new(organization.slack_workspace)
      .send_ephemeral(payload.dig(:channel, :id), user_id, { text: text })
    nil
  end
end

# frozen_string_literal: true

# Handles the "Publish goal" button on a GoalDisplay message: one-click
# publish, no modal round-trip. Updates the origin message in place to show
# the goal as published (block_actions carries channel + the origin message's
# ts in `container`).
class Slack::Interactions::PublishGoal < Slack::Interactions::Base
  def call
    return unless organization

    goal = organization.goals.publishing_draft.find_by(id: action_value)
    return if goal.nil?
    return ephemeral("Only the goal's creator or an owner can publish it.") unless goal.modifiable_by?(user_id)

    result = UpdateGoal.call(goal: goal, attributes: {}, publish: true)
    return unless result.success?

    channel = payload.dig(:channel, :id) || payload.dig(:container, :channel_id)
    message_ts = payload.dig(:container, :message_ts) || payload.dig(:message, :ts)

    Slack::Request::UpdateMessage.new(organization.slack_workspace).update_message(
      channel, message_ts, Slack::Messages::GoalDisplay.new(goal: result.goal).to_h
    )
    nil
  end

  private

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end
end

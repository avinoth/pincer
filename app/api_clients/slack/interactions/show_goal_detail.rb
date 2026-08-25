class Slack::Interactions::ShowGoalDetail < Slack::Interactions::Base
  def call
    return unless organization

    goal = organization.goals.find_by(id: action_value)
    return if goal.nil?

    channel = payload.dig(:channel, :id) || payload.dig(:container, :channel_id)
    return if channel.blank?

    Slack::Request::SendMessage.new(organization.slack_workspace).send_message(
      channel, Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: thread_ts)
    )
    nil
  end

  private

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end

  def thread_ts
    payload.dig(:message, :thread_ts) || payload.dig(:container, :message_ts) || payload.dig(:message, :ts)
  end
end

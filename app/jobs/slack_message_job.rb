class SlackMessageJob < ApplicationJob
  queue_as :default

  # STUB SEAM — DM/command reply behavior not yet specified.
  #
  # Contract: perform(channel_id, message, organization_id)
  # Intended behavior: post `message` to `channel_id` via
  #   Slack::Request::SendMessage.new(organization.slack_workspace)
  #     .send_message(channel_id, { text: message })
  # Wire this up once command routing (Command::Slack) is designed.
  def perform(channel_id, message, organization_id)
    Rails.logger.info("[SlackMessageJob] stub: channel=#{channel_id} org=#{organization_id}")
  end
end

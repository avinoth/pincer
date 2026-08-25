# frozen_string_literal: true

# block_actions handler for the "wave" button on the app_mention reply. Posts a
# threaded wave back — proves the mention -> button -> router -> reply loop.
class Slack::Interactions::Wave < Slack::Interactions::Base
  def call
    return unless organization

    channel = payload.dig(:channel, :id) || payload.dig(:container, :channel_id)
    return if channel.blank?

    thread_ts = payload.dig(:message, :thread_ts) ||
                payload.dig(:message, :ts) ||
                payload.dig(:container, :message_ts)

    Slack::Request::SendMessage.new(organization.slack_workspace)
      .send_message(channel, { text: "👋 back at you, <@#{user_id}>!", thread_ts: thread_ts })
    nil
  end
end

class Slack::Request::SendMessage < Slack::Request::Base
  class InvalidChannel < StandardError; end
  class InvalidAccount < StandardError; end

  # Post a message. `channel_id` may be a channel or a user id (opens a DM).
  # `message` is a Slack chat.postMessage payload hash (e.g. { text: "..." }).
  def send_message(channel_id, message)
    return if channel_id.blank?

    payload = message.merge(channel: channel_id)
    log_slack_call("chat.postMessage", payload) { client.chat_postMessage(payload) }
  rescue Slack::Web::Api::Errors::IsArchived, Slack::Web::Api::Errors::ChannelNotFound
    raise InvalidChannel
  rescue Slack::Web::Api::Errors::AccountInactive
    raise InvalidAccount
  end

  # Post an ephemeral message, visible only to `user_id` in `channel_id`.
  def send_ephemeral(channel_id, user_id, message)
    return if channel_id.blank? || user_id.blank?

    payload = message.merge(channel: channel_id, user: user_id)
    log_slack_call("chat.postEphemeral", payload) { client.chat_postEphemeral(payload) }
  rescue Slack::Web::Api::Errors::IsArchived, Slack::Web::Api::Errors::ChannelNotFound
    raise InvalidChannel
  rescue Slack::Web::Api::Errors::AccountInactive
    raise InvalidAccount
  end
end

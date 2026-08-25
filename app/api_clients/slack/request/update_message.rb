# frozen_string_literal: true

class Slack::Request::UpdateMessage < Slack::Request::Base
  class InvalidChannel < StandardError; end
  class InvalidAccount < StandardError; end

  # Edit a previously posted message in place. `ts` is the target message's
  # timestamp (from the chat.postMessage response). `message` is a Slack
  # chat.update payload hash (e.g. { text: "...", blocks: [...] }).
  def update_message(channel_id, ts, message)
    return if channel_id.blank? || ts.blank?

    payload = message.merge(channel: channel_id, ts: ts)
    log_slack_call("chat.update", payload) { client.chat_update(payload) }
  rescue Slack::Web::Api::Errors::IsArchived, Slack::Web::Api::Errors::ChannelNotFound, Slack::Web::Api::Errors::MessageNotFound
    raise InvalidChannel
  rescue Slack::Web::Api::Errors::AccountInactive
    raise InvalidAccount
  end
end

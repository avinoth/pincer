# frozen_string_literal: true

class AppMentionReplyJob < ApplicationJob
  queue_as :default

  def perform(team_id:, channel:, thread_ts:, user:, text:)
    organization = SlackWorkspace.find_by(identifier: team_id)&.organization
    return unless organization
    return if channel.blank?

    reply = Slack::Messages::MentionReply.new(text: text)
    Slack::Request::SendMessage.new(organization.slack_workspace)
      .send_message(channel, reply.to_h.merge(thread_ts: thread_ts))
  rescue => e
    Bugsnag.notify(e, { team_id: team_id, channel: channel })
  end
end

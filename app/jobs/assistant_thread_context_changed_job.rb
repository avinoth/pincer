# frozen_string_literal: true

# Handles Slack's assistant_thread_context_changed event: the user switched
# which channel they're viewing while a split-view thread stays open. Just
# refreshes the Conversation's context_hint for the next turn's system prompt —
# no AgentRun, nothing narrated to the user.
class AssistantThreadContextChangedJob < ApplicationJob
  queue_as :default

  def perform(slack_team_id:, channel:, thread_ts:, context: {})
    organization = SlackWorkspace.find_by(identifier: slack_team_id)&.organization
    return unless organization
    return if channel.blank? || thread_ts.blank?

    conversation = organization.conversations.find_by(slack_channel_id: channel, slack_thread_ts: thread_ts)
    return unless conversation

    channel_id = context&.with_indifferent_access&.dig(:channel_id)
    return if channel_id.blank?

    conversation.update!(context_hint: "user is viewing ##{channel_id}")
  rescue => e
    Bugsnag.notify(e, { slack_team_id: slack_team_id, channel: channel, thread_ts: thread_ts })
  end
end

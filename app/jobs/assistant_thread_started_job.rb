# frozen_string_literal: true

# Handles Slack's assistant_thread_started event: the user just opened a fresh
# Agent split-view thread, before typing anything. Finds-or-creates the
# Conversation (surface "assistant"), posts a threaded greeting, and seeds the
# thread's suggested prompts. No AgentRun — there's no user turn to react to yet.
class AssistantThreadStartedJob < ApplicationJob
  queue_as :default

  SUGGESTED_PROMPTS = [
    { title: "Create a goal for this quarter", message: "Create a goal for this quarter" },
    { title: "How are my goals doing?", message: "How are my goals doing?" }
  ].freeze

  def perform(slack_team_id:, channel:, thread_ts:, slack_user_id:, context: {})
    organization = SlackWorkspace.find_by(identifier: slack_team_id)&.organization
    return unless organization
    return if channel.blank? || thread_ts.blank?

    conversation = find_or_create_conversation(organization, channel, thread_ts, context)
    user = resolve_user(organization, slack_user_id)

    post_greeting(organization, conversation, user)
    build_streamer(organization, conversation, slack_user_id).set_suggested_prompts(SUGGESTED_PROMPTS)
  rescue => e
    Bugsnag.notify(e, { slack_team_id: slack_team_id, channel: channel, thread_ts: thread_ts })
  end

  private

  def find_or_create_conversation(organization, channel, thread_ts, context)
    organization.conversations.create_with(
      surface: :assistant,
      context_hint: context_hint_for(context),
    ).find_or_create_by!(slack_channel_id: channel, slack_thread_ts: thread_ts)
  end

  def context_hint_for(context)
    channel_id = context&.with_indifferent_access&.dig(:channel_id)
    channel_id.present? ? "user is viewing ##{channel_id}" : nil
  end

  def resolve_user(organization, slack_user_id)
    return nil if slack_user_id.blank?

    result = CreateUserFromSlack.call(organization: organization, slack_user_id: slack_user_id)
    result.success? ? result.user : nil
  end

  def post_greeting(organization, conversation, user)
    first_name = user&.full_name.to_s.split.first.presence || "there"

    first_time = user.present? &&
      User.where(id: user.id, greeted_at: nil).update_all(greeted_at: Time.current) == 1

    message =
      if first_time
        Slack::Messages::AssistantWelcome.new(name: first_name)
      else
        Slack::Messages::AssistantGreeting.new(name: first_name)
      end

    Slack::Request::SendMessage.new(organization.slack_workspace).send_message(
      conversation.slack_channel_id,
      message.to_h.merge(thread_ts: conversation.slack_thread_ts),
    )
  end

  def build_streamer(organization, conversation, slack_user_id)
    Slack::Streamer.new(
      organization.slack_workspace,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      recipient_user_id: slack_user_id,
    )
  end
end

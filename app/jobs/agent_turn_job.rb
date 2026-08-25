# frozen_string_literal: true

# Async entry point for one turn of the Slack agent. Slack must be acked within
# 3s, so the events controller (checkpoint 5) enqueues this; the worker resolves
# the org + user, finds-or-creates the thread's Conversation, appends the
# triggering message, opens an AgentRun, and hands off to Ai::Agent::Runner.
#
# Enqueue for:
#   * an @mention / DM / assistant message the user typed:
#       AgentTurnJob.perform_later(
#         slack_team_id:, channel:, thread_ts:, surface:, slack_user_id:, text:)
#   * a system-authored event (assistant thread started, a late form submission
#     narrated back into the thread, etc.):
#       AgentTurnJob.perform_later(
#         slack_team_id:, channel:, thread_ts:, surface:, slack_user_id:, event:)
#
# Exactly one of `text:` / `event:` is given. `surface` is "assistant" |
# "channel" | "dm" and is only used when the Conversation is first created.
#
# Concurrency (settled decision #7): strict serialization per Slack thread. Only
# one turn performs at a time per (team, channel, thread_ts); GoodJob queues the
# rest (perform_limit 1, no enqueue limit) and retries them — nothing is dropped.
# The key is a plain string so it works before the Conversation row exists.
class AgentTurnJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  queue_as :default

  good_job_control_concurrency_with(
    perform_limit: 1,
    key: -> {
      a = arguments.first || {}
      "agent-turn:#{a[:slack_team_id]}:#{a[:channel]}:#{a[:thread_ts]}"
    },
  )

  # Message the runner appends for a still-open pause that the user chose to talk
  # past instead of resolving (resolve-once rule, case i).
  SUPERSEDED_PAUSE_RESULT =
    "Form shown; user has not submitted it yet — they continued the conversation instead."

  def perform(slack_team_id:, channel:, thread_ts:, surface:, slack_user_id:, text: nil, event: nil)
    organization = SlackWorkspace.find_by(identifier: slack_team_id)&.organization
    return unless organization
    return if channel.blank? || thread_ts.blank?

    user = resolve_user(organization, slack_user_id)
    return unless user

    conversation = find_or_create_conversation(organization, channel, thread_ts, surface)

    supersede_open_pause(conversation)
    append_turn_message(conversation, user, text: text, event: event)

    agent_run = conversation.agent_runs.create!(status: :running)
    Ai::Agent::Runner.call(
      agent_run: agent_run,
      streamer_factory: streamer_factory(conversation, slack_user_id),
      user: user,
    )
  rescue => e
    Bugsnag.notify(e, { slack_team_id: slack_team_id, channel: channel, thread_ts: thread_ts }) if defined?(Bugsnag)
    raise
  end

  private

  def resolve_user(organization, slack_user_id)
    result = CreateUserFromSlack.call(organization: organization, slack_user_id: slack_user_id)
    result.success? ? result.user : nil
  end

  def find_or_create_conversation(organization, channel, thread_ts, surface)
    organization.conversations.create_with(surface: surface).find_or_create_by!(
      slack_channel_id: channel,
      slack_thread_ts: thread_ts,
    )
  end

  # Resolve-once rule (settled decision #5, case i): if the thread's latest run is
  # still paused on a tool, the user has moved on without resolving it. Append a
  # synthetic tool result so the transcript stays balanced, then retire that run
  # as superseded. The live form button in Slack stays clickable — a later submit
  # is handled as its own event (case ii) by checkpoint 5.
  def supersede_open_pause(conversation)
    run = conversation.latest_run
    return unless run&.status_paused_on_tool?

    conversation.conversation_messages.create!(
      role: :tool,
      tool_call_id: (run.pending_tool_call || {}).with_indifferent_access["id"],
      content: SUPERSEDED_PAUSE_RESULT,
    )
    run.update!(status: :completed)
  end

  def append_turn_message(conversation, user, text:, event:)
    if event.present?
      conversation.conversation_messages.create!(role: :event, content: event)
    else
      conversation.conversation_messages.create!(role: :user, content: text, user: user)
    end
  end

  # Returns a callable that mints a fresh Slack::Streamer per call — the Runner
  # opens one per model completion (plus one for thread-level decoration), not
  # one per turn (Slack only allows Block Kit blocks in chat.stopStream, never
  # appendStream, so a tool's card can't be inlined mid-message).
  def streamer_factory(conversation, slack_user_id)
    -> {
      Slack::Streamer.new(
        conversation.organization.slack_workspace,
        channel: conversation.slack_channel_id,
        thread_ts: conversation.slack_thread_ts,
        recipient_user_id: slack_user_id,
      )
    }
  end
end

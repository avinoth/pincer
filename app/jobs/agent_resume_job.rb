# frozen_string_literal: true

# Resumes a paused agent run off the Slack interaction request's 3s window.
# Ai::Agent::Resume re-enters the full Runner loop (an LLM round trip) — too
# slow to run inline in the view_submission handler
# (Slack::Interactions::CreateGoalSubmission), so that handler enqueues us
# instead and returns response_action: "clear" immediately.
#
# If the run is no longer paused by the time we run — e.g. the resolve-once rule
# (settled decision #5, case i) superseded it while this job sat in queue —
# Ai::Agent::Resume raises NotPausedError. We fall back to the same "late submit"
# event path the submission handler uses when it already knows the run has moved
# on (case ii), so the outcome narrates identically either way.
class AgentResumeJob < ApplicationJob
  queue_as :default

  def perform(agent_run_id:, tool_result:, slack_user_id: nil)
    agent_run = AgentRun.find_by(id: agent_run_id)
    return unless agent_run

    Ai::Agent::Resume.call(agent_run: agent_run, tool_result: tool_result, recipient_user_id: slack_user_id)
  rescue Ai::Agent::Resume::NotPausedError
    enqueue_late_submit_event(agent_run, tool_result, slack_user_id)
  rescue => e
    Bugsnag.notify(e, { agent_run_id: agent_run_id })
  end

  private

  def enqueue_late_submit_event(agent_run, tool_result, slack_user_id)
    conversation = agent_run.conversation
    goal = (tool_result || {}).with_indifferent_access[:goal] || {}

    AgentTurnJob.perform_later(
      slack_team_id: conversation.organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: slack_user_id || fallback_user_id(conversation),
      event: "user has now submitted the previously displayed goal form; " \
             "goal '#{goal[:title]}' was created (id #{goal[:id]}).",
    )
  end

  # Best-effort author when the enqueuing request didn't hand us one: the last
  # human who actually typed in this thread.
  def fallback_user_id(conversation)
    conversation.conversation_messages.where(role: :user).where.not(user_id: nil)
      .order(:created_at).last&.user&.provider_uid
  end
end

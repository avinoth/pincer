# frozen_string_literal: true

# Handles the "Delete initiative" confirm button posted by
# Ai::Agent::Tools::DeleteInitiative (see
# Slack::Messages::AgentInitiativeDeletePrompt). The button's value carries
# the paused AgentRun's id; the initiative to delete is the one the tool
# stashed onto pending_tool_call["args"]["initiative_id"] — the tool itself
# never deletes anything, only this click does (via ::DeleteInitiative).
#
# If the run's pending_tool_call already carries a deleted_initiative_id
# (this confirm was already resolved — a retried Slack delivery, or another
# user racing the same click), it's a replay: tell the acting user and do
# nothing further, rather than deleting a second time.
class Slack::Interactions::AgentConfirmDeleteInitiative < Slack::Interactions::Base
  def call
    return unless organization

    agent_run = find_agent_run
    return if agent_run.nil?
    return ephemeral("This initiative was already deleted.") if agent_run_already_produced?(agent_run)

    initiative_id = agent_run.pending_tool_call&.dig("args", "initiative_id")
    initiative = organization_initiatives.find_by(id: initiative_id)
    return already_gone(agent_run, initiative_id) if initiative.nil?

    unless initiative.modifiable_by?(user_id)
      return ephemeral("Only the initiative's owner or the goal's owners/creator can delete it.")
    end

    delete(agent_run, initiative)
  end

  private

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end

  # Scoped to this org so a stale/foreign run id never resumes someone else's
  # run (same discipline as AgentPickInitiativeSelection#find_agent_run).
  def find_agent_run
    AgentRun.joins(:conversation).where(conversations: { organization_id: organization.id }).find_by(id: action_value)
  end

  # Org-scoped via the parent goal — a tampered/foreign initiative id never
  # leaks another org's initiative.
  def organization_initiatives
    Initiative.joins(:goal).where(goals: { organization_id: organization.id })
  end

  def agent_run_already_produced?(agent_run)
    agent_run.pending_tool_call&.dig("deleted_initiative_id").present?
  end

  # The initiative was already gone by the time the human clicked confirm
  # (deleted some other way in the meantime) — treat that as the delete
  # having already happened rather than surfacing an error.
  def already_gone(agent_run, initiative_id)
    mark_produced(agent_run, initiative_id)
    update_tombstone(nil)
    trigger_agent_hook(
      agent_run,
      tool_result: { status: "already_deleted", initiative_id: initiative_id },
      narration: "the initiative the user asked to delete (id #{initiative_id}) was already gone",
    )
    nil
  end

  def delete(agent_run, initiative)
    title = initiative.title
    goal_title = initiative.goal.title

    result = ::DeleteInitiative.call(initiative: initiative)
    return ephemeral("Couldn't delete the initiative: #{result.error}") if result.failure?

    mark_produced(agent_run, initiative.id)
    update_tombstone(title)
    trigger_agent_hook(
      agent_run,
      tool_result: { status: "deleted", initiative: { id: initiative.id, title: title }, goal: { title: goal_title } },
      narration: "user confirmed deletion of initiative '#{title}' (id #{initiative.id}); it's been permanently deleted",
    )
    nil
  end

  # Merge-don't-overwrite, same discipline as
  # Slack::Interactions::AgentPickInitiativeSelection#mark_produced —
  # pending_tool_call already carries "id"/"name"/"args" and those must
  # survive this update.
  def mark_produced(agent_run, initiative_id)
    pending = (agent_run.pending_tool_call || {}).stringify_keys
    pending["deleted_initiative_id"] = initiative_id
    agent_run.update!(pending_tool_call: pending)
  end

  def update_tombstone(title)
    channel = payload.dig(:channel, :id)
    message_ts = payload.dig(:container, :message_ts)
    return if channel.blank? || message_ts.blank?

    Slack::Request::UpdateMessage.new(organization.slack_workspace).update_message(
      channel, message_ts, Slack::Messages::InitiativeDeletedNotice.new(title: title).to_h
    )
  end

  # Resumes the paused run inline-fast (enqueues — Resume is a full LLM round
  # trip, too slow for Slack's 3s window) when it's still waiting on exactly
  # this confirm; otherwise the run has moved on since the prompt was shown
  # (resolve-once rule), so we narrate the outcome back in as a fresh turn
  # instead of resuming a run that no longer expects this result.
  def trigger_agent_hook(agent_run, tool_result:, narration:)
    if agent_run.status_paused_on_tool? && agent_run.pending_tool_call&.dig("name") == "delete_initiative"
      AgentResumeJob.perform_later(agent_run_id: agent_run.id, slack_user_id: user_id, tool_result: tool_result)
    else
      enqueue_late_submit_event(agent_run, narration)
    end
  end

  def enqueue_late_submit_event(agent_run, narration)
    conversation = agent_run.conversation

    AgentTurnJob.perform_later(
      slack_team_id: organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: user_id,
      event: narration,
    )
  end
end

# frozen_string_literal: true

# Handles the initiative-picker dropdown posted by
# Ai::Agent::Tools::PickInitiative (see
# Slack::Messages::AgentInitiativePickerPrompt). The select's block_id carries
# the paused AgentRun's id; the chosen option's value is the picked
# initiative's id.
#
# If the run's pending_tool_call already carries a produced_initiative_id
# (this picker was already resolved — by this user re-selecting a stale
# dropdown, or another user racing them to it), it's a replay: tell the acting
# user and do nothing further, rather than resuming (or narrating into) the
# run a second time.
class Slack::Interactions::AgentPickInitiativeSelection < Slack::Interactions::Base
  def call
    return unless organization

    agent_run = find_agent_run
    return if agent_run.nil?

    return ephemeral("This initiative was already picked.") if agent_run_already_produced?(agent_run)

    # Org-scoped (via the parent goal) so a tampered/foreign initiative id
    # never leaks another org's initiative.
    initiative = organization_initiatives.find_by(id: selected_initiative_id)
    return if initiative.nil?

    mark_produced(agent_run, initiative)

    if agent_run.status_paused_on_tool? && agent_run.pending_tool_call&.dig("name") == "pick_initiative"
      AgentResumeJob.perform_later(
        agent_run_id: agent_run.id, slack_user_id: user_id, tool_result: tool_result_for(initiative),
      )
    else
      enqueue_late_submit_event(agent_run, initiative)
    end

    nil
  end

  private

  def action
    Array(payload[:actions]).first
  end

  def block_id
    action&.dig(:block_id)
  end

  def selected_initiative_id
    action&.dig(:selected_option, :value)
  end

  def organization_initiatives
    Initiative.joins(:goal).where(goals: { organization_id: organization.id })
  end

  # Scoped to this org so a stale/foreign run id never resumes someone else's
  # run (same discipline as AgentOpenCreateInitiativeModal#find_agent_run).
  def find_agent_run
    AgentRun.joins(:conversation).where(conversations: { organization_id: organization.id }).find_by(id: agent_run_id)
  end

  def agent_run_id
    block_id.to_s.delete_prefix(Slack::Messages::AgentInitiativePickerPrompt::BLOCK_ID_PREFIX)
  end

  def agent_run_already_produced?(agent_run)
    agent_run.pending_tool_call&.dig("produced_initiative_id").present?
  end

  # Merge-don't-overwrite, same discipline as
  # Slack::Interactions::CreateInitiativeSubmission#mark_produced —
  # pending_tool_call already carries "id"/"name"/"args" and those must
  # survive this update.
  def mark_produced(agent_run, initiative)
    pending = (agent_run.pending_tool_call || {}).stringify_keys
    pending["produced_initiative_id"] = initiative.id
    agent_run.update!(pending_tool_call: pending)
  end

  def tool_result_for(initiative)
    {
      id: initiative.id,
      title: initiative.title,
      goal_id: initiative.goal_id,
      owner: initiative.owner&.full_name,
      status: initiative.status
    }
  end

  def enqueue_late_submit_event(agent_run, initiative)
    conversation = agent_run.conversation

    AgentTurnJob.perform_later(
      slack_team_id: organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: user_id,
      event: "user has now picked an initiative from the previously displayed list: " \
             "'#{initiative.title}' (id #{initiative.id}).",
    )
  end
end

# frozen_string_literal: true

# Handles the goal-picker dropdown posted by Ai::Agent::Tools::PickGoal (see
# Slack::Messages::AgentGoalPickerPrompt). The select's block_id carries the
# paused AgentRun's id; the chosen option's value is the picked goal's id.
#
# If the run's pending_tool_call already carries a produced_goal_id (this
# picker was already resolved — by this user re-selecting a stale dropdown, or
# another user racing them to it), it's a replay: tell the acting user and do
# nothing further, rather than resuming (or narrating into) the run a second time.
class Slack::Interactions::AgentPickGoalSelection < Slack::Interactions::Base
  def call
    return unless organization

    agent_run = find_agent_run
    return if agent_run.nil?

    return ephemeral("This goal was already picked.") if agent_run_already_produced?(agent_run)

    # Org-scoped so a tampered/foreign goal id never leaks another org's goal.
    goal = organization.goals.find_by(id: selected_goal_id)
    return if goal.nil?

    mark_produced(agent_run, goal)

    if agent_run.status_paused_on_tool? && agent_run.pending_tool_call&.dig("name") == "pick_goal"
      AgentResumeJob.perform_later(agent_run_id: agent_run.id, slack_user_id: user_id, tool_result: tool_result_for(goal))
    else
      enqueue_late_submit_event(agent_run, goal)
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

  def selected_goal_id
    action&.dig(:selected_option, :value)
  end

  # Scoped to this org so a stale/foreign run id never resumes someone else's
  # run (same discipline as AgentOpenCreateGoalModal#find_agent_run).
  def find_agent_run
    AgentRun.joins(:conversation).where(conversations: { organization_id: organization.id }).find_by(id: agent_run_id)
  end

  def agent_run_id
    block_id.to_s.delete_prefix(Slack::Messages::AgentGoalPickerPrompt::BLOCK_ID_PREFIX)
  end

  def agent_run_already_produced?(agent_run)
    agent_run.pending_tool_call&.dig("produced_goal_id").present?
  end

  # Merge-don't-overwrite, same discipline as
  # Slack::Interactions::CreateGoalSubmission#mark_produced — pending_tool_call
  # already carries "id"/"name"/"args" and those must survive this update.
  def mark_produced(agent_run, goal)
    pending = (agent_run.pending_tool_call || {}).stringify_keys
    pending["produced_goal_id"] = goal.id
    agent_run.update!(pending_tool_call: pending)
  end

  def tool_result_for(goal)
    { id: goal.id, title: goal.title, start_date: goal.start_date, end_date: goal.end_date, status: goal.status }
  end

  def enqueue_late_submit_event(agent_run, goal)
    conversation = agent_run.conversation

    AgentTurnJob.perform_later(
      slack_team_id: organization.slack_workspace.identifier,
      channel: conversation.slack_channel_id,
      thread_ts: conversation.slack_thread_ts,
      surface: conversation.surface,
      slack_user_id: user_id,
      event: "user has now picked a goal from the previously displayed list: '#{goal.title}' (id #{goal.id}).",
    )
  end
end

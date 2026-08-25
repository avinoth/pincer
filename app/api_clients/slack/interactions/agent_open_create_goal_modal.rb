# frozen_string_literal: true

# Handles the "Create Goal" button posted by Ai::Agent::Tools::ShowGoalCreateForm
# (see Slack::Messages::AgentGoalDraftPrompt). The button value is a paused
# AgentRun's id; opens the CreateGoalModal view prefilled from the run's
# pending_tool_call args.
#
# If the run's pending_tool_call already carries a produced_goal_id (the form
# was already submitted — by this user re-clicking a stale button, or by
# another user racing them to it), the draft is stale: opens the
# GoalAlreadyCreatedModal info view instead, rather than reopening an editable
# form for a goal that already exists.
class Slack::Interactions::AgentOpenCreateGoalModal < Slack::Interactions::Base
  def call
    return unless organization

    agent_run = find_agent_run
    return if agent_run.nil?

    produced_goal_id = agent_run.pending_tool_call&.dig("produced_goal_id")
    view = produced_goal_id.present? ? already_created_view(produced_goal_id) : create_goal_view(agent_run)

    Slack::Request::OpenView.new(organization.slack_workspace).open_modal(view, trigger_id)
    nil
  end

  private

  def create_goal_view(agent_run)
    Slack::Views::CreateGoalModal.new(
      agent_run: agent_run,
      parent_goals: organization.goals.where(status: [ :not_started, :in_progress ])
        .publishing_published.order(:title).limit(50),
    )
  end

  # Org-scoped so a stale/foreign goal id never leaks another org's goal title.
  def already_created_view(goal_id)
    Slack::Views::GoalAlreadyCreatedModal.new(goal: organization.goals.find_by(id: goal_id))
  end

  # Scoped to this org so a stale/foreign run id never opens someone else's draft.
  def find_agent_run
    AgentRun.joins(:conversation).where(conversations: { organization_id: organization.id }).find_by(id: action_value)
  end

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end
end

# frozen_string_literal: true

# Handles the "Create Initiative" button posted by
# Ai::Agent::Tools::ShowInitiativeCreateForm (see
# Slack::Messages::AgentInitiativeDraftPrompt). The button value is a paused
# AgentRun's id; opens the CreateInitiativeModal view prefilled from the run's
# pending_tool_call args.
#
# If the run's pending_tool_call already carries a produced_initiative_id (the
# form was already submitted — by this user re-clicking a stale button, or by
# another user racing them to it), the draft is stale: opens the
# InitiativeAlreadyCreatedModal info view instead, rather than reopening an
# editable form for an initiative that already exists.
class Slack::Interactions::AgentOpenCreateInitiativeModal < Slack::Interactions::Base
  def call
    return unless organization

    agent_run = find_agent_run
    return if agent_run.nil?

    produced_initiative_id = agent_run.pending_tool_call&.dig("produced_initiative_id")
    view = produced_initiative_id.present? ? already_created_view(produced_initiative_id) : create_initiative_view(agent_run)

    Slack::Request::OpenView.new(organization.slack_workspace).open_modal(view, trigger_id)
    nil
  end

  private

  def create_initiative_view(agent_run)
    Slack::Views::CreateInitiativeModal.new(
      agent_run: agent_run,
      goals: organization.goals.accepting_initiatives.publishing_published.order(:title).limit(50),
    )
  end

  # Org-scoped so a stale/foreign initiative id never leaks another org's
  # initiative title (via its parent goal).
  def already_created_view(initiative_id)
    Slack::Views::InitiativeAlreadyCreatedModal.new(
      initiative: Initiative.joins(:goal).where(goals: { organization_id: organization.id }).find_by(id: initiative_id),
    )
  end

  # Scoped to this org so a stale/foreign run id never opens someone else's draft.
  def find_agent_run
    AgentRun.joins(:conversation).where(conversations: { organization_id: organization.id }).find_by(id: action_value)
  end

  def action_value
    Array(payload[:actions]).first&.dig(:value)
  end
end

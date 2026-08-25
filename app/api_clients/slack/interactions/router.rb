# frozen_string_literal: true

# Routes Slack interactive payloads to handler classes. Register new buttons/modals
# by adding to REGISTRY — the single extension point.
#
# - block_actions:    keyed by each action's action_id
# - view_submission:  keyed by the submitted view's callback_id
class Slack::Interactions::Router
  REGISTRY = {
    "block_actions" => {
      "wave" => Slack::Interactions::Wave,
      Slack::Messages::AgentGoalDraftPrompt::ACTION_ID => Slack::Interactions::AgentOpenCreateGoalModal,
      Slack::Messages::GoalDisplay::PUBLISH_ACTION_ID => Slack::Interactions::PublishGoal,
      Slack::Messages::GoalDisplay::EDIT_ACTION_ID => Slack::Interactions::OpenEditGoalModal,
      Slack::Messages::AgentGoalPickerPrompt::ACTION_ID => Slack::Interactions::AgentPickGoalSelection,
      Slack::Messages::GoalSummaryList::VIEW_DETAIL_ACTION_ID => Slack::Interactions::ShowGoalDetail,
      Slack::Messages::AgentInitiativeDraftPrompt::ACTION_ID => Slack::Interactions::AgentOpenCreateInitiativeModal,
      Slack::Messages::InitiativeDisplay::EDIT_ACTION_ID => Slack::Interactions::OpenEditInitiativeModal,
      Slack::Messages::AgentInitiativePickerPrompt::ACTION_ID => Slack::Interactions::AgentPickInitiativeSelection,
      Slack::Messages::AgentInitiativeDeletePrompt::ACTION_ID => Slack::Interactions::AgentConfirmDeleteInitiative,
      Slack::Messages::InitiativeDisplay::DELETE_ACTION_ID => Slack::Interactions::DeleteInitiativeAction
    },
    "view_submission" => {
      Slack::Views::ExampleModal::CALLBACK_ID => Slack::Interactions::ExampleSubmission,
      Slack::Views::CreateGoalModal::CALLBACK_ID => Slack::Interactions::CreateGoalSubmission,
      Slack::Views::EditGoalModal::CALLBACK_ID => Slack::Interactions::EditGoalSubmission,
      Slack::Views::CreateInitiativeModal::CALLBACK_ID => Slack::Interactions::CreateInitiativeSubmission,
      Slack::Views::EditInitiativeModal::CALLBACK_ID => Slack::Interactions::EditInitiativeSubmission
    }
  }.freeze

  def initialize(payload)
    @payload = payload.to_h.with_indifferent_access
  end

  # Returns nil for block_actions; may return a response_action hash for
  # view_submission (rendered as JSON by the controller).
  def route
    case @payload[:type]
    when "block_actions"   then route_block_actions
    when "view_submission" then route_view_submission
    when "view_closed"     then nil # hook for cleanup if ever needed
    end
  end

  private

  def route_block_actions
    Array(@payload[:actions]).each do |action|
      handler = REGISTRY.dig("block_actions", action[:action_id])
      handler&.new(@payload)&.call
    end
    nil
  end

  def route_view_submission
    callback_id = @payload.dig(:view, :callback_id)
    handler = REGISTRY.dig("view_submission", callback_id)
    handler&.new(@payload)&.call
  end
end

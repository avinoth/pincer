# frozen_string_literal: true

# The Create Initiative form — goal, title, description, and a single owner.
# Prefilled from the extracted draft. Submitting validates everything in one
# pass and creates the Initiative (see
# Slack::Interactions::CreateInitiativeSubmission) — closing the modal leaves
# zero rows behind.
#
# Offered by the agent flow (Ai::Agent::Tools::ShowInitiativeCreateForm /
# AgentOpenCreateInitiativeModal): pass `agent_run:` (the paused AgentRun) and
# `goals:` (candidate parent goals for the static_select — the org's goals
# still accepting initiatives). Draft comes from
# agent_run.pending_tool_call["args"]. private_metadata is JSON
# {"agent_run_id" => id} that CreateInitiativeSubmission reads back.
class Slack::Views::CreateInitiativeModal < Slack::Views::Modal
  CALLBACK_ID = "create_initiative"

  # @param goals [Enumerable<Goal>] candidate parent goals (org's goals still accepting initiatives)
  def initialize(agent_run:, goals: [])
    @agent_run = agent_run
    @draft = (draft_source || {}).with_indifferent_access
    @goals = goals.to_a
  end

  def callback_id
    CALLBACK_ID
  end

  def title
    "Create Initiative"
  end

  def submit_label
    "Create initiative"
  end

  def private_metadata
    { agent_run_id: @agent_run.id }.to_json
  end

  def blocks
    [
      input(
        label: "Goal",
        block_id: "goal_block",
        element: static_select(
          action_id: "goal",
          placeholder: "Select a goal",
          options: @goals.map { |g| option(g.title, g.id.to_s) },
          initial_option: initial_goal_option,
        ),
      ),
      input(
        label: "Title",
        block_id: "title_block",
        element: plain_text_input(
          action_id: "title",
          initial_value: @draft[:title].presence,
          max_length: 255,
        ),
      ),
      input(
        label: "Description",
        block_id: "description_block",
        optional: true,
        element: plain_text_input(
          action_id: "description",
          multiline: true,
          initial_value: @draft[:description].presence,
          max_length: 2000,
        ),
      ),
      input(
        label: "Owner",
        block_id: "owner_block",
        element: users_select(
          action_id: "owner",
          placeholder: "Select an owner",
          initial_user: @draft[:owner].presence,
        ),
      )
    ]
  end

  private

  def draft_source
    @agent_run.pending_tool_call&.dig("args")
  end

  def initial_goal_option
    goal = @draft[:goal_id].presence && @goals.find { |g| g.id.to_s == @draft[:goal_id].to_s }
    goal && option(goal.title, goal.id.to_s)
  end
end

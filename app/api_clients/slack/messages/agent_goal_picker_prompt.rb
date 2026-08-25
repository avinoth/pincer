# frozen_string_literal: true

# Posted (threaded) by Ai::Agent::Tools::PickGoal when a fuzzy title search
# turns up more than one candidate. The dropdown's block_id carries the paused
# AgentRun's id (see BLOCK_ID_PREFIX / Slack::Interactions::AgentPickGoalSelection),
# and each option's value is a candidate goal's id — selecting one resumes the run.
class Slack::Messages::AgentGoalPickerPrompt < Slack::Messages::Base
  ACTION_ID = "agent_pick_goal"
  BLOCK_ID_PREFIX = "agent_pick_goal_"

  def initialize(agent_run:, query:, goals:)
    @agent_run = agent_run
    @query = query
    @goals = goals
  end

  def text
    "Multiple goals match \"#{@query}\" — which one did you mean?"
  end

  def blocks
    [
      section(text),
      actions(
        [
          static_select(
            action_id: ACTION_ID,
            placeholder: "Select a goal",
            options: @goals.map { |goal| option(option_label(goal), goal.id.to_s) },
          )
        ],
        block_id: "#{BLOCK_ID_PREFIX}#{@agent_run.id}",
      )
    ]
  end

  private

  def option_label(goal)
    "#{goal.title} (#{date_range(goal)} · #{goal.status})"
  end

  def date_range(goal)
    return "no dates" if goal.start_date.blank? || goal.end_date.blank?

    "#{goal.start_date.strftime('%b %-d')}–#{goal.end_date.strftime('%b %-d, %Y')}"
  end
end

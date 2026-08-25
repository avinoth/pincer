# frozen_string_literal: true

# Posted (threaded) by Ai::Agent::Tools::PickInitiative when a fuzzy title
# search turns up more than one candidate. The dropdown's block_id carries the
# paused AgentRun's id (see BLOCK_ID_PREFIX /
# Slack::Interactions::AgentPickInitiativeSelection), and each option's value
# is a candidate initiative's id — selecting one resumes the run.
class Slack::Messages::AgentInitiativePickerPrompt < Slack::Messages::Base
  ACTION_ID = "agent_pick_initiative"
  BLOCK_ID_PREFIX = "agent_pick_initiative_"

  def initialize(agent_run:, query:, initiatives:)
    @agent_run = agent_run
    @query = query
    @initiatives = initiatives
  end

  def text
    "Multiple initiatives match \"#{@query}\" — which one did you mean?"
  end

  def blocks
    [
      section(text),
      actions(
        [
          static_select(
            action_id: ACTION_ID,
            placeholder: "Select an initiative",
            options: @initiatives.map { |initiative| option(option_label(initiative), initiative.id.to_s) },
          )
        ],
        block_id: "#{BLOCK_ID_PREFIX}#{@agent_run.id}",
      )
    ]
  end

  private

  def option_label(initiative)
    "#{initiative.title} (#{initiative.goal.title} · #{initiative.status})"
  end
end

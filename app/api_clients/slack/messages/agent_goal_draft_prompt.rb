# frozen_string_literal: true

# Posted (threaded) by the show_goal_create_form tool when the agent has enough
# of a draft to offer creating it. The prose is authored by the LLM itself —
# passed in as `message` — rather than a fixed template, and the button carries
# the paused AgentRun's id, which resumes when the button is used.
class Slack::Messages::AgentGoalDraftPrompt < Slack::Messages::Base
  ACTION_ID = "agent_open_create_goal_modal"

  def initialize(agent_run:, message:)
    @agent_run = agent_run
    @message = message
  end

  def text
    @message
  end

  def blocks
    [
      section(@message),
      actions([
        button("Create Goal", action_id: ACTION_ID, value: @agent_run.id.to_s, style: "primary")
      ])
    ]
  end
end

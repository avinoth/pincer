# frozen_string_literal: true

# Posted (threaded) by the show_initiative_create_form tool when the agent
# doesn't have enough of a draft to create the initiative directly. The prose
# is authored by the LLM itself — passed in as `message` — rather than a fixed
# template, and the button carries the paused AgentRun's id, which resumes
# when the button is used.
class Slack::Messages::AgentInitiativeDraftPrompt < Slack::Messages::Base
  ACTION_ID = "agent_open_create_initiative_modal"

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
        button("Create Initiative", action_id: ACTION_ID, value: @agent_run.id.to_s, style: "primary")
      ])
    ]
  end
end

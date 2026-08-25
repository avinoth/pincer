# frozen_string_literal: true

# Posted (threaded) by the delete_initiative tool as the confirm-first prompt
# before an initiative is actually removed. The prose is authored by the LLM
# itself — passed in as `message`, naming the initiative it's about to
# delete — and the button carries the paused AgentRun's id, which resumes
# (after the delete happens) when the button is used. The message itself is
# the confirmation: unlike the InitiativeDisplay card's Delete button, there's
# no native Slack confirm dialog layered on top.
class Slack::Messages::AgentInitiativeDeletePrompt < Slack::Messages::Base
  ACTION_ID = "agent_confirm_delete_initiative"

  def initialize(agent_run:, message:, initiative:)
    @agent_run = agent_run
    @message = message
    @initiative = initiative
  end

  def text
    @message
  end

  def blocks
    [
      section(@message),
      actions([
        button("Delete initiative", action_id: ACTION_ID, value: @agent_run.id.to_s, style: "danger")
      ])
    ]
  end
end

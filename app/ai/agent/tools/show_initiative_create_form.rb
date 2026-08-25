# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Offers to create an initiative from the agent's best-guess draft, when
      # create_initiative can't run directly (goal/owner/title aren't all
      # confidently known). Doesn't create anything itself — persists the
      # draft args onto the run and posts a Slack message with a "Create
      # Initiative" button that opens the real modal
      # (Slack::Interactions::AgentOpenCreateInitiativeModal); the modal
      # submission is what actually persists the Initiative. Always returns
      # Tools::PENDING: this tool call can only be resolved by a subsequent
      # human action in Slack, so the run must pause here (see
      # Ai::Agent::Tools::PENDING).
      class ShowInitiativeCreateForm < Base
        description "Offer to create an initiative from your best-guess draft. This does NOT " \
                    "create the initiative — it shows the user a form pre-filled with your draft, " \
                    "which they review and submit. Use this when you're missing or unsure of the " \
                    "goal, owner, or title (otherwise call create_initiative directly). Never tell " \
                    "the user the initiative exists until a later tool result confirms it."

        param :message, desc: "Short prose shown above the button that enables users to open the form — what you understood, in your voice."
        param :goal_id, type: "integer", required: false, desc: "Best-guess parent goal id, if known."
        param :title, required: false, desc: "Best-guess initiative title, if implied."
        param :owner, required: false, desc: "Best-guess owner's Slack user id, taken from a <@...> mention, if implied."
        param :description, required: false, desc: "Best-guess longer description, if implied."

        def execute(message:, goal_id: nil, title: nil, owner: nil, description: nil)
          args = {
            goal_id: goal_id,
            title: title,
            owner: owner,
            description: description
          }.compact

          persist_draft(args)
          post_prompt(message)

          Tools::PENDING
        rescue StandardError => e
          { error: "Couldn't show the initiative creation form: #{e.message}" }
        end

        private

        # Draft args land under pending_tool_call["args"]; the runner is
        # responsible for the sibling id/name bookkeeping on the same hash, so
        # we merge rather than overwrite.
        def persist_draft(args)
          agent_run = context.agent_run
          pending = (agent_run.pending_tool_call || {}).stringify_keys
          pending["args"] = args.stringify_keys
          agent_run.update!(pending_tool_call: pending)
        end

        def post_prompt(message)
          prompt = Slack::Messages::AgentInitiativeDraftPrompt.new(agent_run: context.agent_run, message: message)

          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            prompt.to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end
      end
    end
  end
end

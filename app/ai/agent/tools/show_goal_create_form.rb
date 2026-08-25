# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Offers to create a goal from the agent's best-guess draft. Doesn't
      # create anything itself — persists the draft args onto the run and posts
      # a Slack message with a "Create Goal" button that opens the real modal
      # (Slack::Interactions::AgentOpenCreateGoalModal); the modal submission is
      # what actually persists the Goal. Always returns Tools::PENDING: this
      # tool call can only be resolved by a subsequent human action in Slack,
      # so the run must pause here (see Ai::Agent::Tools::PENDING).
      class ShowGoalCreateForm < Base
        description "Offer to create a goal from your best-guess draft. This does NOT create " \
                    "the goal — it shows the user a form pre-filled with your draft, which they " \
                    "review and submit. Never tell the user the goal exists until a later tool " \
                    "result confirms it was actually created."

        param :message, desc: "Short prose shown above the button that enables users to open the form — what you understood, in your voice."
        param :title, desc: "Best-guess goal title."
        param :description, required: false, desc: "Best-guess longer description, if implied."
        param :start_date, required: false, desc: "ISO8601 date (YYYY-MM-DD), if implied."
        param :end_date, required: false, desc: "ISO8601 date (YYYY-MM-DD), if implied."
        param :metric_name, required: false, desc: "Primary metric name, e.g. \"MRR\", if implied."
        param :metric_direction, type: "string", required: false,
              desc: "\"increase\" or \"decrease\", only if clearly implied."
        param :metric_start_value, type: "number", required: false, desc: "Metric baseline value, if stated."
        param :metric_target_value, type: "number", required: false, desc: "Metric target value, if stated."
        param :metric_unit, required: false, desc: "Metric unit, e.g. \"%\" or \"$\", if implied."

        def execute(message:, title:, description: nil, start_date: nil, end_date: nil,
                    metric_name: nil, metric_direction: nil, metric_start_value: nil,
                    metric_target_value: nil, metric_unit: nil)
          args = {
            title: title,
            description: description,
            start_date: start_date,
            end_date: end_date,
            metric_name: metric_name,
            metric_direction: metric_direction,
            metric_start_value: metric_start_value,
            metric_target_value: metric_target_value,
            metric_unit: metric_unit
          }.compact

          persist_draft(args)
          post_prompt(message)

          Tools::PENDING
        rescue StandardError => e
          { error: "Couldn't show the goal creation form: #{e.message}" }
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
          prompt = Slack::Messages::AgentGoalDraftPrompt.new(agent_run: context.agent_run, message: message)

          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            prompt.to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end
      end
    end
  end
end

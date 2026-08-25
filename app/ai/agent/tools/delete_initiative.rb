# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Confirm-first delete: never deletes anything itself. Persists the
      # initiative_id onto the run and posts a Slack message with a danger
      # "Delete initiative" button
      # (Slack::Interactions::AgentConfirmDeleteInitiative); only that click
      # actually calls ::DeleteInitiative. Always returns Tools::PENDING —
      # deletion is irreversible, so this pauses the run for a human to
      # confirm rather than trusting the model's own judgment (see
      # Tools::PENDING).
      #
      # Scoped to the current organization (via the parent goal) — an
      # initiative_id from another org is treated as not found. Gated on
      # Initiative#modifiable_by? — only the initiative's owner or the parent
      # goal's creator/owners may delete it.
      class DeleteInitiative < Base
        description "Delete an initiative permanently. This does NOT delete the initiative itself " \
                    "— it posts a confirmation button the user must click before anything is " \
                    "removed. Requires a concrete initiative_id (use pick_initiative first if the " \
                    "user's reference is ambiguous). Never tell the user the initiative is gone " \
                    "until a later tool result confirms it."

        param :initiative_id, type: "integer",
              desc: "The initiative's id, as returned by pick_initiative, create_initiative, or edit_initiative."
        param :message, desc: "Short prose shown above the confirm button, in your own voice — name the initiative being deleted."

        def execute(initiative_id:, message:)
          initiative = organization_initiatives.find_by(id: initiative_id)
          return { error: "No initiative found with id #{initiative_id}." } unless initiative
          unless initiative.modifiable_by?(context.user&.provider_uid)
            return { error: "Only the initiative's owner or the goal's owners/creator can delete it." }
          end

          persist_draft({ "initiative_id" => initiative_id })
          post_prompt(message, initiative)

          Tools::PENDING
        rescue StandardError => e
          { error: "Couldn't show the delete confirmation for initiative #{initiative_id}: #{e.message}" }
        end

        private

        # Org-scoped via the parent goal — an initiative_id from another org is
        # treated as not found rather than leaking across organizations.
        def organization_initiatives
          Initiative.joins(:goal).where(goals: { organization_id: context.organization.id })
        end

        # Draft args land under pending_tool_call["args"]; the runner is
        # responsible for the sibling id/name bookkeeping on the same hash, so
        # we merge rather than overwrite (see show_goal_create_form.rb#persist_draft).
        def persist_draft(args)
          agent_run = context.agent_run
          pending = (agent_run.pending_tool_call || {}).stringify_keys
          pending["args"] = args
          agent_run.update!(pending_tool_call: pending)
        end

        def post_prompt(message, initiative)
          prompt = Slack::Messages::AgentInitiativeDeletePrompt.new(
            agent_run: context.agent_run, message: message, initiative: initiative,
          )

          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            prompt.to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end
      end
    end
  end
end

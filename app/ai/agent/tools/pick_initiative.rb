# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Reusable fuzzy disambiguator: resolves a free-text initiative reference
      # (e.g. "the onboarding initiative") to a concrete initiative_id before a
      # tool like edit_initiative, which requires one, can run. Mirrors
      # pick_goal.rb.
      #
      # Zero or a single match resolve inline, with no pause. Two-to-25 matches
      # can't be resolved by the model alone, so this pauses the run
      # (Tools::PENDING) and posts a Slack dropdown
      # (Slack::Messages::AgentInitiativePickerPrompt); the run resumes once a
      # human picks one (see Slack::Interactions::AgentPickInitiativeSelection),
      # and the chosen initiative is fed back into the transcript as if this
      # tool had returned it directly.
      class PickInitiative < Base
        MAX_CANDIDATES = 25

        description "Resolve a free-text or ambiguous initiative reference (e.g. a title " \
                    "fragment) to a concrete initiative, by fuzzy title match, optionally scoped " \
                    "to one goal. A single match resolves immediately. Multiple matches pause this " \
                    "turn so the user can pick one from a dropdown — wait for that pick before " \
                    "proceeding. Use this before edit_initiative whenever the user didn't give you " \
                    "an exact initiative_id."

        param :query, desc: "Title or title fragment to search for, e.g. \"onboarding\"."
        param :goal_id, type: "integer", required: false, desc: "Restrict the search to this goal's initiatives, if known."

        def execute(query:, goal_id: nil)
          matches = candidate_scope(goal_id).where("initiatives.title ILIKE ?", "%#{query}%")
            .order("initiatives.title").limit(MAX_CANDIDATES + 1).to_a

          return { error: "No initiative matches '#{query}'. Ask the user to rephrase." } if matches.empty?
          return summarize(matches.first) if matches.size == 1
          return { error: "Too many initiatives match; ask the user to narrow." } if matches.size > MAX_CANDIDATES

          stash_candidates(matches)
          post_picker(query, matches)

          Tools::PENDING
        rescue StandardError => e
          { error: "Couldn't search initiatives for '#{query}': #{e.message}" }
        end

        private

        def candidate_scope(goal_id)
          scope = Initiative.joins(:goal).where(goals: { organization_id: context.organization.id })
          goal_id.present? ? scope.where(goal_id: goal_id) : scope
        end

        def summarize(initiative)
          {
            id: initiative.id,
            title: initiative.title,
            goal_id: initiative.goal_id,
            owner: initiative.owner&.full_name,
            status: initiative.status
          }
        end

        # Candidate ids land under pending_tool_call["args"]; the runner is
        # responsible for the sibling id/name bookkeeping on the same hash, so
        # we merge rather than overwrite (see show_goal_create_form.rb#persist_draft).
        def stash_candidates(initiatives)
          agent_run = context.agent_run
          pending = (agent_run.pending_tool_call || {}).stringify_keys
          pending["args"] = { "candidate_initiative_ids" => initiatives.map(&:id) }
          agent_run.update!(pending_tool_call: pending)
        end

        def post_picker(query, initiatives)
          prompt = Slack::Messages::AgentInitiativePickerPrompt.new(
            agent_run: context.agent_run, query: query, initiatives: initiatives,
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
